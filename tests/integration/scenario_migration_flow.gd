extends GutTest

# Integration: low-stability place loses population to adjacent high-prosperity place.
# Migration is conserved.

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


func test_migration_conserved():
	# Set up: one unstable place, one prosperous
	var state_a: PopulationState = _population.get_state(&"athens")
	var state_b: PopulationState = _population.get_state(&"corinth")
	if state_a == null or state_b == null:
		pending("Need athens and corinth")
		return
	# Make all places neutral except these two
	for pid: StringName in _population._states.keys():
		var s: PopulationState = _population._states[pid]
		s.stability_factor = 1.0
		s.prosperity_factor = 1.0
	state_a.stability_factor = 0.3  # unstable → outflow
	state_b.prosperity_factor = 1.5  # prosperous → inflow
	_population._compute_migration()
	# Check conservation
	var total_migration: int = 0
	for pid: StringName in _population._states.keys():
		total_migration += _population._states[pid].net_migration_last_period
	assert_eq(total_migration, 0, "Migration must be conserved (sum to 0)")
	assert_lt(state_a.net_migration_last_period, 0, "Unstable place should lose population")
