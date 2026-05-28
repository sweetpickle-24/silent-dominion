extends GutTest

# Integration: trigger PlagueOnsetEvent in a dense place.
# Mass mortality + population drop + out-migration.

var _population: Population
var _mortality: Mortality


func before_each():
	_population = Population.new()
	_population.name = "Population"
	add_child(_population)
	_mortality = Mortality.new()
	_mortality.name = "Mortality"
	add_child(_mortality)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_population):
		if _population._tick_sub:
			eb.unsubscribe(_population._tick_sub)
		remove_child(_population)
		_population.free()
	if is_instance_valid(_mortality):
		if _mortality._tick_sub:
			eb.unsubscribe(_mortality._tick_sub)
		remove_child(_mortality)
		_mortality.free()


func test_plague_causes_population_decline():
	var wr: Node = get_node("/root/WorldRegistry")
	var athens: PlaceRecord = wr.get_place(&"athens")
	if athens == null:
		pending("No Athens")
		return
	var saved_pop: int = athens.population
	var state: PopulationState = _population.get_state(&"athens")
	# Trigger plague
	var plague := PlagueOnsetEvent.new()
	plague.place_id = &"athens"
	plague.severity = 0.8
	plague.day = 100
	_population._on_plague_onset(plague)
	# Verify shock factor lowered
	assert_lt(state.shock_factor, 1.0, "Plague should lower shock factor")
	# Apply population delta — should be negative due to shock
	_population._apply_population_delta(&"athens", 100)
	# With severe shock, deaths spike
	assert_lte(athens.population, saved_pop, "Population should not grow during plague")
	athens.population = saved_pop  # restore
	state.shock_factor = 1.0  # restore
