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

# Tick timing history for debug overlay tab 3.
const _TICK_HISTORY_CAP: int = 500
var _tick_timings: Array = []

# === Local signals (NOT EventBus) ===
signal speed_changed(new_speed: StringName)
signal pause_changed(now_paused: bool)
signal era_about_to_transition(old_era: StringName, new_era: StringName)

# Cached autoload references.
var _logger: Node
var _event_bus: Node
var _rule_evaluator: Node

# Era transition data loaded from data/eras/transitions/.
var _era_transitions_by_from_era: Dictionary = {}   # StringName -> Array[EraTransition]

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
	_rule_evaluator = get_node("/root/RuleEvaluator")
	current_season = _season_for_day(current_day)
	_load_era_transitions()
	call_deferred("_register_save_handlers")
	call_deferred("_register_auto_pause_subscription")
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


func _load_era_transitions() -> void:
	var dir := DirAccess.open("res://data/eras/transitions/")
	if dir == null:
		_logger.warn(LogChannels.TIME, "data/eras/transitions/ does not exist; no era transitions loaded")
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path: String = "res://data/eras/transitions/%s" % file_name
			var resource = ResourceLoader.load(path)
			if resource is EraTransition:
				if not _era_transitions_by_from_era.has(resource.from_era):
					_era_transitions_by_from_era[resource.from_era] = []
				_era_transitions_by_from_era[resource.from_era].append(resource)
		file_name = dir.get_next()
	dir.list_dir_end()
	var total: int = 0
	for key in _era_transitions_by_from_era:
		total += _era_transitions_by_from_era[key].size()
	_logger.info(LogChannels.TIME, "Era transitions loaded", {"transition_count": total})


func _check_era_transition() -> void:
	var transitions: Array = _era_transitions_by_from_era.get(current_era, [])
	if transitions.is_empty():
		return
	var context: RuleContext = RuleContext.world_only(current_day, current_era)
	for transition: EraTransition in transitions:
		if _rule_evaluator.evaluate_predicate(transition.trigger_condition, context):
			_transition_to_era(transition.to_era, transition.description)
			return  # one transition per day max per C2


func _transition_to_era(new_era: StringName, description: String) -> void:
	var old_era: StringName = current_era
	era_about_to_transition.emit(old_era, new_era)
	current_era = new_era
	var event := EraTransitionedEvent.new()
	event.old_era = old_era
	event.new_era = new_era
	event.transition_day = current_day
	event.description = description
	_event_bus.dispatch(event)
	# Auto-pause on era transition per §35.16
	var auto_pause := AutoPauseTriggeredEvent.new()
	auto_pause.trigger_category = AutoPauseCategoryValues.ERA_TRANSITION
	auto_pause.trigger_source_event_id = StringName("era_transition_%d" % current_day)
	auto_pause.urgency = &"normal"
	_event_bus.dispatch(auto_pause)
	_logger.info(LogChannels.TIME, "Era transition fired", {
		"old_era": old_era,
		"new_era": new_era,
		"day": current_day,
	})


var _auto_pause_sub  # SubscriptionHandle

func _register_auto_pause_subscription() -> void:
	_auto_pause_sub = _event_bus.subscribe(
		preload("res://scripts/data/events/auto_pause_triggered_event.gd"),
		Callable(self, "_on_auto_pause_triggered"),
		100,
		&"",
		EndOfTickPhases.UI,
	)


func _on_auto_pause_triggered(event: AutoPauseTriggeredEvent) -> void:
	set_paused(true, StringName("auto_pause:" + event.trigger_category))
	set_speed(SpeedValues.X1)
	_logger.info(LogChannels.TIME, "Auto-paused", {
		"category": event.trigger_category,
		"urgency": event.urgency,
	})


func get_tick_timings() -> Array:
	return _tick_timings.duplicate()


func _register_save_handlers() -> void:
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"time_state",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)


func snapshot_state() -> Dictionary:
	return {
		"current_day": current_day,
		"current_year": current_year,
		"current_era": current_era,
		"current_season": current_season,
	}


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	current_day = state.get("current_day", 0)
	current_year = state.get("current_year", 0)
	current_era = state.get("current_era", &"ancient")
	current_season = state.get("current_season", &"winter")
	_accumulator = 0.0
	_tick_count_today = 0
	_logger.info(LogChannels.TIME, "TimeKeeper state applied from load", {
		"day": current_day,
		"era": current_era,
		"season": current_season,
	})


# --- Internal ---

func _advance_one_day() -> void:
	var start_usec: int = Time.get_ticks_usec()

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

	_check_era_transition()

	var duration_ms: float = (Time.get_ticks_usec() - start_usec) / 1000.0
	_tick_timings.append({"day": current_day, "duration_ms": duration_ms})
	if _tick_timings.size() > _TICK_HISTORY_CAP:
		_tick_timings.pop_front()
	if duration_ms > 10.0:
		_logger.warn(LogChannels.TIME, "Tick exceeded budget", {
			"day": current_day,
			"duration_ms": duration_ms,
		})


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
