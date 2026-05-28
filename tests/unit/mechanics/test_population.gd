extends GutTest

var _population: Population


func before_each():
	_population = Population.new()
	_population.name = "Population"
	add_child(_population)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_population):
		if _population._tick_sub:
			eb.unsubscribe(_population._tick_sub)
		remove_child(_population)
		_population.free()


func test_population_initialized_from_places():
	assert_gt(_population._states.size(), 0, "Should initialize states for all places")
	var athens_pop: int = _population.population_of(&"athens")
	assert_gt(athens_pop, 0, "Athens should have nonzero population")


func test_surplus_grows_population():
	var state: PopulationState = _population.get_state(&"athens")
	if state == null:
		pending("No athens state")
		return
	state.food_surplus_factor = 1.5  # surplus
	state.prosperity_factor = 1.2
	state.stability_factor = 1.0
	state.shock_factor = 1.0
	var delta: int = state.period_delta()
	assert_gt(delta, 0, "Surplus conditions should grow population")


func test_scarcity_shrinks_population():
	var state: PopulationState = _population.get_state(&"athens")
	if state == null:
		pending("No athens state")
		return
	state.food_surplus_factor = 0.3  # severe scarcity
	state.prosperity_factor = 0.5
	state.stability_factor = 0.5
	state.shock_factor = 1.0
	var delta: int = state.period_delta()
	assert_lt(delta, 0, "Scarcity should shrink population")


func test_migration_conserved():
	# Set up: one place with low stability (outflow), one with high prosperity (inflow)
	var state_a: PopulationState = _population.get_state(&"athens")
	var state_b: PopulationState = _population.get_state(&"corinth")
	if state_a == null or state_b == null:
		pending("Need athens and corinth")
		return
	state_a.stability_factor = 0.3  # very unstable → outflow
	state_b.prosperity_factor = 1.5  # prosperous → inflow
	# Reset all other places to neutral to isolate migration
	for pid: StringName in _population._states.keys():
		if pid != &"athens" and pid != &"corinth":
			_population._states[pid].stability_factor = 1.0
			_population._states[pid].prosperity_factor = 1.0
	_population._compute_migration()
	# Athens should have negative migration, someone should have positive
	assert_lt(state_a.net_migration_last_period, 0, "Unstable place should have outflow")
	# Total migration should be conserved (sum to ~0)
	var total_migration: int = 0
	for pid: StringName in _population._states.keys():
		total_migration += _population._states[pid].net_migration_last_period
	assert_eq(total_migration, 0, "Migration must be conserved")


func test_prosperity_stability_factors():
	var state: PopulationState = _population.get_state(&"athens")
	if state == null:
		pending("No athens state")
		return
	_population._read_condition_inputs()
	# Factors should be in reasonable range
	assert_gt(state.prosperity_factor, 0.0)
	assert_lte(state.prosperity_factor, 2.0)
	assert_gt(state.stability_factor, 0.0)
	assert_lte(state.stability_factor, 1.5)


func test_levy_capacity_scales_with_population():
	var levy: int = _population.levy_capacity(&"athens")
	var pop: int = _population.population_of(&"athens")
	assert_eq(levy, int(pop * 0.05), "Levy should be 5% of population")


func test_weight_accumulators_update():
	var state: PopulationState = _population.get_state(&"athens")
	if state == null:
		pending("No athens state")
		return
	state.stability_factor = 0.3  # very unstable → should accumulate ambition+
	_population._update_weight_accumulators()
	var ambition_weight: float = state.weight_accumulators.get(&"ambition", 0.0)
	assert_gt(ambition_weight, 0.0, "Destabilisation should raise ambition weight")


func test_city_slot_ready_at_threshold():
	var state: PopulationState = _population.get_state(&"athens")
	if state == null:
		pending("No athens state")
		return
	var wr: Node = get_node("/root/WorldRegistry")
	var place: PlaceRecord = wr.get_place(&"athens")
	var saved_pop: int = place.population
	# Above threshold
	place.population = 60000
	state.total = 60000
	_population._apply_population_delta(&"athens", 100)
	assert_true(state.city_slot_ready, "Above 50k should be city-slot-ready")
	# Below threshold
	place.population = 30000
	state.total = 30000
	_population._apply_population_delta(&"athens", 100)
	assert_false(state.city_slot_ready, "Below 50k should not be city-slot-ready")
	place.population = saved_pop  # restore


func test_population_delta_event_fires():
	var events: Array = []
	var eb: Node = get_node("/root/EventBus")
	var sub = eb.subscribe(
		preload("res://scripts/data/events/population_delta_applied_event.gd"),
		func(e): events.append(e),
		50,
	)
	var state: PopulationState = _population.get_state(&"athens")
	if state == null:
		pending("No athens state")
		eb.unsubscribe(sub)
		return
	state.food_surplus_factor = 2.0  # ensure positive delta
	_population._apply_population_delta(&"athens", 100)
	if state.period_delta() != 0:
		assert_gt(events.size(), 0, "Should fire PopulationDeltaAppliedEvent")
	eb.unsubscribe(sub)


func test_famine_lowers_shock_factor():
	var state: PopulationState = _population.get_state(&"athens")
	if state == null:
		pending("No athens state")
		return
	var event := FamineOnsetEvent.new()
	event.place_id = &"athens"
	event.severity = 0.7
	_population._on_famine_onset(event)
	assert_lt(state.shock_factor, 1.0, "Famine should lower shock factor")


func test_plague_lowers_shock_factor():
	var state: PopulationState = _population.get_state(&"athens")
	if state == null:
		pending("No athens state")
		return
	var event := PlagueOnsetEvent.new()
	event.place_id = &"athens"
	event.severity = 0.8
	_population._on_plague_onset(event)
	assert_lt(state.shock_factor, 1.0, "Plague should lower shock factor")


func test_generation_rate_scales_with_population():
	var rate_athens: float = _population.generation_rate(&"athens")
	var rate_delphi: float = _population.generation_rate(&"delphi")
	assert_gt(rate_athens, rate_delphi, "Larger city should have higher generation rate")


func test_save_load_roundtrip():
	_population._day_accumulator = 15
	var snapshot: Dictionary = _population.snapshot_state()
	assert_true(snapshot.has("states"))
	_population._day_accumulator = 0
	_population.apply_state(snapshot)
	assert_eq(_population._day_accumulator, 15)
