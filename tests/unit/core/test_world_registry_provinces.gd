extends GutTest

func test_provinces_loaded():
	var wr: Node = get_node("/root/WorldRegistry")
	assert_eq(wr.provinces.size(), 25, "Should have loaded 25 provinces")

func test_routes_loaded():
	var wr: Node = get_node("/root/WorldRegistry")
	assert_eq(wr.routes.size(), 18, "Should have loaded 18 routes")

func test_get_province():
	var wr: Node = get_node("/root/WorldRegistry")
	var attica: ProvinceRecord = wr.get_province(&"attica")
	assert_not_null(attica)
	assert_eq(attica.cultural_sphere, &"greek")
	assert_true(attica.is_adjacent_to(&"boeotia"))

func test_get_province_unknown():
	var wr: Node = get_node("/root/WorldRegistry")
	assert_null(wr.get_province(&"nonexistent"))

func test_places_in_province():
	var wr: Node = get_node("/root/WorldRegistry")
	var attica_places: Array = wr.places_in_province(&"attica")
	# Athens and Laurion are in attica
	assert_gte(attica_places.size(), 2)

func test_get_route():
	var wr: Node = get_node("/root/WorldRegistry")
	var route: RouteRecord = wr.get_route(&"royal_road")
	assert_not_null(route)
	assert_eq(route.kind, &"overland")
	assert_eq(route.tier, &"major")
