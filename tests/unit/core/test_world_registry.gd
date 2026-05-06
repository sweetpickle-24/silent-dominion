extends GutTest

# WorldRegistry is an autoload that loads on startup. These tests verify
# the data it loaded from the real fixture files in data/.


func test_place_types_loaded():
	var wr: Node = get_node("/root/WorldRegistry")
	assert_gt(wr.place_types.size(), 0, "Should have loaded place types")
	assert_eq(wr.place_types.size(), 11, "Should have loaded all 11 place types")


func test_places_loaded():
	var wr: Node = get_node("/root/WorldRegistry")
	assert_eq(wr.place_count(), 4, "Should have loaded 4 test fixtures")


func test_get_place_returns_record():
	var wr: Node = get_node("/root/WorldRegistry")
	var athens: PlaceRecord = wr.get_place(&"test_athens")
	assert_not_null(athens, "test_athens should exist")
	assert_eq(athens.name, "Athens")
	assert_eq(athens.place_type, &"city")
	assert_eq(athens.region, &"attica")
	assert_eq(athens.founded_day, -100000)


func test_get_place_unknown_returns_null():
	var wr: Node = get_node("/root/WorldRegistry")
	var result = wr.get_place(&"nonexistent_place")
	assert_null(result, "Unknown place id should return null")


func test_get_place_type_returns_definition():
	var wr: Node = get_node("/root/WorldRegistry")
	var city: PlaceTypeDefinition = wr.get_place_type(&"city")
	assert_not_null(city, "city type should exist")
	assert_eq(city.display_name, "City")
	assert_true(city.is_settlement)


func test_get_place_type_site():
	var wr: Node = get_node("/root/WorldRegistry")
	var mine: PlaceTypeDefinition = wr.get_place_type(&"mine")
	assert_not_null(mine)
	assert_eq(mine.display_name, "Mine")
	assert_false(mine.is_settlement)


func test_get_place_type_unknown_returns_null():
	var wr: Node = get_node("/root/WorldRegistry")
	var result = wr.get_place_type(&"nonexistent_type")
	assert_null(result, "Unknown place type id should return null")


func test_all_place_ids():
	var wr: Node = get_node("/root/WorldRegistry")
	var ids: Array = wr.all_place_ids()
	assert_eq(ids.size(), 4)
	assert_has(ids, &"test_athens")
	assert_has(ids, &"test_laurion")
	assert_has(ids, &"test_delphi")
	assert_has(ids, &"test_alexandria_library")


func test_place_type_cross_reference_valid():
	var wr: Node = get_node("/root/WorldRegistry")
	for id in wr.all_place_ids():
		var place: PlaceRecord = wr.get_place(id)
		var pt: PlaceTypeDefinition = wr.get_place_type(place.place_type)
		assert_not_null(pt, "Place '%s' should reference a valid place_type '%s'" % [id, place.place_type])
