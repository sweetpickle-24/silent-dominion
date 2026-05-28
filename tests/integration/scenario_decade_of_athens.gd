extends GutTest
## Integration scenario: a decade of simulation verifies Place update logic
## produces sensible state drift across the Mediterranean place set.

var _place: Place


func before_each():
	# Use the Place instance that _ready already created from WorldRegistry
	_place = Place.new()
	_place.name = "Place"
	add_child(_place)


func after_each():
	if is_instance_valid(_place):
		remove_child(_place)
		_place.free()


func test_decade_of_athens():
	# Reset populations — prior tests may have mutated WorldRegistry resources
	var wr: Node = get_node("/root/WorldRegistry")
	for pid: StringName in wr.all_place_ids():
		var p: PlaceRecord = wr.get_place(pid)
		if p != null:
			p.accumulated_yield = 0
	wr.get_place(&"athens").population = 100000
	wr.get_place(&"rome").population = 25000
	wr.get_place(&"delphi").population = 800
	_place._initialize_runtime_state_from_registry()
	# Tick 3650 days (10 years)
	for day in range(1, 3651):
		_place.update_per_day(day)

	var athens: PlaceRecord = _place.get_place_state(&"athens")
	assert_not_null(athens)
	# Population drift removed from Place at 11.14b — Population mechanic owns growth.
	# Place keeps population stable; yields still accumulate from existing population.
	assert_eq(athens.population, 100000, "Athens population stable (Population mechanic owns growth)")
	assert_gt(athens.accumulated_yield, 0, "Athens should have accumulated tax yield")

	# Laurion mine should have produced and depleted
	var laurion: PlaceRecord = _place.get_place_state(&"laurion")
	assert_not_null(laurion)
	assert_lt(laurion.site_capacity, 5000000, "Laurion reserves should have depleted")
	assert_gt(laurion.accumulated_yield, 0, "Laurion should have produced silver")

	# Delphi (monastery) should have 0 accumulated yield
	var delphi: PlaceRecord = _place.get_place_state(&"delphi")
	assert_not_null(delphi)
	assert_eq(delphi.accumulated_yield, 0, "Delphi (monastery) should have 0 yield")
	assert_eq(delphi.population, 800, "Delphi population stable")

	# Rome (town) — population stable, yield accumulates
	var rome: PlaceRecord = _place.get_place_state(&"rome")
	assert_not_null(rome)
	assert_eq(rome.population, 25000, "Rome population stable")
	assert_gt(rome.accumulated_yield, 0, "Rome should have accumulated yield")

	# Babylon (largest city) should have largest yield
	var babylon: PlaceRecord = _place.get_place_state(&"babylon")
	assert_gt(babylon.accumulated_yield, athens.accumulated_yield, "Babylon should out-produce Athens")

	# No place should have negative population
	for pid: StringName in _place.get_all_place_ids():
		var r: PlaceRecord = _place.get_place_state(pid)
		assert_true(r.population >= 0, "Place %s should have non-negative population" % pid)
