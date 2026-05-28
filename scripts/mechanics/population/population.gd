class_name Population
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _world_registry: Node

var _states: Dictionary = {}           # StringName place_id -> PopulationState
var _tick_sub
var _day_accumulator: int = 0

# Period cadence: apply population changes every N days
const UPDATE_PERIOD_DAYS: int = 30

# Migration constants (placeholder, flagged for calibration)
const MIGRATION_RATE: float = 0.001     # fraction of population that migrates per period
const MIGRATION_STABILITY_THRESHOLD: float = 0.7  # below this, outflow starts
const MIGRATION_PROSPERITY_ATTRACTION: float = 1.5  # multiplier for inflow to prosperous places

# Growth constants
const BASE_GROWTH_RATE: float = 0.004   # ~0.4% per period natural growth at equilibrium
const CITY_SLOT_THRESHOLD: int = 50000


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_world_registry = get_node("/root/WorldRegistry")
	_initialize_states()
	_tick_sub = _event_bus.subscribe(
		preload("res://scripts/data/events/game_day_ticked_event.gd"),
		Callable(self, "_on_game_day_ticked"),
		140, &"", EndOfTickPhases.WORLD_SHARED,
	)
	# Subscribe to famine/plague for shock_factor
	_event_bus.subscribe(
		preload("res://scripts/data/events/famine_onset_event.gd"),
		Callable(self, "_on_famine_onset"),
		140, &"", EndOfTickPhases.WORLD_SHARED,
	)
	_event_bus.subscribe(
		preload("res://scripts/data/events/plague_onset_event.gd"),
		Callable(self, "_on_plague_onset"),
		140, &"", EndOfTickPhases.WORLD_SHARED,
	)
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"population_state",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)
	_logger.info(LogChannels.POPULATION, "Population mechanic ready", {"places": _states.size()})


func _initialize_states() -> void:
	for place_id: StringName in _world_registry.all_place_ids():
		var place: PlaceRecord = _world_registry.get_place(place_id)
		if place == null:
			continue
		var state := PopulationState.new()
		state.place_id = place_id
		state.total = place.population
		_states[place_id] = state


# --- Per-tick ---

func _on_game_day_ticked(_event: GameDayTickedEvent) -> void:
	_day_accumulator += 1
	if _day_accumulator >= UPDATE_PERIOD_DAYS:
		_day_accumulator = 0
		_update_all_populations()


func _update_all_populations() -> void:
	var day: int = _time_keeper.current_day
	# 1. Read condition inputs for each place
	_read_condition_inputs()
	# 2. Compute migration (conserved)
	_compute_migration()
	# 3. Apply population deltas
	for place_id: StringName in _states.keys():
		_apply_population_delta(place_id, day)
	# 4. Update weight accumulators
	_update_weight_accumulators()


func _read_condition_inputs() -> void:
	var kingdom_node: Node = get_node_or_null("../Kingdom")
	for place_id: StringName in _states.keys():
		var state: PopulationState = _states[place_id]
		var place: PlaceRecord = _world_registry.get_place(place_id)
		if place == null:
			continue
		# Prosperity from mercantile/civic faction balance
		var merc: float = place.factional_balance.get(&"mercantile", 0.0)
		var civic: float = place.factional_balance.get(&"civic", 0.0)
		state.prosperity_factor = 0.8 + (merc + civic) * 0.4
		# Stability from kingdom unrest (if place is in a kingdom)
		if kingdom_node != null:
			var kid: StringName = kingdom_node.kingdom_of_place(place_id)
			if kid != &"":
				var k: KingdomRecord = kingdom_node.get_kingdom(kid)
				if k != null:
					state.stability_factor = 1.0 - (k.unrest / 100.0) * 0.5
		# Food surplus: placeholder based on place type
		if place.place_type in [&"city", &"town", &"village"]:
			state.food_surplus_factor = 1.0 + place.infrastructure_level * 0.002
		else:
			state.food_surplus_factor = 0.9  # non-settlement sites have lower surplus


func _compute_migration() -> void:
	# Simplified: places below stability threshold lose population,
	# adjacent/connected places above threshold gain proportionally.
	var outflows: Dictionary = {}   # place_id -> int (population leaving)
	var inflow_candidates: Dictionary = {}  # place_id -> float (attraction weight)
	var total_attraction: float = 0.0
	for place_id: StringName in _states.keys():
		var state: PopulationState = _states[place_id]
		if state.stability_factor < MIGRATION_STABILITY_THRESHOLD and state.total > 100:
			var out: int = int(state.total * MIGRATION_RATE * (1.0 - state.stability_factor))
			outflows[place_id] = out
		if state.prosperity_factor > 1.0:
			var attraction: float = state.prosperity_factor * MIGRATION_PROSPERITY_ATTRACTION
			inflow_candidates[place_id] = attraction
			total_attraction += attraction
	# Distribute outflows to inflow candidates (proportional to attraction)
	var total_out: int = 0
	for out_amount: int in outflows.values():
		total_out += out_amount
	if total_out > 0 and total_attraction > 0.0:
		for place_id: StringName in inflow_candidates.keys():
			var share: float = inflow_candidates[place_id] / total_attraction
			_states[place_id].net_migration_last_period = int(total_out * share)
		for place_id: StringName in outflows.keys():
			_states[place_id].net_migration_last_period = -outflows[place_id]
	else:
		for place_id: StringName in _states.keys():
			_states[place_id].net_migration_last_period = 0


func _apply_population_delta(place_id: StringName, day: int) -> void:
	var state: PopulationState = _states[place_id]
	var place: PlaceRecord = _world_registry.get_place(place_id)
	if place == null:
		return
	var old_pop: int = place.population
	var delta: int = state.period_delta()
	place.population = maxi(place.population + delta, 0)
	state.total = place.population
	# Update city-slot readiness
	state.city_slot_ready = place.population >= CITY_SLOT_THRESHOLD
	# Fire event
	if delta != 0:
		var event := PopulationDeltaAppliedEvent.new()
		event.place_id = place_id
		event.old_population = old_pop
		event.new_population = place.population
		event.delta = delta
		event.day = day
		_event_bus.dispatch(event)


func _update_weight_accumulators() -> void:
	for place_id: StringName in _states.keys():
		var state: PopulationState = _states[place_id]
		# Condition→weight shifts per §8.11
		# Destabilisation: low stability → ambition+, loyalty-
		if state.stability_factor < 0.6:
			_accumulate_weight(state, &"ambition", 0.5)
			_accumulate_weight(state, &"loyalty", -0.3)
			_accumulate_weight(state, &"paranoia", 0.4)
		# Merchant elevation: high prosperity → greed+, intellect+
		if state.prosperity_factor > 1.2:
			_accumulate_weight(state, &"greed", 0.3)
			_accumulate_weight(state, &"intellect", 0.2)
		# Sustained peace: high stability → loyalty+, resilience+
		if state.stability_factor > 0.9:
			_accumulate_weight(state, &"loyalty", 0.2)
			_accumulate_weight(state, &"resilience", 0.1)
		# Religion seeding: (placeholder — religion mechanic at 11.14c)
		# Philosophy investment: scholarly faction → intellect+, curiosity+
		var place: PlaceRecord = _world_registry.get_place(place_id)
		if place != null:
			var scholarly: float = place.factional_balance.get(&"scholarly", 0.0)
			if scholarly > 0.2:
				_accumulate_weight(state, &"intellect", 0.3)
				_accumulate_weight(state, &"curiosity", 0.2)
		# Repeated betrayals: (placeholder — tracked at 11.17)


func _accumulate_weight(state: PopulationState, trait_id: StringName, delta: float) -> void:
	var current: float = state.weight_accumulators.get(trait_id, 0.0)
	state.weight_accumulators[trait_id] = current + delta


# --- Shock handlers ---

func _on_famine_onset(event: FamineOnsetEvent) -> void:
	var state: PopulationState = _states.get(event.place_id, null)
	if state != null:
		state.shock_factor = maxf(1.0 - event.severity, 0.1)
		state.food_surplus_factor = maxf(state.food_surplus_factor - event.severity * 0.5, 0.1)
		_logger.info(LogChannels.POPULATION, "Famine onset", {
			"place": event.place_id, "severity": event.severity,
		})


func _on_plague_onset(event: PlagueOnsetEvent) -> void:
	var state: PopulationState = _states.get(event.place_id, null)
	if state != null:
		state.shock_factor = maxf(1.0 - event.severity, 0.1)
		_logger.info(LogChannels.POPULATION, "Plague onset", {
			"place": event.place_id, "severity": event.severity,
		})


# --- Public API ---

func population_of(place_id: StringName) -> int:
	var state: PopulationState = _states.get(place_id, null)
	return state.total if state != null else 0


func levy_capacity(place_id: StringName) -> int:
	return int(population_of(place_id) * 0.05)


func generation_rate(place_id: StringName) -> float:
	# Characters generated per generation period, scaled by population
	var pop: int = population_of(place_id)
	if pop < 1000:
		return 0.0
	return maxf(pop / 20000.0, 0.1)  # ~1 per 20k pop, minimum 0.1


func migration_pressure(place_id: StringName) -> float:
	var state: PopulationState = _states.get(place_id, null)
	if state == null:
		return 0.0
	return 1.0 - state.stability_factor


func get_weight_accumulators(place_id: StringName) -> Dictionary:
	var state: PopulationState = _states.get(place_id, null)
	if state == null:
		return {}
	return state.weight_accumulators


func get_state(place_id: StringName) -> PopulationState:
	return _states.get(place_id, null)


# --- Save/load ---

func snapshot_state() -> Dictionary:
	return {
		"states": _states.duplicate(true),
		"day_accumulator": _day_accumulator,
	}


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_states = state.get("states", {}).duplicate(true)
	_day_accumulator = state.get("day_accumulator", 0)
	_logger.info(LogChannels.POPULATION, "Population state applied from load")
