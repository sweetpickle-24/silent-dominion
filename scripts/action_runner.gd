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

# action_id (StringName) -> ActionDefinition
var definitions: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_load_from_json(ACTION_DATA_PATH)
	Scheduler.task_due.connect(_on_task_due)
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

	var success: bool = _rng.randf() < success_chance

	# Apply relationship changes BEFORE the report is built so the tone
	# of future letters can lean on the new standing if we ever want
	# that. The returned delta is echoed to the log for debugging.
	var rel_delta: int = _apply_relationship_effects(def, target_id, success)

	# Side-effects that should be resolved BEFORE the report is written,
	# so the report text can name whoever was quieted.
	var extras: Dictionary = _apply_special_effects(def, target_id, success)

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
