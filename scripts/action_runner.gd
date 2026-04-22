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

	if not Exposure.allows_tier(def.tier):
		push_warning("[Actions] Action '%s' blocked by exposure level: %s" %
			[action_id, Exposure.level_name()])
		return Scheduler.INVALID_HANDLE

	if def.silver_cost > 0 and not Purse.can_afford(def.silver_cost):
		push_warning("[Actions] Action '%s' refused: purse cannot cover %d silver" %
			[action_id, def.silver_cost])
		return Scheduler.INVALID_HANDLE

	# Deduct now — spending the coin is part of issuing the action, not
	# of resolving it. If the letter fails, the silver stays spent.
	if def.silver_cost > 0:
		Purse.spend(def.silver_cost)

	var delay: int = _rng.randi_range(def.min_days_to_resolve, def.max_days_to_resolve)
	var fire_day: int = GameClock.absolute_day() + delay

	var descriptor: Dictionary = {
		"kind":          String(TASK_KIND),
		"action_id":     String(action_id),
		"target_id":     target_id,
		"issued_day":    GameClock.absolute_day(),
		"fire_day":      fire_day,
		"silver_cost":   def.silver_cost,
		"exposure_cost": def.exposure_cost,
	}

	var handle: int = Scheduler.schedule_task_on_day(fire_day, descriptor)
	EventBus.action_issued.emit(action_id, descriptor.duplicate(true))
	print("[Actions] Issued '%s' vs '%s'; resolves in %d days (day %d)." %
		[action_id, target_id, delay, fire_day])
	return handle


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

	var def: ActionDefinition = get_definition(action_id)
	if def == null:
		push_warning("[Actions] Cannot resolve unknown action: %s" % action_id)
		return

	var success_chance: float = _modified_success_chance(def, target_id)
	var success: bool = _rng.randf() < success_chance

	# Apply relationship changes BEFORE the report is built so the tone
	# of future letters can lean on the new standing if we ever want
	# that. The returned delta is echoed to the log for debugging.
	var rel_delta: int = _apply_relationship_effects(def, target_id, success)

	var report: Letter = _build_report(def, target_id, success)
	EventBus.letter_delivered.emit(report)

	if success:
		_maybe_publish_public_trace(def, target_id)
	else:
		_apply_failure_exposure(def)

	EventBus.action_resolved.emit(action_id, {
		"success":      success,
		"target_id":    target_id,
		"summary":      report.subject,
		"rel_delta":    rel_delta,
	})


## A botched covert move leaves loose threads someone may follow. Nudge
## exposure up by a small amount that scales with the action's tier.
## Doesn't push the meter into a new band on its own, but stacks across
## a bad season. Passive/watch actions are exempt — nothing happens
## there that can be traced back.
func _apply_failure_exposure(def: ActionDefinition) -> void:
	if def.exposure_cost <= 0.0:
		return
	var tail: float = 0.0
	match def.tier:
		ActionDefinition.Tier.DEEP_SHADOW: tail = 1.0
		ActionDefinition.Tier.ACTIVE:      tail = 2.0
		ActionDefinition.Tier.HIGH:        tail = 4.0
	if tail > 0.0:
		Exposure.bump(tail, "failed_" + String(def.id))


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

func _build_report(def: ActionDefinition, target_id: String, success: bool) -> Letter:
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

	# Body uses the linked name so the reader can click through to the
	# target's dossier from the letter.
	var linked_name: String = _linked_target(def.target_kind, target_id, target_name)
	var body: String = _body_for(def, linked_name, success)

	return Letter.create(letter_id, def.report_sender, date, subject, body, &"action")


## Wrap an Actor target name in a BBCode url so the letter view can
## open the dossier on click. Non-Actor targets return plain text.
## The colour is a dark wine red that reads as "interactive" on parchment.
func _linked_target(kind: ActionDefinition.TargetKind, id: String, display: String) -> String:
	if kind == ActionDefinition.TargetKind.ACTOR and not id.is_empty():
		return "[url=actor:%s][color=#702020][b]%s[/b][/color][/url]" % [id, display]
	return display


func _body_for(def: ActionDefinition, target: String, success: bool) -> String:
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
