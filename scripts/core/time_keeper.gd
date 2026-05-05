extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

# === Calendar state (saved) ===
var current_day: int = 0
var current_year: int = 0
var current_era: StringName = EraValues.ANCIENT
var current_season: StringName = SeasonValues.WINTER

# Scenario start date for display purposes.
@export var scenario_start_year_bce: int = 500
@export var scenario_start_month: int = 1
@export var scenario_start_day_of_month: int = 1

# === Tick state (not saved — re-derives on load) ===
var current_speed: StringName = SpeedValues.X1
var is_paused: bool = false
var _accumulator: float = 0.0
var _tick_count_today: int = 0

# === Local signals (NOT EventBus) ===
signal speed_changed(new_speed: StringName)
signal pause_changed(now_paused: bool)
signal era_about_to_transition(old_era: StringName, new_era: StringName)

# Cached autoload references.
var _logger: Node
var _event_bus: Node

# Season boundaries by day-of-year (Northern Hemisphere meteorological).
# Jan 1 = day-of-year 0.
# Winter: 0-58 (Jan 1 – Feb 28), Spring: 59-150 (Mar 1 – May 31),
# Summer: 151-242 (Jun 1 – Aug 31), Autumn: 243-333 (Sep 1 – Nov 30),
# Winter: 334-364 (Dec 1 – Dec 31).
const _SPRING_START: int = 59
const _SUMMER_START: int = 151
const _AUTUMN_START: int = 243
const _WINTER2_START: int = 334


func _ready() -> void:
	_logger = get_node("/root/Logger")
	_event_bus = get_node("/root/EventBus")
	current_season = _season_for_day(current_day)
	_logger.info(LogChannels.TIME, "TimeKeeper ready", {
		"speed": current_speed,
		"paused": is_paused,
	})


func _process(delta: float) -> void:
	if is_paused:
		return
	var days_per_second: int = _days_per_second_for(current_speed)
	if days_per_second == 0:
		return
	_accumulator += delta * days_per_second
	while _accumulator >= 1.0:
		_accumulator -= 1.0
		_advance_one_day()


# --- Public API ---

func set_paused(paused: bool, source: StringName = &"player") -> void:
	if is_paused == paused:
		return
	is_paused = paused
	pause_changed.emit(paused)
	_logger.info(LogChannels.TIME, "Pause changed: %s (source: %s)" % [paused, source])


func set_speed(speed: StringName) -> void:
	if current_speed == speed:
		return
	current_speed = speed
	speed_changed.emit(speed)
	_logger.info(LogChannels.TIME, "Speed: %s" % speed)


func get_display_date() -> String:
	var day_offset_years: int = int(floor(current_day / 365.0))
	var resolved_year: int = -scenario_start_year_bce + day_offset_years + 1

	var year_display: int
	var era_suffix: String
	if resolved_year <= 0:
		year_display = -resolved_year + 1
		era_suffix = "BCE"
	else:
		year_display = resolved_year
		era_suffix = "CE"

	var day_of_year: int = current_day % 365
	var month_day: Dictionary = _month_day_from_doy(day_of_year)
	var month_name: String = MonthValues.NAMES[month_day.month]

	return "%d %s %d %s \u00b7 %s" % [
		month_day.day,
		month_name,
		year_display,
		era_suffix,
		EraValues.DISPLAY_NAMES[current_era],
	]


func apply_loaded_state(day: int, year: int, era: StringName, season: StringName) -> void:
	current_day = day
	current_year = year
	current_era = era
	current_season = season
	_accumulator = 0.0
	_tick_count_today = 0
	_logger.info(LogChannels.TIME, "TimeKeeper state applied from load", {
		"day": current_day,
		"era": current_era,
		"season": current_season,
	})


# --- Internal ---

func _advance_one_day() -> void:
	current_day += 1
	var old_year: int = current_year
	current_year = current_day / 365
	current_season = _season_for_day(current_day)

	var event := GameDayTickedEvent.new()
	event.day = current_day
	event.year = current_year
	event.era = current_era
	event.season = current_season
	event.year_changed = (current_year != old_year)

	_event_bus.dispatch(event)
	_event_bus.end_of_tick(current_day)

	# TODO: _check_era_transition() — requires RuleEvaluator (Step 3)


func _days_per_second_for(speed: StringName) -> int:
	match speed:
		SpeedValues.X1: return 1
		SpeedValues.X2: return 2
		SpeedValues.X4: return 4
		SpeedValues.X16: return 16
		_: return 0


func _season_for_day(day: int) -> StringName:
	var doy: int = day % 365
	if doy < _SPRING_START:
		return SeasonValues.WINTER
	elif doy < _SUMMER_START:
		return SeasonValues.SPRING
	elif doy < _AUTUMN_START:
		return SeasonValues.SUMMER
	elif doy < _WINTER2_START:
		return SeasonValues.AUTUMN
	else:
		return SeasonValues.WINTER


func _month_day_from_doy(day_of_year: int) -> Dictionary:
	var remaining: int = day_of_year
	for month_index in range(12):
		var days_in_month: int = MonthValues.DAYS_PER_MONTH[month_index]
		if remaining < days_in_month:
			return {"month": month_index, "day": remaining + 1}
		remaining -= days_in_month
	# Fallback (should not happen with 0-364 range).
	return {"month": 11, "day": 31}
