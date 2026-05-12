extends GutTest

func test_regions_adjacent_true():
	var helpers: Node = get_node("/root/Helpers")
	assert_true(helpers.regions_adjacent(&"attica", &"boeotia"), "Attica and Boeotia should be adjacent")

func test_regions_adjacent_false():
	var helpers: Node = get_node("/root/Helpers")
	assert_false(helpers.regions_adjacent(&"attica", &"persis"), "Attica and Persis should not be adjacent")

func test_regions_adjacent_unknown():
	var helpers: Node = get_node("/root/Helpers")
	assert_false(helpers.regions_adjacent(&"attica", &"nonexistent"), "Unknown province returns false")

func test_regions_same_cultural_sphere_true():
	var helpers: Node = get_node("/root/Helpers")
	assert_true(helpers.regions_same_cultural_sphere(&"attica", &"boeotia"), "Both Greek sphere")

func test_regions_same_cultural_sphere_false():
	var helpers: Node = get_node("/root/Helpers")
	assert_false(helpers.regions_same_cultural_sphere(&"attica", &"persis"), "Greek vs Persian sphere")
