class_name Place
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG
const _GameDayTickedEventScript := preload("res://scripts/data/events/game_day_ticked_event.gd")

var _event_bus: Node
var _logger: Node
var _world_registry: Node
var _time_keeper: Node

# Runtime per-place state (mutable, saved). Copy of WorldRegistry at _ready, then drifts.
var _place_states: Dictionary = {}   # StringName place_id -> PlaceRecord


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_world_registry = get_node("/root/WorldRegistry")
	_time_keeper = get_node("/root/TimeKeeper")
	_event_bus.subscribe(
		_GameDayTickedEventScript,
		Callable(self, "_on_game_day_ticked"),
		10,
		&"",
		EndOfTickPhases.WORLD_SHARED,
	)
	_initialize_runtime_state_from_registry()
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"place_states",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)
	var total_pop: int = 0
	for pid: StringName in _place_states:
		total_pop += (_place_states[pid] as PlaceRecord).population
	_logger.info(LogChannels.PLACE, "Place mechanic ready", {
		"place_count": _place_states.size(),
		"total_population": total_pop,
	})


func _initialize_runtime_state_from_registry() -> void:
	for place_id: StringName in _world_registry.all_place_ids():
		var registry_record: PlaceRecord = _world_registry.get_place(place_id)
		var runtime_record: PlaceRecord = registry_record.duplicate(true) as PlaceRecord
		_place_states[place_id] = runtime_record


func _on_game_day_ticked(event: GameDayTickedEvent) -> void:
	update_per_day(event.day)


func update_per_day(day: int) -> void:
	for place_id: StringName in _place_states.keys():
		var record: PlaceRecord = _place_states[place_id]
		_update_place(record, day)
	if day % 365 == 0 and day > 0:
		var total_pop: int = 0
		var total_yield: int = 0
		for pid: StringName in _place_states:
			var r: PlaceRecord = _place_states[pid]
			total_pop += r.population
			total_yield += r.accumulated_yield
		_logger.info(LogChannels.PLACE, "Annual summary", {
			"year": day / 365,
			"total_population": total_pop,
			"total_accumulated_yield": total_yield,
			"era": _time_keeper.current_era,
		})


func _update_place(record: PlaceRecord, day: int) -> void:
	match record.place_type:
		PlaceTypeValues.CITY: _update_city(record, day)
		PlaceTypeValues.TOWN: _update_town(record, day)
		PlaceTypeValues.VILLAGE: _update_village(record, day)
		PlaceTypeValues.MINE: _update_mine(record, day)
		PlaceTypeValues.MONASTERY: _update_monastery(record, day)
		PlaceTypeValues.FORT: _update_fort(record, day)
		PlaceTypeValues.TRADING_POST: _update_trading_post(record, day)
		PlaceTypeValues.LIGHTHOUSE: _update_lighthouse(record, day)
		PlaceTypeValues.NAMED_SITE: _update_named_site(record, day)
		PlaceTypeValues.ACADEMY: _update_monastery(record, day)
		PlaceTypeValues.LIBRARY: _update_monastery(record, day)
		_: push_error("Unknown place_type: %s on place %s" % [record.place_type, record.id])


# === Per-place-type update routines ===
# All numbers are placeholder calibration values. T2 calibration revises.

func _update_city(record: PlaceRecord, _day: int) -> void:
	# ~0.1% annual growth baseline = 0.00000274 per day. Infrastructure bonus up to 2×.
	var pop_drift_rate: float = 0.00000274 * (1.0 + record.infrastructure_level / 100.0)
	var pop_delta: int = int(record.population * pop_drift_rate)
	if pop_delta < 1 and record.population > 100:
		pop_delta = 1
	record.population += pop_delta
	record.tax_yield_per_day = _compute_city_tax_yield(record)
	record.accumulated_yield += record.tax_yield_per_day


func _compute_city_tax_yield(record: PlaceRecord) -> int:
	var infrastructure_factor: float = 1.0 + record.infrastructure_level / 100.0
	var era_factor: float = _era_yield_multiplier()
	return int((record.population / 1000.0) * infrastructure_factor * era_factor)


func _update_town(record: PlaceRecord, _day: int) -> void:
	var pop_drift_rate: float = 0.0000020 * (1.0 + record.infrastructure_level / 100.0)
	var pop_delta: int = int(record.population * pop_drift_rate)
	if pop_delta < 1 and record.population > 100:
		pop_delta = 1
	record.population += pop_delta
	record.tax_yield_per_day = int(_compute_city_tax_yield(record) * 0.6)
	record.accumulated_yield += record.tax_yield_per_day


func _update_village(record: PlaceRecord, _day: int) -> void:
	var pop_drift_rate: float = 0.0000015
	var pop_delta: int = int(record.population * pop_drift_rate)
	record.population += pop_delta
	record.tax_yield_per_day = int(record.population / 5000.0)
	record.accumulated_yield += record.tax_yield_per_day


func _update_mine(record: PlaceRecord, _day: int) -> void:
	if record.site_capacity <= 0:
		record.tax_yield_per_day = 0
		return
	var production: int = maxi(1, record.population / 50)
	if production > record.site_capacity:
		production = record.site_capacity
	record.site_capacity -= production
	record.tax_yield_per_day = production
	record.accumulated_yield += production


func _update_monastery(record: PlaceRecord, day: int) -> void:
	record.tax_yield_per_day = 0
	if day % 365 == 0:
		record.population += 1


func _update_fort(record: PlaceRecord, _day: int) -> void:
	record.tax_yield_per_day = -maxi(1, record.population / 100)
	record.accumulated_yield += record.tax_yield_per_day


func _update_trading_post(record: PlaceRecord, _day: int) -> void:
	var flow: int = int(record.population * (1.0 + record.infrastructure_level / 100.0) / 100.0)
	record.tax_yield_per_day = flow
	record.accumulated_yield += flow


func _update_lighthouse(record: PlaceRecord, _day: int) -> void:
	record.tax_yield_per_day = 0


func _update_named_site(record: PlaceRecord, _day: int) -> void:
	record.tax_yield_per_day = 0


func _era_yield_multiplier() -> float:
	match _time_keeper.current_era:
		EraValues.ANCIENT: return 1.0
		EraValues.CLASSICAL_COLLAPSE: return 1.2
		EraValues.MEDIEVAL: return 1.5
		EraValues.EARLY_MODERN: return 2.5
		EraValues.MODERN: return 4.0
		_: return 1.0


# --- Public API ---

func get_place_state(place_id: StringName) -> PlaceRecord:
	return _place_states.get(place_id, null)


func get_all_place_ids() -> Array:
	return _place_states.keys()


# --- Save/load ---

func snapshot_state() -> Dictionary:
	return {"place_states": _place_states.duplicate(true)}


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_place_states = state.get("place_states", {}).duplicate(true)
	for place_id: StringName in _world_registry.all_place_ids():
		if not _place_states.has(place_id):
			var registry_record: PlaceRecord = _world_registry.get_place(place_id)
			_place_states[place_id] = registry_record.duplicate(true)
	_logger.info(LogChannels.PLACE, "Place state applied from load", {"place_count": _place_states.size()})
