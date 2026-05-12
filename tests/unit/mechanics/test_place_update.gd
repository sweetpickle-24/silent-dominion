extends GutTest

var _place: Place


func _make_record(type: StringName, pop: int = 1000, infra: int = 50, capacity: int = -1) -> PlaceRecord:
	var r := PlaceRecord.new()
	r.id = &"test_place"
	r.name = "Test Place"
	r.place_type = type
	r.province = &"test_region"
	r.population = pop
	r.infrastructure_level = infra
	r.site_capacity = capacity
	return r


func before_each():
	_place = Place.new()
	_place.name = "Place"
	add_child(_place)


func after_each():
	if is_instance_valid(_place):
		var eb: Node = get_node("/root/EventBus")
		# Place subscribes but doesn't expose the handle; just free it
		remove_child(_place)
		_place.free()


func test_city_population_grows():
	var r := _make_record(PlaceTypeValues.CITY, 10000, 50)
	var start_pop: int = r.population
	for day in range(365):
		_place._update_city(r, day)
	assert_gt(r.population, start_pop, "City population should grow over a year")


func test_city_tax_yield_positive():
	var r := _make_record(PlaceTypeValues.CITY, 10000, 50)
	_place._update_city(r, 1)
	assert_gt(r.tax_yield_per_day, 0, "City should produce tax yield")
	assert_gt(r.accumulated_yield, 0)


func test_city_infrastructure_affects_yield():
	var low := _make_record(PlaceTypeValues.CITY, 10000, 0)
	var high := _make_record(PlaceTypeValues.CITY, 10000, 100)
	_place._update_city(low, 1)
	_place._update_city(high, 1)
	assert_gt(high.tax_yield_per_day, low.tax_yield_per_day, "Higher infra should produce more yield")


func test_mine_produces_and_depletes():
	var r := _make_record(PlaceTypeValues.MINE, 100, 30, 1000)
	var start_cap: int = r.site_capacity
	_place._update_mine(r, 1)
	assert_gt(r.tax_yield_per_day, 0, "Mine should produce yield")
	assert_lt(r.site_capacity, start_cap, "Mine reserves should deplete")


func test_mine_depleted_stops_producing():
	var r := _make_record(PlaceTypeValues.MINE, 100, 30, 0)
	_place._update_mine(r, 1)
	assert_eq(r.tax_yield_per_day, 0, "Depleted mine should not produce")


func test_monastery_no_yield():
	var r := _make_record(PlaceTypeValues.MONASTERY, 50, 40)
	_place._update_monastery(r, 1)
	assert_eq(r.tax_yield_per_day, 0, "Monastery should not produce tax yield")


func test_fort_negative_yield():
	var r := _make_record(PlaceTypeValues.FORT, 500, 30)
	_place._update_fort(r, 1)
	assert_lt(r.tax_yield_per_day, 0, "Fort should consume upkeep (negative yield)")


func test_trading_post_scales_with_infra():
	var low := _make_record(PlaceTypeValues.TRADING_POST, 1000, 0)
	var high := _make_record(PlaceTypeValues.TRADING_POST, 1000, 100)
	_place._update_trading_post(low, 1)
	_place._update_trading_post(high, 1)
	assert_gt(high.tax_yield_per_day, low.tax_yield_per_day, "Higher infra trading post should produce more")


func test_all_places_evolve_over_100_days():
	# Use the real loaded place states from the Place mechanic
	for day in range(1, 101):
		_place.update_per_day(day)
	for pid: StringName in _place._place_states:
		var r: PlaceRecord = _place._place_states[pid]
		# Cities/towns should have accumulated yield
		if r.place_type == PlaceTypeValues.CITY or r.place_type == PlaceTypeValues.TOWN:
			assert_gt(r.accumulated_yield, 0, "Place %s should have accumulated yield" % pid)
		# Monasteries/lighthouses/named_sites should have 0 yield
		if r.place_type == PlaceTypeValues.LIGHTHOUSE or r.place_type == PlaceTypeValues.NAMED_SITE:
			assert_eq(r.accumulated_yield, 0, "Place %s should have 0 yield" % pid)
		# No population should be negative
		assert_true(r.population >= 0, "Place %s population should not be negative" % pid)


func test_save_load_roundtrip():
	# Tick 10 days to generate some state drift
	for day in range(1, 11):
		_place.update_per_day(day)
	var athens_pop_before: int = _place.get_place_state(&"athens").population
	assert_gt(athens_pop_before, 100000, "Athens should have grown slightly")

	var state: Dictionary = _place.snapshot_state()
	# Reset by re-initializing from registry
	_place._initialize_runtime_state_from_registry()
	assert_eq(_place.get_place_state(&"athens").population, 100000, "Should be reset to registry value")

	_place.apply_state(state)
	assert_eq(_place.get_place_state(&"athens").population, athens_pop_before, "Should restore saved state")
