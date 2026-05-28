extends GutTest

# Integration: prosperous stable place grows over years; place hit by scarcity shrinks.

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


func test_prosperous_place_grows():
	var wr: Node = get_node("/root/WorldRegistry")
	var athens: PlaceRecord = wr.get_place(&"athens")
	if athens == null:
		pending("No Athens")
		return
	var saved_pop: int = athens.population
	var state: PopulationState = _population.get_state(&"athens")
	state.food_surplus_factor = 1.5
	state.prosperity_factor = 1.3
	state.stability_factor = 1.0
	state.shock_factor = 1.0
	# Run several periods
	for i in range(5):
		_population._apply_population_delta(&"athens", i * 30)
	assert_gt(athens.population, saved_pop, "Prosperous place should grow")
	athens.population = saved_pop  # restore


func test_scarcity_shrinks_population():
	var wr: Node = get_node("/root/WorldRegistry")
	var corinth: PlaceRecord = wr.get_place(&"corinth")
	if corinth == null:
		pending("No Corinth")
		return
	var saved_pop: int = corinth.population
	var state: PopulationState = _population.get_state(&"corinth")
	state.food_surplus_factor = 0.3
	state.prosperity_factor = 0.5
	state.stability_factor = 0.5
	state.shock_factor = 1.0
	for i in range(5):
		_population._apply_population_delta(&"corinth", i * 30)
	assert_lt(corinth.population, saved_pop, "Scarcity should shrink population")
	corinth.population = saved_pop  # restore
