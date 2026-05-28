extends GutTest

var _languages: Languages


func before_each():
	_languages = Languages.new()
	_languages.name = "Languages"
	add_child(_languages)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_languages):
		if _languages._tick_sub:
			eb.unsubscribe(_languages._tick_sub)
		remove_child(_languages)
		_languages.free()


func test_languages_loaded():
	assert_eq(_languages.all_language_ids().size(), 8, "Should load 8 starting languages")


func test_every_language_has_valid_attributes():
	for lid: StringName in _languages.all_language_ids():
		var l: LanguageRecord = _languages.language_record(lid)
		assert_not_null(l)
		assert_ne(l.display_name, "")
		assert_gte(l.prestige, 0)
		assert_lte(l.prestige, 100)
		assert_true(l.vitality in [&"emerging", &"growing", &"stable", &"declining", &"dead"])


func test_composition_initialized():
	var wr: Node = get_node("/root/WorldRegistry")
	var regions_with_comp: int = 0
	for pid: StringName in wr.all_province_ids():
		var comp: Dictionary = _languages.get_composition(pid)
		if not comp.is_empty():
			regions_with_comp += 1
	assert_gt(regions_with_comp, 0, "Some regions should have language composition")


func test_greek_dominant_in_attica():
	assert_eq(_languages.dominant_language(&"attica"), &"greek")


func test_latin_dominant_in_latium():
	assert_eq(_languages.dominant_language(&"latium"), &"latin")


func test_composition_sums_near_100():
	var wr: Node = get_node("/root/WorldRegistry")
	for pid: StringName in wr.all_province_ids():
		var comp: Dictionary = _languages.get_composition(pid)
		if comp.is_empty():
			continue
		var total: float = 0.0
		for share: float in comp.values():
			total += share
		assert_almost_eq(total, 100.0, 5.0, "Region %s composition should sum to ~100" % pid)
