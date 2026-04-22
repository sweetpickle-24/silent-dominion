extends Node
## Autoloaded as `Exposure`. Tracks how detectable the player has become.
##
## Implements §3.2. A single global 0-100 meter; rises when actions are
## issued (each ActionDefinition.exposure_cost), decays slowly on every
## game-day that passes.
##
## The player never sees the raw number (§7.6). The ExposureIndicator
## widget on the table exposes only the qualitative level name.
##
## Five levels, matching the doc's table:
##   0-20   DEEP_SHADOW   — full palette
##   21-45  WHISPERED     — full palette (tier 3 starts to feel risky)
##   46-65  KNOWN         — tier 3 actions blocked
##   66-85  HUNTED        — tier 2 also blocked
##   86-100 EXPOSED       — almost everything blocked

signal value_changed(value: float)
signal level_changed(level: int)

enum Level { DEEP_SHADOW, WHISPERED, KNOWN, HUNTED, EXPOSED }

# Decay per game-day. At 0.25/day the meter drifts down by ~7.5/month,
# which is the rate the "go dark and wait a season" play style implies.
const DECAY_PER_DAY: float = 0.25

const LEVEL_THRESHOLDS: Array[int] = [21, 46, 66, 86]    # >= threshold bumps up

const LEVEL_NAMES: Dictionary = {
	Level.DEEP_SHADOW: "Deep shadow",
	Level.WHISPERED:   "Whispered",
	Level.KNOWN:       "Known quantity",
	Level.HUNTED:      "Hunted",
	Level.EXPOSED:     "Exposed",
}

const LEVEL_BLURBS: Dictionary = {
	Level.DEEP_SHADOW: "No one who matters has noticed you.",
	Level.WHISPERED:   "A handful of idle tongues speak of you, but no one listens yet.",
	Level.KNOWN:       "Your name is on lips you do not want it on. High-tier work is no longer safe.",
	Level.HUNTED:      "Paid eyes search for you. Active manipulation will be noticed.",
	Level.EXPOSED:     "You are the story. Almost no move is quiet enough.",
}

var value: float = 0.0
var level: Level = Level.DEEP_SHADOW


func _ready() -> void:
	EventBus.action_issued.connect(_on_action_issued)
	GameClock.day_passed.connect(_on_day_passed)


# --- Public API --------------------------------------------------------------

func level_name() -> String:
	return String(LEVEL_NAMES[level])


func level_blurb() -> String:
	return String(LEVEL_BLURBS[level])


## Returns true if an action of the given tier is currently permitted.
## Rules per §3.2:
##   Tier 3 (HIGH)   blocked once Known-quantity or worse.
##   Tier 2 (ACTIVE) blocked once Hunted or worse.
##   Tier 1 (DEEP)   blocked only when Exposed.
func allows_tier(tier: ActionDefinition.Tier) -> bool:
	match tier:
		ActionDefinition.Tier.HIGH:
			return level <= Level.WHISPERED
		ActionDefinition.Tier.ACTIVE:
			return level <= Level.KNOWN
		_:
			return level != Level.EXPOSED


## Public bump. Positive values raise exposure, negative values lower it.
## Used by systems other than the direct action-issued hook (whisper
## follow-ups, botched covert actions, discovered ties).
func bump(delta: float, _reason: String = "") -> void:
	_add(delta)


## Reason string for a blocked action. Returns empty string if allowed.
func block_reason(tier: ActionDefinition.Tier) -> String:
	if allows_tier(tier):
		return ""
	match tier:
		ActionDefinition.Tier.HIGH:
			return "Too visible for a high-intervention move. Wait for the watchers to lose interest."
		ActionDefinition.Tier.ACTIVE:
			return "You are being watched too closely for active manipulation."
		_:
			return "Every corner is watched. Even a whisper would carry."


# --- Hooks -------------------------------------------------------------------

func _on_action_issued(action_id: StringName, _payload: Dictionary) -> void:
	var def: ActionDefinition = Actions.get_definition(action_id)
	if def == null:
		return
	_add(float(def.exposure_cost))


func _on_day_passed(_y: int, _m: int, _d: int) -> void:
	if value <= 0.0:
		return
	_add(-DECAY_PER_DAY)


# --- Internal ----------------------------------------------------------------

func _add(delta: float) -> void:
	var new_value: float = clampf(value + delta, 0.0, 100.0)
	if is_equal_approx(new_value, value):
		return
	value = new_value
	value_changed.emit(value)

	var new_level: Level = _level_for(value)
	if new_level != level:
		level = new_level
		level_changed.emit(int(level))


func _level_for(v: float) -> Level:
	var iv: int = int(v)
	if iv >= LEVEL_THRESHOLDS[3]:
		return Level.EXPOSED
	if iv >= LEVEL_THRESHOLDS[2]:
		return Level.HUNTED
	if iv >= LEVEL_THRESHOLDS[1]:
		return Level.KNOWN
	if iv >= LEVEL_THRESHOLDS[0]:
		return Level.WHISPERED
	return Level.DEEP_SHADOW


# --- Save/load hooks ---------------------------------------------------------

func snapshot() -> Dictionary:
	return { "value": value }


func restore(d: Dictionary) -> void:
	value = clampf(float(d.get("value", 0.0)), 0.0, 100.0)
	level = _level_for(value)
	value_changed.emit(value)
	level_changed.emit(int(level))
