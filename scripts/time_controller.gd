extends Node
## Autoloaded as `TimeCtl`. Owns the glue between player preferences
## (`Prefs`) and the clock/save machinery:
##
##   - §10.4 auto-pause on high-priority letters.
##   - §10.8 continuous autosave to a rotating A/B pair of slots.
##
## This autoload has no state of its own worth saving; everything
## derives from Prefs + GameClock + Inbox. Disable a feature in Prefs
## and TimeCtl becomes inert.

const AUTOSAVE_SLOT_A: String = "autosave_a"
const AUTOSAVE_SLOT_B: String = "autosave_b"

# Internal: rotating slot cursor. Lives only in memory; on launch we
# start with A, first save goes to A, next to B, etc. A crash leaves
# both files intact so the player can resume from whichever is newer.
var _next_autosave_slot: String = AUTOSAVE_SLOT_A

# Last absolute day we autosaved on. -1 = never this session.
var _last_autosave_abs_day: int = -1


func _ready() -> void:
	DevLogger.write("TimeCtl: ready")
	EventBus.letter_delivered.connect(_on_letter_delivered)
	GameClock.day_passed.connect(_on_day_passed)


# --- §10.4 Auto-pause -------------------------------------------------------

func _on_letter_delivered(letter: Letter) -> void:
	if Prefs == null or not Prefs.auto_pause_on_priority:
		return
	if letter == null or not letter.is_high_priority():
		return
	# Don't slam the clock to pause if the player is already paused
	# — that would mask the fact that *this* letter was the trigger.
	if GameClock.speed == GameClock.Speed.PAUSED:
		return
	GameClock.set_speed(GameClock.Speed.PAUSED)


# --- §10.8 Continuous autosave ---------------------------------------------

func _on_day_passed(_y: int, _m: int, _d: int) -> void:
	if Prefs == null or not Prefs.continuous_autosave:
		return
	var today: int = GameClock.absolute_day()
	if _last_autosave_abs_day < 0:
		# First tick after launch/load: seed the clock but don't save
		# immediately, we already have whatever state we just loaded.
		_last_autosave_abs_day = today
		return
	if today - _last_autosave_abs_day < max(1, Prefs.autosave_interval_days):
		return

	var slot: String = _next_autosave_slot
	if SaveManager.save_to_slot(slot):
		_last_autosave_abs_day = today
		_next_autosave_slot = AUTOSAVE_SLOT_B if slot == AUTOSAVE_SLOT_A else AUTOSAVE_SLOT_A


# --- Public helpers ---------------------------------------------------------

## Which autosave slot holds the newer file, or empty if neither
## exists. Used by menus and the resume-on-launch flow.
func latest_autosave_slot() -> String:
	var a: Dictionary = SaveManager.slot_info(AUTOSAVE_SLOT_A)
	var b: Dictionary = SaveManager.slot_info(AUTOSAVE_SLOT_B)
	if a.is_empty() and b.is_empty():
		return ""
	if a.is_empty():
		return AUTOSAVE_SLOT_B
	if b.is_empty():
		return AUTOSAVE_SLOT_A
	# Compare saved_at strings lexicographically — they're ISO-like
	# `YYYY-MM-DDTHH:MM:SS` from Time.get_datetime_string_from_system.
	if String(b.get("saved_at", "")) > String(a.get("saved_at", "")):
		return AUTOSAVE_SLOT_B
	return AUTOSAVE_SLOT_A


## Force an autosave now (e.g. before quitting). Returns the slot
## written, or empty on failure.
func force_autosave() -> String:
	var slot: String = _next_autosave_slot
	if not SaveManager.save_to_slot(slot):
		return ""
	_last_autosave_abs_day = GameClock.absolute_day()
	_next_autosave_slot = AUTOSAVE_SLOT_B if slot == AUTOSAVE_SLOT_A else AUTOSAVE_SLOT_A
	return slot
