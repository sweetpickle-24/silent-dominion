extends Node
## Autoloaded as `Fidelity`. Coverage gating for the autonomous world (§9.6).
##
## Most of the world is not under the player's eye. The simulation
## still runs there — wars get declared, rulers die, treasuries fail —
## but the *texture* of what happens (court decrees, plot whispers,
## the deaths of minor advisors) is suppressed for kingdoms the player
## has no presence in. This keeps the public scroll from drowning the
## player in flavour from places they cannot influence, while leaving
## the structural events visible.
##
## Fidelity tier is derived from PlayerPicture coverage:
##   low   — visibility below COLD_THRESHOLD; flavour suppressed.
##   high  — visibility at or above COLD_THRESHOLD; everything fires.
##
## When a kingdom transitions low → high (the player just got eyes on
## it), this module synthesises a single catch-up dispatch that
## summarises the structural events of the last two years there. The
## spec calls it the "recent history of decisions" the player gets on
## extending intelligence into a low-fidelity region.

signal fidelity_lifted(kingdom_id: String)

const COLD_THRESHOLD: int = 20
# Number of months of structural history retained per kingdom.
const HISTORY_MONTHS: int = 24

# Structural event kinds we keep in the rolling history. Anything not
# in this list is treated as flavour and may be suppressed by the
# emitting subsystem if Fidelity.is_low() returns true.
const STRUCTURAL_KINDS: Array[StringName] = [
	&"war_declaration", &"peace_declaration", &"war_outcome",
	&"battle", &"army_shift",
	&"succession", &"regency_resolved",
	&"tax_change", &"fiscal_crisis", &"fiscal_recovery",
	&"plague", &"famine", &"earthquake", &"recovery",
	&"population_collapse", &"population_boom",
	&"construction_done",
]

# kingdom_id -> Array of {abs_day:int, kind:String, headline:String}
var _history: Dictionary = {}


func _ready() -> void:
	DevLogger.write("Fidelity: ready")
	EventBus.public_event.connect(_on_public_event)
	Picture.visibility_changed.connect(_on_visibility_changed)


# --- Public queries ----------------------------------------------------------

func is_low(kingdom_id: String) -> bool:
	if kingdom_id.is_empty():
		return false
	return Picture.score_for(kingdom_id) < COLD_THRESHOLD


func is_high(kingdom_id: String) -> bool:
	return not is_low(kingdom_id)


# --- History tracking --------------------------------------------------------

func _on_public_event(event: Dictionary) -> void:
	var kid: String = String(event.get("kingdom_id", ""))
	if kid.is_empty():
		return
	var kind: StringName = StringName(String(event.get("kind", "")))
	if not STRUCTURAL_KINDS.has(kind):
		return
	var arr: Array = _history.get(kid, [])
	arr.append({
		"abs_day":  int(event.get("abs_day", GameClock.absolute_day())),
		"kind":     String(kind),
		"headline": String(event.get("headline", "")),
	})
	# Trim anything older than HISTORY_MONTHS (~30 days each).
	var cutoff: int = GameClock.absolute_day() - HISTORY_MONTHS * 30
	while not arr.is_empty() and int(arr[0]["abs_day"]) < cutoff:
		arr.pop_front()
	_history[kid] = arr


# --- Catch-up dispatch -------------------------------------------------------

# Track the last known coverage state per kingdom so we only fire a
# single catch-up on the actual cold→warm transition.
var _was_cold: Dictionary = {}


func _on_visibility_changed(kingdom_id: String, score: int) -> void:
	var prev_cold: bool = bool(_was_cold.get(kingdom_id, true))
	var now_cold: bool = score < COLD_THRESHOLD
	_was_cold[kingdom_id] = now_cold
	if not prev_cold or now_cold:
		return
	_emit_catch_up(kingdom_id)
	fidelity_lifted.emit(kingdom_id)


func _emit_catch_up(kingdom_id: String) -> void:
	var arr: Array = _history.get(kingdom_id, [])
	if arr.is_empty():
		return
	var k: Kingdom = WorldData.get_kingdom(kingdom_id)
	var kname: String = k.kingdom_name if k != null else kingdom_id
	# Take the last several entries — too many drowns the dispatch.
	var sample: Array = arr if arr.size() <= 5 else arr.slice(arr.size() - 5, arr.size())
	var lines: Array[String] = []
	for entry in sample:
		var line: String = String(entry.get("headline", ""))
		if line.is_empty():
			continue
		lines.append("•  " + line)
	if lines.is_empty():
		return
	var body: String = "Eyes on %s for the first time in years. The recent record, drawn from a fresh operative's report:\n%s" % [
		kname, "\n".join(lines),
	]
	EventBus.public_event.emit({
		"kind":       &"catch_up",
		"kingdom_id": kingdom_id,
		"channel":    "operative",
		"headline":   "%s: a delayed accounting" % kname,
		"body":       body,
		"abs_day":    GameClock.absolute_day(),
	})


# --- Save / load -------------------------------------------------------------

func snapshot() -> Dictionary:
	var hist: Dictionary = {}
	for kid in _history.keys():
		hist[kid] = (_history[kid] as Array).duplicate(true)
	var was_cold: Dictionary = _was_cold.duplicate(true)
	return {
		"history":  hist,
		"was_cold": was_cold,
	}


func restore(d: Dictionary) -> void:
	_history.clear()
	var hist_raw: Variant = d.get("history", {})
	if hist_raw is Dictionary:
		for kid in (hist_raw as Dictionary).keys():
			var arr_raw: Variant = hist_raw[kid]
			if arr_raw is Array:
				_history[String(kid)] = (arr_raw as Array).duplicate(true)
	var wc_raw: Variant = d.get("was_cold", {})
	_was_cold = (wc_raw as Dictionary).duplicate(true) if wc_raw is Dictionary else {}
