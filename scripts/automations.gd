extends Node
## Autoloaded as `Automations`. The engine that runs the player's
## standing orders (§13.2).
##
## A rule is a "delegation of already-learned work": the player
## identified a Memoirs pattern they trust and said "run it on its
## own from now on". The engine ticks monthly, and for every rule
## whose cadence has elapsed it:
##
##   1. Confirms the pattern is still in the library and not too
##      stale. Missing or unverified patterns pause the rule and
##      route a letter to the inbox asking the player to walk
##      another pass by hand.
##   2. For §13.4: if the selected target's dominant religion is
##      opaque to the player, pauses the rule. Automation cannot
##      teach what hands-on work has not taught first.
##   3. Picks a target. For ACTOR scope this is the named actor.
##      For KINGDOM / REGION scope the engine picks the best profile
##      match living in that scope.
##   4. Dispatches via `Actions.issue(..., auto=true)`. The marker
##      prevents religion engagement and memoir recording from
##      counting the run as manual.
##
## Rules are never created silently. The compose view calls
## `create_actor_rule()` after the player opts in; the memoirs view
## exposes pause / resume / cancel.

signal rule_added(id: StringName)
signal rule_changed(id: StringName)
signal rule_removed(id: StringName)

const STALE_TOLERATED: bool = true
# If true the engine will still fire on patterns flagged unverified
# (but flag the rule). If false it pauses immediately on staleness.
# Unverified-but-firing is the more interesting gameplay shape —
# the organisation *does* keep trying, and the warnings get louder.

const LOSS_STREAK_PAUSE: int = 3
# After this many consecutive failures the rule self-pauses. Forces
# the player to re-engage manually rather than burning silver on
# something the world has clearly changed underneath.

# id -> AutomationRule
var rules: Dictionary = {}

# rule_id -> int (streak of consecutive failures)
var _loss_streaks: Dictionary = {}


func _ready() -> void:
	GameClock.month_passed.connect(_on_month_passed)
	EventBus.action_resolved.connect(_on_action_resolved)


# --- Public API --------------------------------------------------------------

func all_rules() -> Array[AutomationRule]:
	var out: Array[AutomationRule] = []
	for r in rules.values():
		out.append(r)
	return out


func active_rules() -> Array[AutomationRule]:
	var out: Array[AutomationRule] = []
	for r in rules.values():
		if r.active and not r.paused:
			out.append(r)
	return out


func get_rule(id: StringName) -> AutomationRule:
	return rules.get(id, null)


## Count of running standing orders — used by the table to label
## the Memoirs button ("Memoirs · 4 standing").
func active_count() -> int:
	return active_rules().size()


## Create a rule keyed to a specific actor. Happens when the player
## sees a memoir chip in compose and confirms "from now on, handle
## them yourself". Returns null if no matching pattern exists.
func create_actor_rule(
		action_id: StringName,
		target_actor_id: StringName,
		cadence_months: int = 6,
) -> AutomationRule:
	var target: Actor = Actors.get_actor(target_actor_id)
	if target == null:
		return null
	var pattern: MemoirPattern = Memoirs.match_for(action_id, target)
	if pattern == null:
		return null
	var r: AutomationRule = AutomationRule.new()
	r.id = StringName("rule_%s_%s_%d" % [String(action_id), String(target_actor_id), Time.get_ticks_msec()])
	r.scope = AutomationRule.Scope.ACTOR
	r.action_id = action_id
	r.target_actor_id = target_actor_id
	r.pattern_id = pattern.id
	r.cadence_months = clampi(cadence_months, 1, 60)
	r.active = true
	r.created_year = -GameClock.year
	r.last_fired_abs_day = GameClock.absolute_day()
	rules[r.id] = r
	rule_added.emit(r.id)
	_announce_adopted(r, target)
	return r


## §13.3 seed — fires the rule's action against any matching actor
## in a given kingdom. Still bounded by the pattern's culture tag,
## so an "athens-shaped merchant" rule will not target Carthaginians.
func create_kingdom_rule(
		action_id: StringName,
		kingdom_id: String,
		pattern_id: StringName,
		cadence_months: int = 6,
) -> AutomationRule:
	var pattern: MemoirPattern = Memoirs.get_pattern(pattern_id)
	if pattern == null:
		return null
	var r: AutomationRule = AutomationRule.new()
	r.id = StringName("rule_%s_%s_%d" % [String(action_id), kingdom_id, Time.get_ticks_msec()])
	r.scope = AutomationRule.Scope.KINGDOM
	r.action_id = action_id
	r.kingdom_id = kingdom_id
	r.pattern_id = pattern_id
	r.cadence_months = clampi(cadence_months, 1, 60)
	r.active = true
	r.created_year = -GameClock.year
	r.last_fired_abs_day = GameClock.absolute_day()
	rules[r.id] = r
	rule_added.emit(r.id)
	return r


func pause(id: StringName, reason: StringName = &"by_hand") -> void:
	var r: AutomationRule = rules.get(id, null)
	if r == null:
		return
	r.paused = true
	r.paused_reason = reason
	rule_changed.emit(id)


func resume(id: StringName) -> void:
	var r: AutomationRule = rules.get(id, null)
	if r == null:
		return
	r.paused = false
	r.paused_reason = &""
	rule_changed.emit(id)


func cancel(id: StringName) -> void:
	if not rules.has(id):
		return
	rules.erase(id)
	_loss_streaks.erase(id)
	rule_removed.emit(id)


# --- Monthly tick ------------------------------------------------------------

func _on_month_passed(_y: int, _m: int) -> void:
	if rules.is_empty():
		return
	var today: int = GameClock.absolute_day()
	for r in rules.values():
		if not r.active or r.paused:
			continue
		var since_days: int = today - r.last_fired_abs_day
		var needed_days: int = r.cadence_months * 30
		if since_days < needed_days:
			continue
		_fire(r)


func _fire(r: AutomationRule) -> void:
	# 1. Confirm the pattern still lives.
	var pattern: MemoirPattern = Memoirs.get_pattern(r.pattern_id)
	if pattern == null:
		_pause_with_reason(r, &"pattern_gone",
			"The library lost the profile this order was built on. It will not fire again until you re-learn it.")
		return
	# 2. Pick a concrete target.
	var target: Actor = _pick_target(r, pattern)
	if target == null:
		# No plausible target right now — don't pause, just skip. The
		# cadence is the throttle.
		return
	# 3. §13.4 religion gate. If the target's dominant faith is
	# opaque to the player, automation refuses to run.
	if target.kingdom_id != "":
		var dominant: Religion = Religions.dominant_in(target.kingdom_id)
		if dominant != null and not Religions.can_automate(dominant.id):
			_pause_with_reason(r, &"religion_opaque",
				"%s still shapes that room. You have not walked that faith by hand — no standing order can."
					% dominant.name)
			return
	# 3b. §22.4 transition gate. Automations targeting the kingdom
	# the player is still settling into are held for the duration
	# of the transition window — skip the firing this tick, not
	# pause the rule. The cadence picks it back up once transition
	# ends.
	if Base != null and Base.is_in_transition_for(target.kingdom_id):
		return
	# 4. Staleness + loss streak checks.
	if pattern.unverified and not STALE_TOLERATED:
		_pause_with_reason(r, &"pattern_stale",
			"The profile behind this order is unverified. Your factotum has stood it down until you refresh it.")
		return
	# 5. Dispatch.
	var handle: int = Actions.issue(r.action_id, String(target.id), true)
	if handle == Scheduler.INVALID_HANDLE:
		# Usually exposure gate or funding shortfall — no point
		# retrying this month.
		return
	r.last_fired_abs_day = GameClock.absolute_day()
	r.fire_count += 1
	rule_changed.emit(r.id)


func _pick_target(r: AutomationRule, pattern: MemoirPattern) -> Actor:
	match r.scope:
		AutomationRule.Scope.ACTOR:
			var a: Actor = Actors.get_actor(r.target_actor_id)
			if a == null or not a.is_alive():
				return null
			return a
		AutomationRule.Scope.KINGDOM:
			return _best_match_in_kingdom(r.kingdom_id, pattern)
		AutomationRule.Scope.REGION:
			# Fold region targeting down to a member kingdom pick.
			# WorldData doesn't model regions yet; we treat region_id
			# as a kingdom until that's there.
			return _best_match_in_kingdom(r.region_id, pattern)
	return null


func _best_match_in_kingdom(kid: String, pattern: MemoirPattern) -> Actor:
	if kid == "":
		return null
	var best: Actor = null
	var best_score: float = 0.0
	for a in Actors.actors_in_kingdom(kid):
		if not a.is_alive():
			continue
		var ap: MemoirPattern = Memoirs.match_for(pattern.action_id, a)
		if ap == null or ap.id != pattern.id:
			continue
		var score: float = 1.0
		if score > best_score:
			best = a
			best_score = score
	return best


# --- Outcome tracking --------------------------------------------------------

func _on_action_resolved(action_id: StringName, result: Dictionary) -> void:
	if not bool(result.get("auto", false)):
		return
	# Find the rule this run belonged to. Match on action + target.
	var tid: String = String(result.get("target_id", ""))
	var success: bool = bool(result.get("success", false))
	for r in rules.values():
		if r.action_id != action_id:
			continue
		if r.scope == AutomationRule.Scope.ACTOR and String(r.target_actor_id) != tid:
			continue
		if success:
			r.success_count += 1
			_loss_streaks[r.id] = 0
		else:
			var streak: int = int(_loss_streaks.get(r.id, 0)) + 1
			_loss_streaks[r.id] = streak
			if streak >= LOSS_STREAK_PAUSE:
				_pause_with_reason(r, &"losses_mounting",
					"Three failures in a row on a standing order. Your hands have stood it down until you look at it yourself.")
		rule_changed.emit(r.id)
		return


# --- Internals ---------------------------------------------------------------

func _pause_with_reason(r: AutomationRule, reason: StringName, body: String) -> void:
	r.paused = true
	r.paused_reason = reason
	rule_changed.emit(r.id)
	_announce_paused(r, body)


func _announce_adopted(r: AutomationRule, target: Actor) -> void:
	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var body: String = (
		"You have entered this into the library as a standing order: "
		+ "%s against %s, every %d months. Your hands will pick it up and run it without your voice from now on — "
		+ "they will stop and write if the pattern shifts."
	) % [
		_pretty_action(r.action_id),
		target.display_name(),
		r.cadence_months,
	]
	var letter: Letter = Letter.create(
		StringName("automation_adopted_%s" % String(r.id)),
		"Your factotum",
		date,
		"A standing order on %s" % target.display_name(),
		body,
		&"operative"
	)
	EventBus.letter_delivered.emit(letter)


func _announce_paused(r: AutomationRule, body: String) -> void:
	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var label: String = _pretty_action(r.action_id)
	var letter: Letter = Letter.create(
		StringName("automation_paused_%s_%d" % [String(r.id), Time.get_ticks_msec()]),
		"Your factotum",
		date,
		"Standing order stood down — %s" % label,
		body,
		&"operative"
	)
	EventBus.letter_delivered.emit(letter)


func _pretty_action(action_id: StringName) -> String:
	var def: ActionDefinition = Actions.get_definition(action_id)
	if def != null and def.display_name != "":
		return def.display_name
	return String(action_id).replace("_", " ")


# --- Save / load -------------------------------------------------------------

func snapshot() -> Dictionary:
	var arr: Array = []
	for r in rules.values():
		arr.append(r.to_dict())
	return {
		"rules":         arr,
		"_loss_streaks": _loss_streaks.duplicate(true),
	}


func restore(d: Dictionary) -> void:
	rules.clear()
	for entry in d.get("rules", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var r: AutomationRule = AutomationRule.from_dict(entry)
		if r.id == &"":
			continue
		rules[r.id] = r
	_loss_streaks = (d.get("_loss_streaks", {}) as Dictionary).duplicate(true)
