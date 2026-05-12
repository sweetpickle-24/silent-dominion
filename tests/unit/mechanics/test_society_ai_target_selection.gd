extends GutTest

var _ai: SocietyAI


func before_each():
	_ai = SocietyAI.new()
	_ai.name = "SocietyAI"
	add_child(_ai)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_ai) and _ai._tick_sub:
		eb.unsubscribe(_ai._tick_sub)
	if is_instance_valid(_ai):
		remove_child(_ai)
		_ai.free()


func test_select_random_scholarly_city_no_constraints():
	var result: StringName = _ai._select_random_scholarly_city({})
	assert_ne(result, &"", "Should find at least one scholarly city")
	# Verify it's actually a city with scholarly faction
	var wr: Node = get_node("/root/WorldRegistry")
	var place: PlaceRecord = wr.get_place(result)
	assert_not_null(place)
	assert_eq(place.place_type, &"city")
	assert_gt(place.factional_balance.get(&"scholarly", 0.0), 0.0)


func test_select_random_scholarly_city_min_population():
	var result: StringName = _ai._select_random_scholarly_city({"min_population": 50000})
	if result != &"":
		var wr: Node = get_node("/root/WorldRegistry")
		var place: PlaceRecord = wr.get_place(result)
		assert_gte(place.population, 50000)


func test_select_random_scholarly_city_cultural_sphere():
	var result: StringName = _ai._select_random_scholarly_city({"cultural_sphere": &"greek"})
	if result != &"":
		var wr: Node = get_node("/root/WorldRegistry")
		var place: PlaceRecord = wr.get_place(result)
		var prov: ProvinceRecord = wr.get_province(place.province)
		assert_eq(prov.cultural_sphere, &"greek")


func test_select_random_scholarly_city_impossible():
	var result: StringName = _ai._select_random_scholarly_city({"min_population": 99999999})
	assert_eq(result, &"", "Impossible constraints should return empty")


func test_select_random_place():
	var result: StringName = _ai._select_random_place({})
	assert_ne(result, &"", "Should find at least one place")
