extends Node
## Autoloaded as `Actions`. Player-facing action pipeline.
##
## Flow:
##   1. issue(action_id, target_id)  -> builds a PendingAction descriptor,
##      schedules resolution via Scheduler (delay in game-days drawn from
##      the ActionDefinition's min/max range), emits EventBus.action_issued.
##   2. Scheduler.task_due  -> we recognise "action_resolution" tasks,
##      roll for success, assemble an intelligence report Letter, hand
##      it to the Inbox via EventBus.letter_delivered, and emit
##      EventBus.action_resolved.
##
## This is the core loop for Phase 0 (§ROADMAP exit criteria).

const ACTION_DATA_PATH: String = "res://data/actions.json"
const TASK_KIND: StringName = &"action_resolution"

## The five outcomes of a bribery attempt (§17.4). These are richer
## than the generic pass/fail axis and have distinct side effects:
## rumours, loud rejections, counter-leverage. The resolver writes
## one of these into `extras["bribe_outcome"]` for the report builder.
enum BribeOutcome {
	CLEAN_SUCCESS,     # accepted, silent, delivered.
	MESSY_SUCCESS,     # accepted, but they talked — rumour enters.
	SILENT_FAILURE,    # refused quietly. No new noise.
	LOUD_FAILURE,      # refused publicly; player exposure + relationship fall.
	COUNTER_LEVERAGED, # refused AND sold the approach to a rival.
}

## Set of bribe variants (§17.2). Any action whose id is in this set
## takes the five-outcome resolution path.
const BRIBE_IDS: Array[StringName] = [
	&"bribe_direct", &"bribe_retainer", &"bribe_career",
	&"bribe_info", &"bribe_gift",
]

# action_id (StringName) -> ActionDefinition
var definitions: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_load_from_json(ACTION_DATA_PATH)
	Scheduler.task_due.connect(_on_task_due)
	Finance.retainer_turned.connect(_on_retainer_turned)
	Finance.retainer_at_risk.connect(_on_retainer_at_risk)
	print("[Actions] Loaded %d action definitions" % definitions.size())


# --- Public API --------------------------------------------------------------

func get_definition(action_id: StringName) -> ActionDefinition:
	return definitions.get(action_id, null)


func all_definitions() -> Array[ActionDefinition]:
	var out: Array[ActionDefinition] = []
	for d in definitions.values():
		out.append(d)
	return out


## Queue an action. `target_id` may be empty for NONE-target actions.
## Returns the scheduler handle or Scheduler.INVALID_HANDLE on failure.
func issue(action_id: StringName, target_id: String = "") -> int:
	var def: ActionDefinition = get_definition(action_id)
	if def == null:
		push_warning("[Actions] Unknown action: %s" % action_id)
		return Scheduler.INVALID_HANDLE

	if def.target_kind != ActionDefinition.TargetKind.NONE and target_id.is_empty():
		push_warning("[Actions] Action '%s' requires a target" % action_id)
		return Scheduler.INVALID_HANDLE

	if def.requires_host_target:
		var host: Actor = Actors.get_actor(StringName(target_id))
		if host == null or not host.is_host():
			push_warning("[Actions] Action '%s' requires a loyal host; '%s' is not one." %
				[action_id, target_id])
			return Scheduler.INVALID_HANDLE

	# Org-specific preconditions: promote_coordinator requires a loyal
	# non-ruler host who isn't already in the org; promote_lieutenant
	# requires an existing seasoned Coordinator.
	if action_id == &"promote_coordinator":
		if not _valid_coordinator_candidate(target_id):
			push_warning("[Actions] promote_coordinator: '%s' is not a valid candidate." % target_id)
			return Scheduler.INVALID_HANDLE
	elif action_id == &"promote_lieutenant":
		if not _valid_lieutenant_candidate(target_id):
			push_warning("[Actions] promote_lieutenant: '%s' is not a valid coordinator." % target_id)
			return Scheduler.INVALID_HANDLE
	elif action_id == &"audit_cell":
		var am: OrgMember = Org.get_member(StringName(target_id))
		if am == null or am.burned or am.layer == OrgMember.Layer.OPERATIVE:
			push_warning("[Actions] audit_cell: '%s' is not an auditable member." % target_id)
			return Scheduler.INVALID_HANDLE
	elif action_id == &"run_double_agent":
		var dm: OrgMember = Org.get_member(StringName(target_id))
		if dm == null or dm.burned or not dm.suspected_compromised:
			push_warning("[Actions] run_double_agent: '%s' is not suspected or not eligible." % target_id)
			return Scheduler.INVALID_HANDLE
		if dm.double_agent:
			push_warning("[Actions] run_double_agent: '%s' is already running as a double." % target_id)
			return Scheduler.INVALID_HANDLE
	elif action_id == &"intel_cross_reference" or action_id == &"intel_source_audit":
		var im: OrgMember = Org.get_member(StringName(target_id))
		if im == null or im.burned:
			push_warning("[Actions] %s: '%s' is not a valid member." % [action_id, target_id])
			return Scheduler.INVALID_HANDLE

	if not Exposure.allows_tier(def.tier):
		push_warning("[Actions] Action '%s' blocked by exposure level: %s" %
			[action_id, Exposure.level_name()])
		return Scheduler.INVALID_HANDLE

	# Funding (§16). Costly actions prefer the banking network —
	# one of the player's houses carries the bill. If no route covers
	# the spend, fall back to the physical purse (emergency coin).
	# Promotions, being conversations not payments, always come from
	# the purse: you do not route a promotion through a merchant.
	var funding: Dictionary = {}
	var used_purse: bool = false
	if def.silver_cost > 0:
		var dest_kingdom: String = _kingdom_of_target(def, target_id)
		var prefer_network: bool = dest_kingdom != "" \
				and action_id != &"promote_coordinator" \
				and action_id != &"promote_lieutenant"
		if prefer_network:
			funding = Finance.fund(
				dest_kingdom,
				def.silver_cost,
				_default_route_for(def),
				action_id
			)
		if funding.is_empty() or not bool(funding.get("ok", false)):
			if not Purse.can_afford(def.silver_cost):
				push_warning(("[Actions] Action '%s' refused: no bank route for %d "
					+ "silver and purse cannot cover the shortfall.") %
					[action_id, def.silver_cost])
				return Scheduler.INVALID_HANDLE
			Purse.spend(def.silver_cost)
			used_purse = true
			funding = {}

	# Routing (§14.2). If the player has a coordinator in the target's
	# kingdom, the dispatch goes through them: a modest delay is added,
	# exposure is dampened, and a coordinator id rides on the descriptor
	# so the resolution handler can tilt success and award trust.
	var coord: OrgMember = _coordinator_for_target(def, target_id)
	var dispatch_delay: int = 0
	if coord != null:
		dispatch_delay = _rng.randi_range(5, 12)

	# Funded routes add their own latency on top of dispatch delay.
	var funding_delay: int = int(funding.get("delay_days", 0))

	var delay: int = _rng.randi_range(def.min_days_to_resolve, def.max_days_to_resolve) \
			+ dispatch_delay + funding_delay
	var fire_day: int = GameClock.absolute_day() + delay

	var descriptor: Dictionary = {
		"kind":          String(TASK_KIND),
		"action_id":     String(action_id),
		"target_id":     target_id,
		"issued_day":    GameClock.absolute_day(),
		"fire_day":      fire_day,
		"silver_cost":   def.silver_cost,
		"exposure_cost": def.exposure_cost,
		"coordinator_id": String(coord.id) if coord != null else "",
		"funded_via":    String(funding.get("house_id", "")),
		"funded_route":  int(funding.get("_route_option", _default_route_for(def))),
		"used_purse":    used_purse,
	}

	var handle: int = Scheduler.schedule_task_on_day(fire_day, descriptor)
	EventBus.action_issued.emit(action_id, descriptor.duplicate(true))
	print("[Actions] Issued '%s' vs '%s'; resolves in %d days (day %d)%s." %
		[action_id, target_id, delay, fire_day,
		"" if coord == null else " via %s" % coord.display_name])
	return handle


## Pick a default funding route for an action. The player will be
## able to override this through a future compose-view toggle; for
## now the heuristic is "match discretion to exposure tier". Loud
## actions go through heavy laundering; quiet ones route directly
## so we don't waste capacity.
func _default_route_for(def: ActionDefinition) -> int:
	match def.tier:
		ActionDefinition.Tier.DEEP_SHADOW:
			return Finance.RoutingOption.DIRECT
		ActionDefinition.Tier.ACTIVE:
			return Finance.RoutingOption.SINGLE_INTERMEDIARY
		ActionDefinition.Tier.HIGH:
			return Finance.RoutingOption.MULTI_HOP
	return Finance.RoutingOption.DIRECT


## Coordinator routing only applies to actions that have a concrete
## kingdom-bound target. Promotions and rituals don't route — they're
## done by the player directly with the candidate.
func _coordinator_for_target(def: ActionDefinition, target_id: String) -> OrgMember:
	if def.id == &"promote_coordinator" or def.id == &"promote_lieutenant":
		return null
	var kid: String = _kingdom_of_target(def, target_id)
	if kid.is_empty():
		return null
	return Org.coverage_for(kid)


func _kingdom_of_target(def: ActionDefinition, target_id: String) -> String:
	match def.target_kind:
		ActionDefinition.TargetKind.ACTOR:
			var a: Actor = Actors.get_actor(StringName(target_id))
			return a.kingdom_id if a != null else ""
		ActionDefinition.TargetKind.KINGDOM:
			return target_id
		ActionDefinition.TargetKind.PROVINCE:
			var p: Province = WorldData.get_province(target_id)
			return p.owning_kingdom if p != null else ""
		ActionDefinition.TargetKind.ORG_MEMBER:
			var m: OrgMember = Org.get_member(StringName(target_id))
			return m.region_id if m != null else ""
		_:
			return ""


func _valid_coordinator_candidate(target_id: String) -> bool:
	var a: Actor = Actors.get_actor(StringName(target_id))
	if a == null or not a.is_alive():
		return false
	if a.role == Actor.Role.RULER:
		return false
	if not a.is_host():
		return false
	if Org.is_actor_member(a.id):
		return false
	return true


func _valid_lieutenant_candidate(target_id: String) -> bool:
	var m: OrgMember = Org.member_for_actor(StringName(target_id))
	if m == null or m.burned:
		return false
	if m.layer != OrgMember.Layer.COORDINATOR:
		return false
	if m.trust < 70:
		return false
	if m.tenure_days < 365:
		return false
	return true


## Voluntarily burn a coordinator's cell (§14.2 rollback). Unlike a
## pending action, this resolves immediately: the coordinator and every
## operative under them are marked burned; the player's global Exposure
## ticks up a little (voluntary burns still leave smoke); a letter is
## dropped into the inbox so the act is recorded in the Memoirs.
##
## Returns true if the cell was actually severed, false if the id was
## invalid, already burned, or not a coordinator.
func sever_cell(coord_id: StringName) -> bool:
	var coord: OrgMember = Org.get_member(coord_id)
	if coord == null or coord.burned:
		return false
	if coord.layer != OrgMember.Layer.COORDINATOR:
		return false

	var region: String = coord.region_id
	var k: Kingdom = WorldData.get_kingdom(region)
	var region_name: String = k.kingdom_name if k != null else region
	var coord_name: String = coord.display_name

	# Burn every operative under them first so the cascade in
	# OrgRegistry.burn_member doesn't misfire heat upward.
	var ops: Array[OrgMember] = []
	for m in Org.all_members():
		if not m.burned and m.superior_id == coord_id \
				and m.layer == OrgMember.Layer.OPERATIVE:
			ops.append(m)
	for op in ops:
		Org.burn_member(op.id, &"severed")

	Org.burn_member(coord_id, &"severed")

	# Cost of a voluntary rollback. Smaller than a failed HIGH action
	# would cost but not free — rumours travel, neighbours notice a
	# merchant who vanished overnight.
	Exposure.bump(3.0, "severed_cell")

	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var body: String = (
		"I have ordered the cell around %s dissolved. The operatives are out of the "
		+ "city by the second watch; the ledgers have been burned; the rented rooms "
		+ "surrendered to their landlords with a month's silver in apology.\n\n"
		+ "%s themselves is warned but not reached. They will notice the absence "
		+ "of their hands over the coming weeks. Whether they keep silent, or go "
		+ "looking, is no longer something we control.\n\n"
		+ "The %s work is dark now. We will rebuild when you judge the heat has passed."
	) % [region_name, coord_name, region_name]
	var letter: Letter = Letter.create(
		StringName("sever_%s_%d" % [coord_id, Time.get_ticks_msec()]),
		"Your factotum",
		date,
		"The %s cell has been burned" % region_name,
		body,
		&"action"
	)
	EventBus.letter_delivered.emit(letter)
	return true


func pending_count() -> int:
	# Scheduler is the single source of truth for queued action resolutions.
	var count: int = 0
	for task in Scheduler.snapshot():
		var desc: Dictionary = task.get("descriptor", {})
		if String(desc.get("kind", "")) == String(TASK_KIND):
			count += 1
	return count


# --- Scheduler hook ----------------------------------------------------------

func _on_task_due(descriptor: Dictionary) -> void:
	if String(descriptor.get("kind", "")) != String(TASK_KIND):
		return
	_resolve(descriptor)


func _resolve(descriptor: Dictionary) -> void:
	var action_id: StringName = StringName(String(descriptor.get("action_id", "")))
	var target_id: String     = String(descriptor.get("target_id", ""))
	var coord_id:  StringName = StringName(String(descriptor.get("coordinator_id", "")))
	var coord: OrgMember = Org.get_member(coord_id) if coord_id != &"" else null

	var def: ActionDefinition = get_definition(action_id)
	if def == null:
		push_warning("[Actions] Cannot resolve unknown action: %s" % action_id)
		return

	var success_chance: float = _modified_success_chance(def, target_id)
	if coord != null and not coord.burned:
		# Skilled coverage lifts the ceiling. Capped so a 90-skill
		# coordinator doesn't make everything a coin flip -> near-cert.
		# Uses effective_skill so an over-stretched coord is actually
		# less reliable than a comfortable one, per §14.1.
		var usable: int = Org.effective_skill(coord.id)
		success_chance = clampf(success_chance + float(usable) / 400.0, 0.05, 0.97)

	# Bribery uses a 5-outcome resolution (§17.4). Compute up-front so
	# the rest of _resolve can read `success` as the reduced pass/fail.
	var bribe_outcome: int = -1
	var success: bool
	if BRIBE_IDS.has(action_id):
		bribe_outcome = _roll_bribe_outcome(action_id, target_id, descriptor)
		success = bribe_outcome == BribeOutcome.CLEAN_SUCCESS \
				or bribe_outcome == BribeOutcome.MESSY_SUCCESS
	else:
		success = _rng.randf() < success_chance

	# Apply relationship changes BEFORE the report is built so the tone
	# of future letters can lean on the new standing if we ever want
	# that. The returned delta is echoed to the log for debugging.
	var rel_delta: int = _apply_relationship_effects(def, target_id, success)

	# Side-effects that should be resolved BEFORE the report is written,
	# so the report text can name whoever was quieted.
	var extras: Dictionary = _apply_special_effects(def, target_id, success)

	# Apply bribe-specific after-effects now that extras exists.
	if bribe_outcome >= 0:
		extras["bribe_outcome"] = bribe_outcome
		_apply_bribe_effects(def, target_id, bribe_outcome, extras)

	# Promotions are structural state changes to the Org, not flavour.
	# Handle them here so the report can describe the new role.
	_apply_org_effects(def, target_id, success, extras)

	if coord != null and not coord.burned:
		extras["coordinator_name"] = coord.display_name
		extras["coordinator_id"]   = String(coord.id)

	var report: Letter = _build_report(def, target_id, success, extras)
	EventBus.letter_delivered.emit(report)

	if success:
		_maybe_publish_public_trace(def, target_id)
	_apply_failure_consequences(def, success, coord)

	# Feed the organisation. Successful routed work builds trust and a
	# pinch of skill; failure bleeds both and heats the operative layer.
	if coord != null and not coord.burned:
		if success:
			Org.adjust_trust(coord.id, 2)
		else:
			Org.adjust_trust(coord.id, -2)

	EventBus.action_resolved.emit(action_id, {
		"success":        success,
		"target_id":      target_id,
		"summary":        report.subject,
		"rel_delta":      rel_delta,
		"routed_via":     String(coord.id) if coord != null else "",
	})


## Bribery outcome tree (§17.1 + §17.4). Susceptibility is type-specific:
## direct payment rewards greed; career offers reward ambition; gift
## rewards existing warmth; information trade fits targets with high
## intellect and low principle. Paranoia shifts everything toward
## LOUD_FAILURE because an offer reads as a trap.
##
## We also read the funded route's discretion: a rumour is much more
## likely when the silver moved through a direct payment than when it
## was wrapped inside a shipment of wine.
func _roll_bribe_outcome(action_id: StringName, target_id: String, descriptor: Dictionary) -> int:
	var a: Actor = Actors.get_actor(StringName(target_id))
	if a == null:
		return BribeOutcome.SILENT_FAILURE

	# Weights for each outcome. Begin from a neutral baseline and
	# push around based on trait fit and financial discretion.
	var w_clean: float = 35.0
	var w_messy: float = 18.0
	var w_silent: float = 22.0
	var w_loud: float = 15.0
	var w_counter: float = 10.0

	# Trait affinities by offer type.
	match action_id:
		&"bribe_direct":
			w_clean  += float(a.greed) * 0.6
			w_silent += float(100 - a.greed) * 0.3
			w_loud   += float(a.paranoia) * 0.4
			# High loyalty: unmoved unless relationship to us is already bad.
			if a.loyalty > 70 and a.relationship > -20:
				w_loud  += 25.0
				w_clean -= 25.0
		&"bribe_retainer":
			w_clean  += float(a.greed) * 0.5
			w_clean  += float(max(0, 60 - a.loyalty)) * 0.3
			w_messy  += 8.0   # ongoing arrangements leak more.
			w_loud   += float(a.paranoia) * 0.3
		&"bribe_career":
			w_clean  += float(a.ambition) * 0.6
			w_silent += float(100 - a.ambition) * 0.3
			# Career offers to a loyal subordinate read better than
			# direct silver — it doesn't feel like a bribe.
			w_loud   += float(max(0, a.loyalty - 60)) * 0.25
		&"bribe_info":
			w_clean  += float(a.intellect) * 0.4
			w_clean  += float(100 - a.piety) * 0.2
			# High-principle / high-piety targets refuse the trade.
			w_loud   += float(a.piety) * 0.3
			w_counter += float(a.ambition) * 0.25  # they may resell.
		&"bribe_gift":
			w_clean  += 15.0
			w_silent += 15.0
			w_loud   -= 10.0
			w_counter -= 5.0
			# Gifts bend with relationship more than anything else.
			w_clean += float(max(0, a.relationship)) * 0.3
			w_loud  -= float(max(0, a.relationship)) * 0.15

	# Discretion of the funded route. DIRECT leaks, embedded-trade
	# is nearly invisible. Only applies if we actually moved silver.
	var route_option: int = int(descriptor.get("funded_route", -1))
	if route_option != -1:
		match route_option:
			Finance.RoutingOption.DIRECT:
				w_messy   += 10.0
				w_counter += 4.0
			Finance.RoutingOption.SINGLE_INTERMEDIARY:
				pass
			Finance.RoutingOption.MULTI_HOP:
				w_messy   -= 6.0
				w_counter -= 3.0
			Finance.RoutingOption.EMBEDDED_TRADE:
				w_messy   -= 10.0
				w_counter -= 5.0
				w_clean   += 6.0

	# Paranoia globally pushes toward LOUD_FAILURE — they smell a trap.
	if a.paranoia >= 70:
		w_loud  += 15.0
		w_clean -= 10.0

	# Clamp to non-negative.
	var weights: Array[float] = [
		maxf(1.0, w_clean),
		maxf(1.0, w_messy),
		maxf(1.0, w_silent),
		maxf(1.0, w_loud),
		maxf(1.0, w_counter),
	]
	return _weighted_pick(weights)


func _weighted_pick(weights: Array[float]) -> int:
	var total: float = 0.0
	for w in weights:
		total += w
	var roll: float = _rng.randf() * total
	var acc: float = 0.0
	for i in range(weights.size()):
		acc += weights[i]
		if roll <= acc:
			return i
	return weights.size() - 1


## Side-effects for each outcome of a bribe. This runs before the
## report is written; the report text branches on `extras["bribe_outcome"]`.
func _apply_bribe_effects(def: ActionDefinition, target_id: String, outcome: int, extras: Dictionary) -> void:
	var a: Actor = Actors.get_actor(StringName(target_id))

	match outcome:
		BribeOutcome.CLEAN_SUCCESS:
			# Retainer bribes open a dependent relationship.
			if def.id == &"bribe_retainer" and a != null:
				@warning_ignore("integer_division")
				var monthly: int = maxi(20, def.silver_cost / 6)
				Finance.register_retainer(a.id, monthly)
				extras["retainer_opened"] = true
				extras["retainer_monthly"] = monthly

		BribeOutcome.MESSY_SUCCESS:
			# Still works, but a rumour enters the street about
			# someone buying this figure. Whispers links the rumour
			# to the target so intel-checkers can find the trail.
			if a != null:
				Whispers.register(&"bribe_trace", a.id)
				var line: String = "was seen accepting silver from a stranger"
				if def.id == &"bribe_career":
					line = "has been promised a door at a better court"
				elif def.id == &"bribe_gift":
					line = "has received gifts their station does not easily explain"
				EventBus.public_event.emit({
					"sender":   "Whispers in the agora",
					"subject":  "A matter involving %s" % a.display_name(),
					"body":     ("It is said — with the usual unreliability — that %s %s."
								+ " No name attaches to the other hand.") % [a.display_name(), line],
					"kingdom":  a.kingdom_id,
					"actor_id": String(a.id),
				})

		BribeOutcome.SILENT_FAILURE:
			# No extra noise. Relationship softens a touch either way;
			# handled in _apply_relationship_effects fallback.
			pass

		BribeOutcome.LOUD_FAILURE:
			# Relationship sours; exposure takes a direct hit because
			# the target is telling people what was offered.
			if a != null:
				Actors.adjust_relationship(a.id, -10)
			Exposure.bump(4.0, "loud_bribe_refusal")
			if a != null:
				EventBus.public_event.emit({
					"sender":   "Gossip at the temple steps",
					"subject":  "A foolish offer",
					"body":     ("%s has told the story over wine: a stranger, a purse, "
								+ "and a request that made them laugh and then frown. "
								+ "They do not name the stranger. They do, however, "
								+ "name themselves — and everyone is listening.") % a.display_name(),
					"kingdom":  a.kingdom_id,
					"actor_id": String(a.id),
				})

		BribeOutcome.COUNTER_LEVERAGED:
			# Worst case: target sold the approach to another interested
			# party. Model the leak by bumping curiosity on any funded
			# house (their records now sit in another lap) and by a
			# bigger exposure hit than a loud failure.
			if a != null:
				Actors.adjust_relationship(a.id, -6)
			Exposure.bump(6.0, "counter_leveraged_bribe")
			if a != null:
				# Register the leak as a whisper trail so later
				# intel work can discover who the rival buyer was.
				Whispers.register(&"counter_leverage", a.id)
				EventBus.public_event.emit({
					"sender":   "A courier you do not employ",
					"subject":  "Your approach has been sold",
					"body":     ("%s refused your offer and then walked it, word for word, "
								+ "to somebody with sharper teeth. You must assume that party "
								+ "now knows there is a hand in this city that reaches their way."
								) % a.display_name(),
					"kingdom":  a.kingdom_id,
					"actor_id": String(a.id),
				})


## Retainer unpaid: the dependent turned. Light the table up — this
## is one of the most dangerous things a player can have happen.
func _on_retainer_turned(retainer: Dictionary) -> void:
	var actor_id: String = String(retainer.get("actor_id", ""))
	var a: Actor = Actors.get_actor(StringName(actor_id))
	var display: String = a.display_name() if a != null else actor_id
	if a != null:
		Actors.adjust_relationship(a.id, -25)
	Exposure.bump(8.0, "retainer_turned")

	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var body: String = (
		"%s has not been paid in three months, and they have found a louder patron. "
		+ "They are carrying what they know of your network into a room you are not in. "
		+ "Their memory of the arrangement is imperfect, but it is more than we want "
		+ "any stranger to carry.\n\nWe must assume the approach was lost."
	) % display
	var letter: Letter = Letter.create(
		StringName("retainer_turned_%d" % Time.get_ticks_msec()),
		"Your paymaster",
		date,
		"A dependent has found another room",
		body,
		&"action"
	)
	EventBus.letter_delivered.emit(letter)


## Retainer merely at risk — one missed month. Quiet warning, no
## player exposure yet; the Memoirs will surface it via the monthly
## digest rather than a dedicated letter.
func _on_retainer_at_risk(retainer: Dictionary, _reason: StringName) -> void:
	var actor_id: String = String(retainer.get("actor_id", ""))
	print("[Actions] Retainer %s is one month behind; %d/%d missed." % [
		actor_id,
		int(retainer.get("missed_months", 0)),
		Finance.RETAINER_MISS_LIMIT,
	])


## Org-structural side effects — the promotion lines on the scroll
## have to actually change the Roster, not just describe it. Hooked
## in before the report is authored so the letter can name the new
## coordinator/lieutenant in-role.
func _apply_org_effects(def: ActionDefinition, target_id: String, success: bool, extras: Dictionary) -> void:
	if not success:
		return
	match def.id:
		&"promote_coordinator":
			var m: OrgMember = Org.promote_actor_to_coordinator(StringName(target_id))
			if m != null:
				extras["new_member_id"]   = String(m.id)
				extras["new_member_name"] = m.display_name
				extras["new_layer"]       = m.layer_name()
		&"promote_lieutenant":
			var existing: OrgMember = Org.member_for_actor(StringName(target_id))
			if existing != null:
				var lt: OrgMember = Org.promote_coordinator_to_lieutenant(existing.id)
				if lt != null:
					extras["new_member_id"]   = String(lt.id)
					extras["new_member_name"] = lt.display_name
					extras["new_layer"]       = lt.layer_name()
		_:
			pass


## Side-effects that aren't pure "report flavour" — the player's act of
## issuing this letter actually mutates the simulation. Returns a dict
## of extras consumed by `_build_report` so the report can reference
## whom (or what) was affected. Keep this limited to things that only
## one specific action does; everything broad goes in
## `_apply_relationship_effects` or `_maybe_publish_public_trace`.
func _apply_special_effects(def: ActionDefinition, target_id: String, success: bool) -> Dictionary:
	var out: Dictionary = {}
	match def.id:
		&"intel_cross_reference":
			_apply_cross_reference(target_id, success, out)
		&"intel_source_audit":
			_apply_source_audit(target_id, success, out)
		&"intel_reinvestigate":
			_apply_reinvestigate(target_id, success, out)
		&"audit_cell":
			_apply_audit_cell(target_id, success, out)
		&"run_double_agent":
			_apply_run_double_agent(target_id, success, out)
		&"investigate_anomaly":
			_apply_investigate_anomaly(target_id, success, out)
		&"cross_reference_pattern":
			_apply_cross_reference_pattern(target_id, success, out)
		&"match_fingerprint":
			_apply_match_fingerprint(target_id, success, out)
		&"sweep_for_rivals":
			_apply_sweep_for_rivals(target_id, success, out)
		&"neutralize_rival_operative":
			_apply_neutralize_rival(target_id, success, out)
		&"turn_rival_operative":
			_apply_turn_rival(target_id, success, out)
		&"quiet_plot":
			var plotter: Actor = WorldAI.top_plotter_in(target_id)
			if plotter != null:
				out["plotter_name"] = plotter.display_name()
				out["plotter_id"]   = String(plotter.id)
				if success:
					WorldAI.cool_plotter(plotter.id)
		&"fan_border":
			var neighbour: String = Relations.worst_neighbour_of(target_id)
			if neighbour.is_empty():
				# Pick any random foreign kingdom as the inflamed frontier.
				for other in WorldData.kingdoms.keys():
					var id: String = String(other)
					if id != target_id:
						neighbour = id
						break
			if not neighbour.is_empty():
				var n: Kingdom = WorldData.get_kingdom(neighbour)
				if n != null:
					out["neighbour_name"] = n.kingdom_name
					out["neighbour_id"]   = neighbour
				var before: int = Relations.state_between(target_id, neighbour)
				out["before_state"] = before
				if success:
					Relations.step_worse(target_id, neighbour)
					out["after_state"] = Relations.state_between(target_id, neighbour)
				else:
					out["after_state"] = before
		_:
			pass
	return out


## §18.2 Cross-reference: fast, silent, useful only when other sources
## cover the same ground. We simulate that coverage by checking whether
## at least one other non-burned member reports from the same region;
## without a corroborator, we cannot contradict anything.
func _apply_cross_reference(target_id: String, success: bool, out: Dictionary) -> void:
	var m: OrgMember = Org.get_member(StringName(target_id))
	if m == null:
		return
	out["member_name"] = m.display_name
	out["member_layer"] = m.layer_name()

	var corroborators: int = 0
	for other in Org.all_members():
		if other.burned or other.id == m.id:
			continue
		if other.region_id == m.region_id:
			corroborators += 1
	out["corroborators"] = corroborators

	if corroborators == 0:
		out["verdict"] = &"no_coverage"
		return

	# Chance of finding a contradiction scales down with their confidence
	# (a trustworthy source rarely produces gaps) and up with tenure
	# under no audit (long-unchecked sources are the ones that rot).
	var base_gap: float = 0.05 + 0.004 * float(max(0, 100 - m.confidence))
	base_gap += 0.005 * float(m.months_since_audit)
	if m.double_agent:
		base_gap += 0.4
	var roll: float = _rng.randf()
	if success and roll < base_gap:
		var drop: int = _rng.randi_range(10, 25)
		m.confidence = clampi(m.confidence - drop, 0, 100)
		m.suspected_compromised = m.confidence <= 35 or m.double_agent
		Org.member_updated.emit(m)
		out["verdict"] = &"contradictions"
		out["confidence_delta"] = -drop
		out["now_suspected"] = m.suspected_compromised
		return
	out["verdict"] = &"consistent"


## §18.2 Source audit — higher fidelity, higher risk. Success brings
## back a real verdict on the target; failure on a compromised source
## means they notice they're being watched and start leaking our work
## to whoever owns them.
func _apply_source_audit(target_id: String, success: bool, out: Dictionary) -> void:
	var m: OrgMember = Org.get_member(StringName(target_id))
	if m == null:
		return
	out["member_name"] = m.display_name
	out["member_layer"] = m.layer_name()

	# A member with low confidence or double-agent flag is de facto
	# compromised. "Compromised" is latched onto suspected_compromised.
	var truly_compromised: bool = m.double_agent \
			or (m.confidence <= 40 and m.months_since_audit >= 6)

	if success:
		# We learn the truth.
		if truly_compromised:
			m.suspected_compromised = true
			m.confidence = mini(m.confidence, 25)
			out["verdict"] = &"compromised_confirmed"
		else:
			m.suspected_compromised = false
			m.confidence = clampi(m.confidence + 15, 0, 100)
			m.months_since_audit = 0
			out["verdict"] = &"clean"
		Org.member_updated.emit(m)
	else:
		# Audit fumbled. If they were clean, no real cost beyond the
		# silver. If they were turned, they now know they are watched,
		# and every future cross-reference is poisoned.
		if truly_compromised:
			m.confidence = mini(m.confidence, 20)
			m.heat = clampi(m.heat + 15, 0, 100)
			out["verdict"] = &"audit_burned"
			Org.member_updated.emit(m)
		else:
			out["verdict"] = &"inconclusive"


## §18.2 Direct re-investigation: slow, reliable, expensive. Produces
## an independent confidence read on the *best* source in that kingdom
## (their reporting is the one most worth verifying).
func _apply_reinvestigate(target_id: String, success: bool, out: Dictionary) -> void:
	out["kingdom_id"] = target_id
	var best: OrgMember = null
	var best_skill: int = -1
	for m in Org.all_members():
		if m.burned or m.region_id != target_id:
			continue
		if m.layer == OrgMember.Layer.OPERATIVE or m.layer == OrgMember.Layer.COORDINATOR:
			if m.skill > best_skill:
				best = m
				best_skill = m.skill
	if best == null:
		out["verdict"] = &"no_source"
		return

	out["member_name"] = best.display_name
	out["member_layer"] = best.layer_name()

	if not success:
		out["verdict"] = &"operative_lost"
		return

	# Independent operative returns the ground truth of their recent
	# reporting. If they're compromised, the true picture diverges;
	# we express that as a large confidence adjustment.
	var truly_compromised: bool = best.double_agent or best.confidence <= 40
	if truly_compromised:
		var drop: int = _rng.randi_range(25, 45)
		best.confidence = clampi(best.confidence - drop, 0, 100)
		best.suspected_compromised = true
		Org.member_updated.emit(best)
		out["verdict"] = &"divergence"
		out["confidence_delta"] = -drop
	else:
		best.confidence = clampi(best.confidence + 10, 0, 100)
		Org.member_updated.emit(best)
		out["verdict"] = &"aligned"


## §19.2 Internal cell audit. Surfaces drift corruption signals built
## up through tenure without oversight; a clean pass resets the clock.
func _apply_audit_cell(target_id: String, success: bool, out: Dictionary) -> void:
	var m: OrgMember = Org.get_member(StringName(target_id))
	if m == null:
		return
	out["member_name"] = m.display_name

	# Risk score is a mix of long-tenure-without-audit and source actor
	# traits (greed, low loyalty) when we have them.
	var risk: int = m.months_since_audit * 2
	if m.source_actor_id != &"":
		var a: Actor = Actors.get_actor(m.source_actor_id)
		if a != null:
			risk += maxi(0, a.greed - 50)
			risk += maxi(0, 50 - a.loyalty)
	out["risk_score"] = risk

	if not success:
		out["verdict"] = &"audit_inconclusive"
		return

	m.months_since_audit = 0
	if m.double_agent or m.suspected_compromised:
		out["verdict"] = &"drift_confirmed"
		m.confidence = mini(m.confidence, 30)
	elif risk >= 60:
		m.suspected_compromised = true
		m.confidence = clampi(m.confidence - 15, 0, 100)
		out["verdict"] = &"drift_detected"
	else:
		out["verdict"] = &"clean"
	Org.member_updated.emit(m)


## §18.5 Run a confirmed compromised source as a double agent. Setup
## is a HIGH action; ongoing maintenance happens monthly in OrgRegistry
## (the double_agent flag makes them bleed a small exposure each month).
func _apply_run_double_agent(target_id: String, success: bool, out: Dictionary) -> void:
	var m: OrgMember = Org.get_member(StringName(target_id))
	if m == null:
		return
	out["member_name"] = m.display_name

	if not m.suspected_compromised:
		out["verdict"] = &"not_suspected"
		return

	if success:
		m.double_agent = true
		m.suspected_compromised = true
		# Trust is operational — we still trust them to do what we say.
		# Confidence stays low because what they report is our fiction.
		m.confidence = clampi(m.confidence, 0, 30)
		Org.member_updated.emit(m)
		out["verdict"] = &"double_running"
	else:
		# Setup discovered. Most dangerous failure mode in the game:
		# the source now knows what we tried to do with them.
		m.heat = clampi(m.heat + 40, 0, 100)
		Exposure.bump(6.0, "double_agent_botched")
		Org.member_updated.emit(m)
		out["verdict"] = &"setup_burned"


## §8.12 Level 1–2: investigate the most recent anomaly in the region.
## Failure burns the silver and returns &"no_trail"; success advances
## one op by one level (up to Actor, the hard cap before cross-
## referencing). The rival_registry already tags ops with hidden
## signatures — we reveal them in stages.
func _apply_investigate_anomaly(target_id: String, success: bool, out: Dictionary) -> void:
	var k: Kingdom = WorldData.get_kingdom(target_id)
	out["kingdom_name"] = k.kingdom_name if k != null else target_id

	if not success:
		out["verdict"] = &"no_trail"
		return

	var op: Dictionary = Fingerprints.advance_one_in(target_id, Fingerprints.LEVEL_SIGNAL)
	if op.is_empty():
		out["verdict"] = &"nothing_anomalous"
		return

	var new_level: int = Fingerprints.level_for(String(op.get("op_id", "")))
	out["verdict"]    = &"advanced"
	out["op_id"]      = String(op.get("op_id", ""))
	out["op_headline"] = String(op.get("headline", ""))
	out["new_level"]   = new_level
	# A flavour token describing what was confirmed this pass.
	if new_level >= Fingerprints.LEVEL_ACTOR:
		out["level_label"] = "a local actor is implicated"
	elif new_level >= Fingerprints.LEVEL_MECHANISM:
		out["level_label"] = "a deliberate hand is confirmed"
	else:
		out["level_label"] = "questions remain open"


## §8.12 Level 3. Requires at least three Actor-level ops in the
## region sharing a signature. Returns the matching society_id (not
## yet the name — that is Level 4) so the letter can describe a
## "persistent organisation" without naming it.
func _apply_cross_reference_pattern(target_id: String, success: bool, out: Dictionary) -> void:
	var k: Kingdom = WorldData.get_kingdom(target_id)
	out["kingdom_name"] = k.kingdom_name if k != null else target_id

	if not success:
		out["verdict"] = &"pattern_not_found"
		return

	var sid: StringName = Fingerprints.cross_reference(target_id)
	if sid == &"":
		out["verdict"] = &"insufficient_evidence"
		return
	out["verdict"]        = &"pattern_confirmed"
	out["pattern_signature"] = String(sid)


## §8.12 Level 4 — commit an identification to the library. Raises
## the player's confirmation on the matched society and attributes
## every Pattern-level op of theirs in the region to them.
func _apply_match_fingerprint(target_id: String, success: bool, out: Dictionary) -> void:
	var k: Kingdom = WorldData.get_kingdom(target_id)
	out["kingdom_name"] = k.kingdom_name if k != null else target_id

	if not success:
		out["verdict"] = &"no_match"
		return

	var sid: StringName = Fingerprints.match_fingerprint(target_id)
	if sid == &"":
		out["verdict"] = &"insufficient_evidence"
		return
	var soc: RivalSociety = Rivals.get_society(sid)
	out["verdict"]       = &"fingerprint_matched"
	out["society_id"]    = String(sid)
	out["society_name"]  = soc.display_name if soc != null else String(sid)
	out["confirmation"]  = Fingerprints.confirmation_for(sid)


## §14.6 counter-intel sweep. Detects the highest-heat undetected
## rival operative in the region. If nothing is placed, we return
## &"all_clear" — which is itself useful information (the player
## can stop spending on sweeps here).
func _apply_sweep_for_rivals(target_id: String, success: bool, out: Dictionary) -> void:
	var k: Kingdom = WorldData.get_kingdom(target_id)
	out["kingdom_name"] = k.kingdom_name if k != null else target_id

	if not success:
		out["verdict"] = &"inconclusive"
		return

	if Rivals.undetected_operatives_in(target_id).is_empty():
		if Rivals.operatives_in(target_id).is_empty():
			out["verdict"] = &"all_clear"
		else:
			out["verdict"] = &"already_tracked"
		return

	var op: Dictionary = Rivals.detect_first_available(target_id)
	if op.is_empty():
		out["verdict"] = &"all_clear"
		return
	var sid: StringName = StringName(String(op.get("society_id", "")))
	var soc: RivalSociety = Rivals.get_society(sid)
	# A known society: name them. An unknown one: describe generically.
	var known: bool = Fingerprints.confirmation_for(sid) >= 75
	out["verdict"]           = &"operative_detected"
	out["operative_id"]      = String(op.get("id", ""))
	out["operative_name"]    = String(op.get("name", ""))
	out["operative_cover"]   = String(op.get("cover_role", ""))
	out["operative_society"] = soc.display_name if (soc != null and known) else "an unrecognised organisation"
	# Fingerprint confirmation gets a small bump because a live
	# operative is the richest possible evidence.
	if not known:
		Fingerprints.bump_confirmation(sid, 8)


## §14.6 neutralisation. Burns one detected-and-live rival operative
## and docks their society's foothold.
func _apply_neutralize_rival(target_id: String, success: bool, out: Dictionary) -> void:
	var k: Kingdom = WorldData.get_kingdom(target_id)
	out["kingdom_name"] = k.kingdom_name if k != null else target_id

	# Need at least one detected, live, non-turned operative.
	var eligible: bool = false
	for e in Rivals.detected_operatives_in(target_id):
		if bool(e.get("turned", false)) or bool(e.get("neutralized", false)):
			continue
		eligible = true
		break
	if not eligible:
		out["verdict"] = &"no_target"
		return

	if not success:
		out["verdict"] = &"botched"
		# A failed burn makes the air hot: the target society now
		# knows someone is hunting them here.
		Exposure.bump(6.0, "neutralise_failed")
		return

	var op: Dictionary = Rivals.neutralize_first_eligible(target_id)
	if op.is_empty():
		out["verdict"] = &"no_target"
		return
	var sid: StringName = StringName(String(op.get("society_id", "")))
	var soc: RivalSociety = Rivals.get_society(sid)
	out["verdict"]           = &"neutralised"
	out["operative_name"]    = String(op.get("name", ""))
	out["operative_cover"]   = String(op.get("cover_role", ""))
	out["operative_society"] = soc.display_name if soc != null else "an unrecognised organisation"
	Exposure.bump(3.0, "neutralise_success")


## §14.6 turn. Flips one detected rival operative into a double. Fails
## quietly on misses (the target never knows), loudly on botched
## rolls (the target knows and tells their side we know).
func _apply_turn_rival(target_id: String, success: bool, out: Dictionary) -> void:
	var k: Kingdom = WorldData.get_kingdom(target_id)
	out["kingdom_name"] = k.kingdom_name if k != null else target_id

	var eligible: Dictionary = {}
	for e in Rivals.detected_operatives_in(target_id):
		if bool(e.get("turned", false)) or bool(e.get("neutralized", false)):
			continue
		eligible = e
		break
	if eligible.is_empty():
		out["verdict"] = &"no_target"
		return

	if not success:
		# Botched: they now know the approach was made and have taken
		# that upward. Raise their heat so they may be burned by their
		# own side in the monthly tick.
		eligible["heat"] = mini(100, int(eligible.get("heat", 0)) + 30)
		Exposure.bump(5.0, "turn_failed")
		out["verdict"]           = &"botched"
		out["operative_name"]    = String(eligible.get("name", ""))
		return

	var op: Dictionary = Rivals.turn_first_eligible(target_id)
	if op.is_empty():
		out["verdict"] = &"no_target"
		return
	var sid: StringName = StringName(String(op.get("society_id", "")))
	var soc: RivalSociety = Rivals.get_society(sid)
	out["verdict"]           = &"turned"
	out["operative_name"]    = String(op.get("name", ""))
	out["operative_cover"]   = String(op.get("cover_role", ""))
	out["operative_society"] = soc.display_name if soc != null else "an unrecognised organisation"


## A botched move leaves loose threads. The *player's* exposure meter
## only pays the tail if there was no coverage — otherwise §14.2
## compartmentalisation kicks in and the heat sticks to the cell that
## ran the job, risking an operative (and, cascading, the coordinator).
func _apply_failure_consequences(def: ActionDefinition, success: bool, coord: OrgMember) -> void:
	if success:
		return
	if def.exposure_cost <= 0.0:
		return
	var tail: float = 0.0
	match def.tier:
		ActionDefinition.Tier.DEEP_SHADOW: tail = 1.0
		ActionDefinition.Tier.ACTIVE:      tail = 2.0
		ActionDefinition.Tier.HIGH:        tail = 4.0
	if tail <= 0.0:
		return

	if coord == null or coord.burned:
		# Direct contact; the heat comes back to you.
		Exposure.bump(tail, "failed_" + String(def.id))
		return

	# Routed work: the heat lands on the operative assigned to the job,
	# not the player. If nobody is free, the coordinator eats it.
	var op: OrgMember = Org.operative_for_coordinator(coord.id)
	if op != null:
		Org.bump_heat(op.id, int(tail * 12.0), StringName("failed_" + String(def.id)))
	else:
		Org.bump_heat(coord.id, int(tail * 8.0), StringName("failed_" + String(def.id)))


## For successful actions that produce an observable consequence in the
## world, drop a matching public dispatch. Phase 0 covers rumour, idea
## plant, and host-agitation. Keeps the player's silent hand visible
## through the scroll, never by name.
func _maybe_publish_public_trace(def: ActionDefinition, target_id: String) -> void:
	match def.id:
		&"seed_rumour":
			_publish_rumour_trace(target_id)
		&"plant_idea":
			_publish_idea_trace(target_id)
		&"host_agitate":
			_publish_agitate_trace(target_id)


func _publish_rumour_trace(target_id: String) -> void:
	var a: Actor = Actors.get_actor(StringName(target_id))
	if a == null:
		return
	Whispers.register(&"rumour", a.id)
	var k: Kingdom = WorldData.get_kingdom(a.kingdom_id)
	var kname: String = k.kingdom_name if k != null else a.kingdom_id
	var whispers: Array[String] = [
		"keeps bad company",
		"has debts they cannot name",
		"lies badly about where they spent the last festival",
		"is spoken of unkindly at another court",
		"is not the friend of the crown they claim to be",
	]
	var line: String = whispers[_rng.randi_range(0, whispers.size() - 1)]
	EventBus.public_event.emit({
		"kind":       &"rumour",
		"kingdom_id": a.kingdom_id,
		"actors":     [String(a.id)],
		"headline":   "A rumour fixes on %s" % a.given_name,
		"body":       "In %s the talk turns, quietly but persistently, to [url=actor:%s][b]%s[/b][/url] — who, it is said, %s. No one can name the first mouth it passed through. No one needs to." % [
			kname, String(a.id), a.display_name(), line,
		],
	})


func _publish_idea_trace(target_id: String) -> void:
	var a: Actor = Actors.get_actor(StringName(target_id))
	if a == null:
		return
	Whispers.register(&"idea", a.id)
	var k: Kingdom = WorldData.get_kingdom(a.kingdom_id)
	var kname: String = k.kingdom_name if k != null else a.kingdom_id
	EventBus.public_event.emit({
		"kind":       &"idea_planted",
		"kingdom_id": a.kingdom_id,
		"actors":     [String(a.id)],
		"headline":   "%s speaks in a new key" % a.given_name,
		"body":       "Those close to [url=actor:%s][b]%s[/b][/url] in %s say they have taken up an argument they were not making a month ago. They speak it as their own. Perhaps it is." % [
			String(a.id), a.display_name(), kname,
		],
	})


func _publish_agitate_trace(host_id: String) -> void:
	var host: Actor = Actors.get_actor(StringName(host_id))
	if host == null:
		return
	Whispers.register(&"agitate", host.id)
	var k: Kingdom = WorldData.get_kingdom(host.kingdom_id)
	var kname: String = k.kingdom_name if k != null else host.kingdom_id
	EventBus.public_event.emit({
		"kind":       &"unrest",
		"kingdom_id": host.kingdom_id,
		"actors":     [String(host.id)],
		"headline":   "The streets of %s turn" % kname,
		"body":       "A night of broken stalls and raised voices in %s. The watch made some arrests. Most of those arrested were the wrong ones. The city has not yet cooled." % kname,
	})


func _modified_success_chance(def: ActionDefinition, target_id: String) -> float:
	# Phase 0 modifier set:
	#   bribe     — pulls toward greed (high greed, easier) and away from
	#               loyalty (loyal pockets won't open).
	#   cultivate — compounds: each successful approach nudges the
	#               relationship, and a warm relationship makes further
	#               cultivation meaningfully easier (and hostility makes
	#               it correspondingly harder).
	# Anything else uses the base chance untouched. Seeds the trait-driven
	# resistance model without pretending to be the full §24.3 formula yet.
	var actor: Actor = Actors.get_actor(StringName(target_id))

	if def.id == &"bribe":
		if actor == null:
			return def.base_success_chance
		var greed_bias: float   = (float(actor.greed) - 50.0) / 100.0          # -0.5 .. +0.5
		var loyalty_bias: float = (50.0 - float(actor.loyalty)) / 100.0
		return clampf(def.base_success_chance + greed_bias + loyalty_bias * 0.5, 0.05, 0.95)

	if def.id == &"cultivate":
		if actor == null:
			return def.base_success_chance
		# +/- 30 points of relationship shifts chance by +/- ~0.15.
		var rel_bias: float = float(actor.relationship) / 200.0                # -0.5 .. +0.5
		return clampf(def.base_success_chance + rel_bias, 0.05, 0.97)

	if def.requires_host_target:
		if actor == null:
			return def.base_success_chance
		# The host is the one doing the work: their charisma and the
		# warmth of their loyalty to you set the ceiling. Paranoia of
		# the court (proxied by their own paranoia) drags them down.
		var char_bias: float    = (float(actor.charisma) - 50.0) / 150.0     # ~ +/- 0.33
		var rel_bias_h: float   = (float(actor.relationship) - 60.0) / 200.0 # small extra tilt above the threshold
		var par_bias: float     = -(float(actor.paranoia) - 50.0) / 300.0
		return clampf(def.base_success_chance + char_bias + rel_bias_h + par_bias, 0.05, 0.95)

	return def.base_success_chance


# --- Relationship effects ----------------------------------------------------

func _apply_relationship_effects(def: ActionDefinition, target_id: String, success: bool) -> int:
	if def.target_kind != ActionDefinition.TargetKind.ACTOR or target_id.is_empty():
		return 0
	var id: StringName = StringName(target_id)
	var delta: int = 0
	match def.id:
		&"cultivate":
			delta = 12 if success else 2            # even a dud visit builds a little rapport
		&"bribe":
			delta = 4 if success else -6            # a refused bribe stings
		&"plant_idea":
			delta = 2 if success else 0
		&"seed_rumour":
			delta = -5 if success else -1           # rumours target THEM, so damage their view of you if they trace it
		&"host_sway_court":
			# Using a host deepens the bond whether it worked or not;
			# failure costs them a little because they stuck their neck out.
			delta = 3 if success else -4
		&"host_agitate":
			delta = 2 if success else -6
		_:
			return 0
	if delta == 0:
		return 0
	Actors.adjust_relationship(id, delta)
	return delta


# --- Report authoring --------------------------------------------------------

func _build_report(def: ActionDefinition, target_id: String, success: bool, extras: Dictionary = {}) -> Letter:
	var target_name: String = _lookup_target_name(def.target_kind, target_id)
	# GameClock stores years as negative (BCE arithmetic); GameDate stores
	# them as positive (display). Flip here.
	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var letter_id: StringName = StringName("report_%d" % Time.get_ticks_msec())

	# Subject lines use the plain name (no bbcode — the inbox header label
	# is not a RichTextLabel).
	var subject: String = "Report on %s" % target_name
	if def.id == &"observe":
		subject = "Watcher's report on %s" % target_name
	elif def.id == &"bribe":
		subject = "Paymaster's note, re: %s" % target_name
	elif BRIBE_IDS.has(def.id):
		var oc: int = int(extras.get("bribe_outcome", -1))
		match oc:
			BribeOutcome.CLEAN_SUCCESS:    subject = "It is done, re: %s" % target_name
			BribeOutcome.MESSY_SUCCESS:    subject = "It is done — but spoken of, re: %s" % target_name
			BribeOutcome.SILENT_FAILURE:   subject = "A polite refusal, re: %s" % target_name
			BribeOutcome.LOUD_FAILURE:     subject = "Our offer has been talked about, re: %s" % target_name
			BribeOutcome.COUNTER_LEVERAGED: subject = "Our approach has been sold, re: %s" % target_name
			_:                             subject = "Paymaster's note, re: %s" % target_name
	elif def.id == &"seed_rumour":
		subject = "Whispers in the market, re: %s" % target_name
	elif def.id == &"plant_idea":
		subject = "Word from the broker, re: %s" % target_name
	elif def.id == &"cultivate":
		subject = "A season of small kindnesses, re: %s" % target_name
	elif def.id == &"host_sway_court":
		subject = "From your host at court"
	elif def.id == &"host_agitate":
		subject = "The streets are hot"
	elif def.id == &"quiet_plot":
		subject = "On the matter in %s" % target_name
	elif def.id == &"fan_border":
		subject = "From the frontier of %s" % target_name
	elif def.id == &"promote_coordinator":
		subject = (
			"A coordinator answers to you"
			if success else
			"A conversation that never happened"
		)
	elif def.id == &"promote_lieutenant":
		subject = (
			"You have a second-in-command"
			if success else
			"The elevation is deferred"
		)
	elif def.id == &"intel_cross_reference":
		var cv: StringName = StringName(String(extras.get("verdict", "")))
		match cv:
			&"contradictions": subject = "Contradictions in %s's reporting" % target_name
			&"no_coverage":    subject = "No corroborating sources for %s" % target_name
			&"consistent":     subject = "%s's reports hold up" % target_name
			_:                 subject = "Cross-reference on %s" % target_name
	elif def.id == &"intel_source_audit":
		var av: StringName = StringName(String(extras.get("verdict", "")))
		match av:
			&"compromised_confirmed": subject = "%s is compromised" % target_name
			&"clean":                 subject = "%s is clean" % target_name
			&"audit_burned":          subject = "The audit on %s was noticed" % target_name
			&"inconclusive":          subject = "Audit on %s was inconclusive" % target_name
			_:                        subject = "Audit on %s" % target_name
	elif def.id == &"intel_reinvestigate":
		var rv: StringName = StringName(String(extras.get("verdict", "")))
		match rv:
			&"divergence":      subject = "Independent ground differs from our source"
			&"aligned":         subject = "Independent investigation aligns with our source"
			&"operative_lost":  subject = "The second operative could not deliver"
			&"no_source":       subject = "No one to verify against"
			_:                  subject = "Re-investigation report"
	elif def.id == &"audit_cell":
		var uv: StringName = StringName(String(extras.get("verdict", "")))
		match uv:
			&"drift_confirmed":     subject = "%s's cell has drifted" % target_name
			&"drift_detected":      subject = "Concerns about %s's cell" % target_name
			&"clean":               subject = "%s's cell is in order" % target_name
			&"audit_inconclusive":  subject = "Audit on %s's cell was inconclusive" % target_name
			_:                      subject = "Internal audit on %s" % target_name
	elif def.id == &"run_double_agent":
		var dv: StringName = StringName(String(extras.get("verdict", "")))
		match dv:
			&"double_running": subject = "%s is now feeding them our words" % target_name
			&"setup_burned":   subject = "The double play is burned"
			&"not_suspected":  subject = "%s is not yet suspected" % target_name
			_:                 subject = "On %s, and the other room" % target_name
	elif def.id == &"investigate_anomaly":
		var iv: StringName = StringName(String(extras.get("verdict", "")))
		match iv:
			&"advanced":           subject = "A hand shows in %s" % target_name
			&"nothing_anomalous":  subject = "Nothing unnatural in %s" % target_name
			&"no_trail":           subject = "The trail in %s went cold" % target_name
			_:                     subject = "Investigation in %s" % target_name
	elif def.id == &"cross_reference_pattern":
		var pv: StringName = StringName(String(extras.get("verdict", "")))
		match pv:
			&"pattern_confirmed":      subject = "A persistent hand in %s" % target_name
			&"pattern_not_found":      subject = "No single pattern in %s" % target_name
			&"insufficient_evidence":  subject = "Too little to cross-reference in %s" % target_name
			_:                         subject = "Archive sweep on %s" % target_name
	elif def.id == &"match_fingerprint":
		var fv: StringName = StringName(String(extras.get("verdict", "")))
		match fv:
			&"fingerprint_matched":    subject = "%s named in %s" % [String(extras.get("society_name", "A rival")), target_name]
			&"no_match":               subject = "No match in the library for %s" % target_name
			&"insufficient_evidence":  subject = "Not ready to match fingerprints on %s" % target_name
			_:                         subject = "Library cross-check on %s" % target_name
	elif def.id == &"sweep_for_rivals":
		var sv: StringName = StringName(String(extras.get("verdict", "")))
		match sv:
			&"operative_detected":  subject = "A face that does not belong in %s" % target_name
			&"all_clear":           subject = "%s is clean of foreign hands" % target_name
			&"already_tracked":     subject = "No new strangers in %s" % target_name
			&"inconclusive":        subject = "Sweep on %s returned nothing" % target_name
			_:                      subject = "Counter-intelligence sweep in %s" % target_name
	elif def.id == &"neutralize_rival_operative":
		var nv: StringName = StringName(String(extras.get("verdict", "")))
		match nv:
			&"neutralised":  subject = "%s is off the board in %s" % [String(extras.get("operative_name", "The operative")), target_name]
			&"botched":      subject = "A burn in %s went wrong" % target_name
			&"no_target":    subject = "No operative to burn in %s" % target_name
			_:               subject = "On a hostile operative in %s" % target_name
	elif def.id == &"turn_rival_operative":
		var tv: StringName = StringName(String(extras.get("verdict", "")))
		match tv:
			&"turned":     subject = "%s now serves us in %s" % [String(extras.get("operative_name", "A rival")), target_name]
			&"botched":    subject = "The turn failed in %s" % target_name
			&"no_target":  subject = "No operative to turn in %s" % target_name
			_:             subject = "On turning an operative in %s" % target_name

	# Body uses the linked name so the reader can click through to the
	# target's dossier from the letter.
	var linked_name: String = _linked_target(def.target_kind, target_id, target_name)
	var body: String = _body_for(def, linked_name, success, extras)

	return Letter.create(letter_id, def.report_sender, date, subject, body, &"action")


## Wrap an Actor target name in a BBCode url so the letter view can
## open the dossier on click. Non-Actor targets return plain text.
## The colour is a dark wine red that reads as "interactive" on parchment.
func _linked_target(kind: ActionDefinition.TargetKind, id: String, display: String) -> String:
	if kind == ActionDefinition.TargetKind.ACTOR and not id.is_empty():
		return "[url=actor:%s][color=#702020][b]%s[/b][/color][/url]" % [id, display]
	return display


func _body_for(def: ActionDefinition, target: String, success: bool, extras: Dictionary = {}) -> String:
	var outcome_lines: String = (
		"The matter proceeded as you willed."
		if success else
		"The matter did not settle as you hoped."
	)

	match def.id:
		&"observe":
			if success:
				return "%s continues under my watch. Their comings and goings are noted, their company recorded, and one detail worth your attention has reached me — a discreet account will follow by the next post.\n\nI remain, as always, unseen." % target
			return "I could not hold the watch on %s. Strangers moved in the same quarter, and to press closer would have courted notice. I withdrew. It is better to be patient than to be remembered." % target

		&"cultivate":
			if success:
				return "The seasons have not been wasted. %s now receives me without question and lets my counsel sit longer than it used to. A small matter of theirs was, in the end, arranged by my hand — though they believe it to be their own.\n\nThey are not yet yours. But they are no longer outside your reach." % target
			return "My approach to %s has gone nowhere. They are polite, as their station demands, but the warmth never takes. Another shape, another envoy, will be needed." % target

		&"plant_idea":
			if success:
				return "The seed has taken. %s voiced the thought themselves before the last moon turned, and to at least two others who matter.\n\nWhether it grows into action is no longer in my hands." % target
			return "I could not place the thought. Our chosen mouth spoke it poorly, and %s received it as an idle pleasantry and moved on. The moment has passed." % target

		&"seed_rumour":
			if success:
				return "The whisper reached the quays by the second day, the markets by the fifth. %s is now discussed in terms that were not theirs a month ago.\n\nNo thread leads back to us." % target
			return "The rumour did not take. It drew a scoff from a well-placed mouth and then dissolved. We will need a sharper vessel, and a different ear." % target

		&"bribe":
			if success:
				return "It is done. %s accepted the silver, and the small thing you asked of them has been quietly arranged.\n\nMy account, and their receipt, are in the usual place." % target
			return "The offer was placed with care and refused — without noise, to our good fortune. The silver is returned. %s is not to be approached this way again, at least not through this hand." % target

		&"bribe_direct", &"bribe_retainer", &"bribe_career", &"bribe_info", &"bribe_gift":
			return _bribe_body(def.id, target, extras)

		&"intel_cross_reference":
			return _cross_reference_body(target, extras)
		&"intel_source_audit":
			return _source_audit_body(target, extras)
		&"intel_reinvestigate":
			return _reinvestigate_body(target, extras)
		&"audit_cell":
			return _audit_cell_body(target, extras)
		&"run_double_agent":
			return _double_agent_body(target, extras)

		&"investigate_anomaly":
			return _investigate_anomaly_body(extras)
		&"cross_reference_pattern":
			return _cross_reference_pattern_body(extras)
		&"match_fingerprint":
			return _match_fingerprint_body(extras)
		&"sweep_for_rivals":
			return _sweep_for_rivals_body(extras)
		&"neutralize_rival_operative":
			return _neutralize_rival_body(extras)
		&"turn_rival_operative":
			return _turn_rival_body(extras)

		&"host_sway_court":
			if success:
				return "It is arranged. I made your case as though it were my own, and the matter was decided as you wished it. No name of yours has been spoken — only mine, which is as it should be.\n\nI remain in service,\n%s" % target
			return "I tried, and failed. The counsel was thick with other mouths and mine was only one. No suspicion fell on you. None, I believe, fell on me. But the decision is not ours this time.\n\n— %s" % target

		&"host_agitate":
			if success:
				return "The markets were crying by the third night. A trader beaten, a loaf overturned, and then the right word passed through the right mouth. By the week's end the city was in the street. What the crown does next is their problem, not ours.\n\nYours in the work,\n%s" % target
			return "I could not get the spark to take. The city is tired but not yet angry. I lost two contacts to the watch. I am well; do not send the usual signal until I send mine first.\n\n— %s" % target

		&"fan_border":
			var n_name: String = String(extras.get("neighbour_name", "a neighbouring crown"))
			var before: int = int(extras.get("before_state", Relations.RelationState.NEUTRAL))
			var after: int  = int(extras.get("after_state", before))
			if not success:
				return "I could not light anything along the border with %s. The traders who should have carried the grievance north carried only grain; the pamphlets I paid for were burned, unread, in the back of a church. The money is gone. The frontier is as quiet as it was." % n_name
			if after == int(Relations.RelationState.AT_WAR):
				return "It has caught. Between %s and %s a skirmish has become a campaign; the envoys have been sent home, the levies are on the move. No one yet names the hand that pushed — they name each other, which is exactly what was wanted." % [target, n_name]
			if before == int(Relations.RelationState.NEUTRAL) and after == int(Relations.RelationState.HOSTILE):
				return "The border has cooled, then curdled. Officials on both sides of the line between %s and %s now speak about each other the way men speak about thieves. A peace is still on the books; a war is now possible in a way it wasn't a season ago." % [target, n_name]
			if after == int(Relations.RelationState.HOSTILE):
				return "Work begun. The frontier between %s and %s is worse for our attention — a step closer to what you're after, though not yet where we want it. Another push may finish it." % [target, n_name]
			return "Something shifted on the border with %s. Not yet the shape you wanted, but a colder wind than last month. Patience." % n_name
		&"promote_coordinator":
			if success:
				return (
					"It is done. %s met you at the old house in the hill and did not leave until the small hours. They understand what is being asked. They accepted, in their own words, without flinching.\n\nFrom this month on, the city's work runs through them. You will not meet hands beneath their rank again unless the world forces you to."
				) % target
			return (
				"I could not finish the conversation with %s. What I had to say was too large for the room — they asked questions I could not answer without risking the whole shape, and so I let them believe it had been the heat, the wine, my own tiredness. They leave the meeting thinking they were nearly offered a business, nothing more.\n\nYou have not lost them. But you have not gained them either. Try again when the season is calmer."
			) % target
		&"promote_lieutenant":
			if success:
				return (
					"I have told %s what they are to me, by degrees, across the last two winters. They now know what kind of thing the organisation is, if not yet what the organisation serves. From this day, their coordinators answer to them; they answer to me; I answer to no one they can name.\n\nThe chain above them has a hand at its top. They do not know whose."
				) % target
			return (
				"The elevation failed. Not by their disloyalty — by mine. I moved too fast; they sensed a shape behind the shape and asked one question too many. I took the conversation back, gave them a different explanation, and let the evening end in coin.\n\nThey are still your coordinator. They are still ours. But it is not yet time to lift them further."
			) % target
		&"quiet_plot":
			var p_name: String = String(extras.get("plotter_name", ""))
			var p_id:   String = String(extras.get("plotter_id", ""))
			var linked_plotter: String = p_name
			if p_id != "" and p_name != "":
				linked_plotter = "[url=actor:%s][color=#702020][b]%s[/b][/color][/url]" % [p_id, p_name]
			if p_name.is_empty():
				if success:
					return "I sent word through the quiet mouths in %s. If a knife was being sharpened for the throne there, it has gone back into its sheath — or else it was never as near the hand as we feared. The court is calm for now." % target
				return "I could find no plot in %s to quiet. Either none was ripe, or it was hidden deeper than our coin reaches. The silver is spent either way; such work rarely leaves receipts." % target
			if success:
				return "The name was %s.\n\nI put silver in the right palms, a promise or two in the right ears, and the ambition was talked back to its cage. They will not move on the crown this season, perhaps not this year. Watch them — a plot laid down is not the same as a plot abandoned." % linked_plotter
			return "I believe the hand at the hilt was %s. I could not buy them, flatter them, or frighten them into standing down. The blade is still being sharpened. Another instrument will be needed — and soon." % linked_plotter

		_:
			return "%s %s" % [outcome_lines, target]


## Per-outcome body text for the five bribe variants (§17). Each variant
## has its own voice; each outcome its own tone. Counter-leveraged is
## the loudest because it names that somebody else now holds leverage.
func _bribe_body(action_id: StringName, target: String, extras: Dictionary) -> String:
	var outcome: int = int(extras.get("bribe_outcome", BribeOutcome.SILENT_FAILURE))

	match outcome:
		BribeOutcome.CLEAN_SUCCESS:
			if action_id == &"bribe_retainer":
				var monthly: int = int(extras.get("retainer_monthly", 0))
				return ("It is settled. %s has taken the first payment and will be kept on a retainer of %d silver the month. They understand what is expected; they do not expect to be asked twice.\n\nThe ledger will show the outflow under a trading name; watch it, because a retainer is a leash with two ends."
					) % [target, monthly]
			if action_id == &"bribe_career":
				return ("A door has been opened. %s walks through it believing it was their own ambition that turned the key, and perhaps partly it was. They act for you now, without knowing the hand above them.\n\nNo silver has changed hands. The trail is thin."
					) % target
			if action_id == &"bribe_info":
				return ("The trade is done. %s now holds a knife we handed them, and we hold one they handed us in return. Neither will be used lightly. For the present, they do as we asked — and they will keep doing so while our blades stay sheathed."
					) % target
			if action_id == &"bribe_gift":
				return ("The kindness has landed where it was meant to. %s has not called it a payment; they have called it a friendship. The asked-for thing followed, as though it were their idea. There is no receipt anyone could point to."
					) % target
			return ("It is done. %s accepted the silver, and the small matter you asked of them has been quietly arranged.\n\nMy account and their receipt are in the usual place."
				) % target

		BribeOutcome.MESSY_SUCCESS:
			if action_id == &"bribe_career":
				return ("You have what you wanted — %s acted for you — but they have told the story of their new patronage to at least one person too many. It will not be long before a version of the tale reaches a rival court. The work holds. The secrecy does not."
					) % target
			if action_id == &"bribe_retainer":
				return ("The arrangement is in place, but %s is already spending beyond what a clerk of their rank should spend, and others have noticed. Expect the first rumours to arrive within the season."
					) % target
			if action_id == &"bribe_gift":
				return ("%s has accepted the attentions and done the thing you wanted. They also mentioned the gifts, unprompted, at the wrong table. The kindness will be inventoried by someone eventually."
					) % target
			return ("The matter is arranged. %s did as you asked — and then drank too much and talked. Nothing names us directly, but a shape is now in the street where there was none before."
				) % target

		BribeOutcome.SILENT_FAILURE:
			if action_id == &"bribe_career":
				return ("%s listened, thanked us, and then stepped away from the door we had opened. They would not say why. The silver we did not spend is intact. No story is forming."
					) % target
			if action_id == &"bribe_info":
				return ("%s declined the trade. They gave no reason, asked no questions, and have not spoken of it to anyone we know of. A quiet refusal is the best kind. We must look elsewhere."
					) % target
			if action_id == &"bribe_gift":
				return ("The gifts were received. The request, when it was made, was not. %s has not complained to anyone, but they have also not moved. This instrument has, at best, been blunted."
					) % target
			if action_id == &"bribe_retainer":
				return ("%s turned down the retainer after the first month, quietly, and returned the coin. No noise. Try another hand for this work."
					) % target
			return ("The offer was placed with care and refused — without noise, to our good fortune. The silver is returned. %s is not to be approached this way again through this hand."
				) % target

		BribeOutcome.LOUD_FAILURE:
			if action_id == &"bribe_gift":
				return ("The gifts came back with a note. %s has read the note aloud to company we did not choose, and the city is now amusing itself at our expense. No name of yours was spoken. The shape of you, however, is a little clearer than it was yesterday."
					) % target
			if action_id == &"bribe_info":
				return ("%s refused the trade and then told the temple about it. The priest, being what priests are, told the square. The city now knows that someone offered %s a secret in exchange for a favour. Us, they do not know. Yet."
					) % target
			return ("%s took offence. Loudly. The offer is being retold in the wine-shops with embellishment — the sum grows every telling. No thread leads directly to you, but the city now knows that someone is buying, and the watch will be looking."
				) % target

		BribeOutcome.COUNTER_LEVERAGED:
			return ("%s did not merely refuse — they walked our offer, word for word, into a room we do not sit in. Another interested party now knows that a hand in this city reaches their way. We must assume the approach is compromised; watch for its echo."
				) % target

	return "%s — no outcome recorded." % target


func _cross_reference_body(target: String, extras: Dictionary) -> String:
	var verdict: StringName = StringName(String(extras.get("verdict", "")))
	var drop: int = int(extras.get("confidence_delta", 0))
	var now_suspected: bool = bool(extras.get("now_suspected", false))
	var corroborators: int = int(extras.get("corroborators", 0))

	match verdict:
		&"contradictions":
			var tail: String = "Their confidence rating falls by %d. " % abs(drop)
			if now_suspected:
				tail += "I have flagged them as suspected — the next move is yours."
			else:
				tail += "Not yet enough to call them turned, but enough to stop acting on their word alone."
			return ("I held %s's reports against every other thread I have on the same ground. "
				+ "There are gaps — places where what they say happened and what others say happened "
				+ "do not line up. They are small, and any one of them could be forgiven. Together, "
				+ "they are not. %s") % [target, tail]
		&"no_coverage":
			return ("I have nothing to hold %s's reports against. No other operative covers the "
				+ "same city, no public news speaks to what they speak of. We must either put a "
				+ "second pair of eyes in place or accept that this source verifies only itself."
				) % target
		&"consistent":
			return ("%s's reporting holds. I compared it against %d other thread(s) of mine and found "
				+ "no contradictions worth pulling at. That is not proof of honesty — only of coherence. "
				+ "But it is what we have."
				) % [target, corroborators]
	return "Cross-reference on %s complete. No clear verdict." % target


func _source_audit_body(target: String, extras: Dictionary) -> String:
	var verdict: StringName = StringName(String(extras.get("verdict", "")))
	match verdict:
		&"compromised_confirmed":
			return ("There is no more doubt. %s is turned. Their lifestyle has exceeded their means "
				+ "for some months, their route home at night passes a door it has no reason to, and "
				+ "they have met twice with a man I can place in another city's records. You now decide "
				+ "what use they still are — a quiet cut, or a louder play."
				) % target
		&"clean":
			return ("%s has been walked through — contacts, purse, routines — and they come out whole. "
				+ "No meetings we did not know of, no silver we did not account for. I have reset the "
				+ "audit clock on them. Put them to harder work with a steadier hand."
				) % target
		&"audit_burned":
			return ("The audit on %s was felt. They know they are watched now — a follower they should "
				+ "not have been able to spot, a question asked of the wrong friend. Worse: if they are "
				+ "the thing we feared, our movements across the last weeks are now carried to whoever "
				+ "owns them. Treat this as a loud failure and act before they do."
				) % target
		&"inconclusive":
			return ("The audit on %s returns nothing I would stake a decision on. Nothing damning, but "
				+ "nothing clean either — the pattern of their week is too ordinary to be persuasive. "
				+ "Try again in a season; or invest in a heavier method."
				) % target
	return "The audit on %s returned no verdict." % target


func _reinvestigate_body(target: String, extras: Dictionary) -> String:
	var verdict: StringName = StringName(String(extras.get("verdict", "")))
	var mname: String = String(extras.get("member_name", "our source"))
	match verdict:
		&"divergence":
			var drop: int = int(extras.get("confidence_delta", 0))
			return ("A second operative, independent of our standing network, has walked the same "
				+ "ground %s walks and come back with a different picture. The gap is wide enough "
				+ "that we cannot explain it by variance alone. %s's confidence rating is reduced "
				+ "by %d; I have flagged them as suspected."
				) % [mname, mname, abs(drop)]
		&"aligned":
			return ("The independent walk confirms %s. What they have been telling us is, as far as "
				+ "a second pair of eyes can judge, what is actually happening. Their confidence rating "
				+ "rises a little."
				) % mname
		&"operative_lost":
			return ("I lost the second operative before the work was complete. They are alive — the "
				+ "letters arrive — but the investigation did not. The silver is gone. Another hand will "
				+ "be needed.")
		&"no_source":
			return ("I could not find a source in %s worth re-investigating. Either we have no one there, "
				+ "or what we have is an abstract operative whose reports are too shallow to doubt or "
				+ "confirm. The silver is returned."
				) % target
	return "Re-investigation produced no verdict."


func _audit_cell_body(target: String, extras: Dictionary) -> String:
	var verdict: StringName = StringName(String(extras.get("verdict", "")))
	match verdict:
		&"drift_confirmed":
			return ("The audit on %s's cell returns what we feared. The ledgers and the operational "
				+ "record do not align; silver intended for one hand has been touching a second before "
				+ "it arrived. I have flagged the cell for a decision — reassign, leverage, or cut."
				) % target
		&"drift_detected":
			return ("%s's cell has grown too comfortable. Nothing outright wrong, yet — but the patterns "
				+ "of their last six months show the small liberties that tend to grow into the large ones. "
				+ "I have resurfaced them as suspected; if you mean to keep them, we should audit again "
				+ "before the year turns."
				) % target
		&"clean":
			return ("%s's cell is in order. Their ledgers match the financial record to within what "
				+ "variance the work admits; their operatives' reports track the public ground. Audit "
				+ "clock is reset — the next review can wait at least a year."
				) % target
		&"audit_inconclusive":
			return ("The audit on %s's cell could not settle. Too much of their work runs through "
				+ "intermediaries we have no hand on; I could not verify what mattered. Consider a "
				+ "heavier method if you have reason to doubt them."
				) % target
	return "The audit on %s's cell returned no verdict." % target


func _double_agent_body(target: String, extras: Dictionary) -> String:
	var verdict: StringName = StringName(String(extras.get("verdict", "")))
	match verdict:
		&"double_running":
			return ("The arrangement is made. %s now carries upward the words we give them and no others. "
				+ "Their eyes remain on us — and ours, for the first time, pass through them and into the "
				+ "room that thought it owned them. This costs. Every month the handler must renew the "
				+ "fiction, and every month the risk of their rival testing them grows. Worth it, if the "
				+ "right thing comes back."
				) % target
		&"setup_burned":
			return ("The approach to %s failed at the worst possible stage. They sensed what was being "
				+ "asked before it was asked, and now they know that we knew they were turned. They have "
				+ "taken that knowledge to the room that owns them. Every source that has spoken to %s "
				+ "in the past year must be assumed compromised. Act now; there is no grace period."
				) % [target, target]
		&"not_suspected":
			return ("%s has not been flagged as suspected. A double-agent play requires a confirmed "
				+ "compromise, or you are merely handing a clean operative to an enemy. Audit first."
				) % target
	return "On the matter of %s, no clear result." % target


## §8.12 Level 1–2 report. We deliberately do not name the society
## here — the letter describes what was learned at the level the
## player reached, and nothing beyond it.
func _investigate_anomaly_body(extras: Dictionary) -> String:
	var region: String = String(extras.get("kingdom_name", "that region"))
	var verdict: StringName = StringName(String(extras.get("verdict", "")))
	match verdict:
		&"no_trail":
			return ("Three weeks in %s and every door my hand was on opened onto an empty room. "
				+ "Either nothing is moving there, or the thing that is moving is well enough "
				+ "dressed that it is wearing its own weather. I would try again in a quieter season."
				) % region
		&"nothing_anomalous":
			return ("The region is quiet enough that I could not, in good conscience, name any event in "
				+ "%s as unnatural. The harvest arrived on time. The courts sat without murder. "
				+ "If there is a hand at work here, it is a careful one, and we have nothing to read yet."
				) % region
		&"advanced":
			var head: String = String(extras.get("op_headline", "the last anomaly"))
			var level: int   = int(extras.get("new_level", Fingerprints.LEVEL_MECHANISM))
			var label: String = String(extras.get("level_label", ""))
			if level >= Fingerprints.LEVEL_ACTOR:
				return ("On the matter headlined '[i]%s[/i]' in %s:\n\n"
					+ "We now have a name — or at least a household — at the bottom of it. "
					+ "A local actor acted at the exact moment the event required. Their money trail "
					+ "does not quite close on itself; it disappears into an institution our ledgers "
					+ "do not recognise. %s.\n\n"
					+ "This is enough to compare against other incidents in %s if we have them."
					) % [head, region, label, region]
			return ("On the matter headlined '[i]%s[/i]' in %s:\n\n"
				+ "What looked like a run of bad weather — or bad luck — was not. The mechanism was "
				+ "deliberate. %s. I could not yet say by whose hand; the trail narrows but does not end.\n\n"
				+ "Another investigation of the same event, from a different angle, may give us the actor."
				) % [head, region, label]
	return "An investigation closed in %s without a clear finding." % region


## §8.12 Level 3 report.
func _cross_reference_pattern_body(extras: Dictionary) -> String:
	var region: String = String(extras.get("kingdom_name", "the region"))
	var verdict: StringName = StringName(String(extras.get("verdict", "")))
	match verdict:
		&"pattern_not_found":
			return ("The archivists spent a month at the desk and a week on the road. The incidents in %s "
				+ "do not, when laid next to each other, sing the same tune. Either we do not have "
				+ "enough of them yet, or there is no single hand here — only weather."
				) % region
		&"insufficient_evidence":
			return ("To compare patterns we first need individual incidents investigated to the point where "
				+ "a local actor has been named. We do not yet have three such incidents in %s. "
				+ "The archivists returned with nothing the desk did not already know."
				) % region
		&"pattern_confirmed":
			return ("Three incidents in %s, unrelated on their face, settle onto the same financial spine. "
				+ "The institution behind them is not one our books recognise. We cannot yet name it, "
				+ "but we can see it — a persistent organisation, working quietly, across years, to a "
				+ "consistent shape.\n\nIf we have encountered their signature elsewhere, the library "
				+ "will know. If not, we will open a new file."
				) % region
	return "The archive produced no useful result on %s." % region


## §8.12 Level 4 report.
func _match_fingerprint_body(extras: Dictionary) -> String:
	var region: String = String(extras.get("kingdom_name", "the region"))
	var verdict: StringName = StringName(String(extras.get("verdict", "")))
	match verdict:
		&"no_match":
			return ("The comparison failed. Either the signature we have built in %s is partial, or the "
				+ "fingerprint library has no record of the hand at work. The archivists recommend "
				+ "more cross-referencing before this move is attempted again."
				) % region
		&"insufficient_evidence":
			return ("To match a fingerprint we need at least one pattern already confirmed in %s. "
				+ "No such pattern is on file. Cross-reference first; then come back to the library."
				) % region
		&"fingerprint_matched":
			var soc: String = String(extras.get("society_name", "a named society"))
			var conf: int   = int(extras.get("confirmation", 0))
			return ("The hand that has been moving in %s is [b]%s[/b].\n\n"
				+ "The library's records of their operations elsewhere line up, near enough, with "
				+ "what we have collected here. Methods, rhythm, the shape of the cut-outs — it is "
				+ "them. Confirmation in the library now stands at roughly %d per cent.\n\n"
				+ "From this point forward, their fingerprint will be read the first time it shows up, "
				+ "not the fifth."
				) % [region, soc, conf]
	return "The match attempt on %s produced no result." % region


## §14.6 counter-intel sweep body.
func _sweep_for_rivals_body(extras: Dictionary) -> String:
	var region: String = String(extras.get("kingdom_name", "the region"))
	var verdict: StringName = StringName(String(extras.get("verdict", "")))
	match verdict:
		&"all_clear":
			return ("Six weeks of patient watching in %s. No face sat twice at the wrong table. "
				+ "No payment moved along a ledger that should not have existed. If there is a "
				+ "foreign hand working here, it is doing so more carefully than we can read. "
				+ "I would rather you save the silver for a region where we have warmer threads."
				) % region
		&"already_tracked":
			return ("The strangers in %s we already know about are the strangers still in %s. "
				+ "Nothing new on the sheets. They are being quieter than last month — which may "
				+ "mean they know we are looking, or it may mean they have nothing on this season."
				) % [region, region]
		&"inconclusive":
			return ("The sweep in %s closed with nothing firm. Two leads turned into locals; a "
				+ "third turned into a corpse before we could ask it anything useful. We are no "
				+ "worse off than we were a month ago. We are also no better."
				) % region
		&"operative_detected":
			var nm: String    = String(extras.get("operative_name", "A stranger"))
			var role: String  = String(extras.get("operative_cover", "an inconspicuous office"))
			var soc: String   = String(extras.get("operative_society", "an unrecognised organisation"))
			return ("A face in %s that should not be here.\n\n"
				+ "[b]%s[/b], a %s, has been in the wrong rooms twice this season. Their payments "
				+ "do not come from the house they appear to work for. Their correspondence leaves "
				+ "the region through a post we do not control.\n\n"
				+ "They are working, on the best reading we have, for [i]%s[/i].\n\n"
				+ "They do not yet know we see them. What you do with this is yours to decide."
				) % [region, nm, role, soc]
	return "The counter-intelligence sweep in %s produced no report." % region


func _neutralize_rival_body(extras: Dictionary) -> String:
	var region: String = String(extras.get("kingdom_name", "the region"))
	var verdict: StringName = StringName(String(extras.get("verdict", "")))
	match verdict:
		&"no_target":
			return ("There is no detected rival operative currently live in %s for us to neutralise. "
				+ "Sweep first; identify a name; and come back to this letter."
				) % region
		&"botched":
			return ("The burn in %s went wrong in every meaningful way. Our chosen vessel drank the "
				+ "wrong cup, our chosen magistrate refused the brief, and the whole matter became a "
				+ "rumour before it became an arrest. The target walks free, they know we tried, and "
				+ "their side has a story now that explains why they should be left to run. Expect "
				+ "them to be harder to catch the next time."
				)
		&"neutralised":
			var nm: String    = String(extras.get("operative_name", "The operative"))
			var role: String  = String(extras.get("operative_cover", "their cover role"))
			var soc: String   = String(extras.get("operative_society", "the organisation behind them"))
			return ("It is done. [b]%s[/b] will no longer work against us in %s.\n\n"
				+ "The crown was given exactly enough to do the arresting; the crowd was given "
				+ "exactly enough to do the hating. Their handlers inside %s watched the whole "
				+ "spectacle and asked no questions the courts could answer. The cover as %s dies "
				+ "with them.\n\n"
				+ "The foothold of %s in this region is quietly smaller than it was last month."
				) % [nm, region, soc, role, soc]
	return "On the matter of a rival operative in %s, no clear report." % region


func _turn_rival_body(extras: Dictionary) -> String:
	var region: String = String(extras.get("kingdom_name", "the region"))
	var verdict: StringName = StringName(String(extras.get("verdict", "")))
	match verdict:
		&"no_target":
			return ("There is no detected, live, un-turned rival operative currently in %s. "
				+ "Nothing for us to turn. Sweep first."
				) % region
		&"botched":
			var nm: String = String(extras.get("operative_name", "The operative"))
			return ("We reached for [b]%s[/b] and closed around nothing. They saw the approach for what it was, "
				+ "stood up from the table, and left without finishing the cup. They have taken that meeting "
				+ "upward. Whether their side burns them for being approached, or feeds them back to us as a "
				+ "fake turn, we will know in weeks, not in years. Expect noise either way."
				) % nm
		&"turned":
			var nm: String    = String(extras.get("operative_name", "The operative"))
			var role: String  = String(extras.get("operative_cover", "their cover role"))
			var soc: String   = String(extras.get("operative_society", "their organisation"))
			return ("[b]%s[/b] now carries upward, to %s, exactly the words we choose to put in their mouth.\n\n"
				+ "They remain on post as %s. Their wage continues. Their handlers continue to write to them. "
				+ "The only thing that has quietly changed is the shape of the letters they send back.\n\n"
				+ "We will have a slow, steady drip on %s from this region for as long as they hold. Count on "
				+ "a year; hope for three. Every month they live is a month their side watches the wrong door."
				) % [nm, soc, role, soc]
	return "On turning an operative in %s, no clear report." % region


func _lookup_target_name(kind: ActionDefinition.TargetKind, id: String) -> String:
	match kind:
		ActionDefinition.TargetKind.ACTOR:
			var a: Actor = Actors.get_actor(StringName(id))
			if a != null:
				return a.display_name()
		ActionDefinition.TargetKind.KINGDOM:
			var k: Kingdom = WorldData.get_kingdom(id)
			if k != null:
				return k.kingdom_name
		ActionDefinition.TargetKind.PROVINCE:
			var p: Province = WorldData.get_province(id)
			if p != null:
				return p.province_name
		ActionDefinition.TargetKind.ORG_MEMBER:
			var m: OrgMember = Org.get_member(StringName(id))
			if m != null:
				return m.display_name
		_:
			pass
	return id if not id.is_empty() else "the matter"


# --- Loading -----------------------------------------------------------------

func _load_from_json(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("[Actions] Data file not found: %s" % path)
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[Actions] Malformed action data: %s" % path)
		return
	for d in parsed.get("actions", []):
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var def: ActionDefinition = ActionDefinition.from_dict(d)
		if def.id == &"":
			continue
		definitions[def.id] = def
