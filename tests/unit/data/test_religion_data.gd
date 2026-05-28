extends GutTest

# Validate authored religion data integrity.

var _religion: ReligionIdeology


func before_each():
	_religion = ReligionIdeology.new()
	_religion.name = "ReligionIdeology"
	add_child(_religion)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_religion):
		if _religion._tick_sub:
			eb.unsubscribe(_religion._tick_sub)
		remove_child(_religion)
		_religion.free()


func test_religions_loaded():
	assert_eq(_religion.all_religion_ids().size(), 6, "Should load 6 starting religions/ideologies")


func test_every_religion_has_valid_attributes():
	for rid: StringName in _religion.all_religion_ids():
		var r: ReligionRecord = _religion.religion_record(rid)
		assert_not_null(r)
		assert_ne(r.display_name, "", "Religion %s should have a display name" % rid)
		assert_gte(r.doctrinal_rigidity, 0)
		assert_lte(r.doctrinal_rigidity, 100)
		assert_gte(r.institutional_strength, 0)
		assert_lte(r.institutional_strength, 100)
		assert_true(r.lifecycle_phase in [&"emergence", &"consolidation", &"dominance", &"fracture", &"decline", &"extinct"])


func test_starting_presence_initialized():
	# At least some places should have religion presence
	var places_with_religion: int = 0
	var wr: Node = get_node("/root/WorldRegistry")
	for pid: StringName in wr.all_place_ids():
		if not _religion.religions_in_place(pid).is_empty():
			places_with_religion += 1
	assert_gt(places_with_religion, 0, "Some places should have religion at start")


func test_every_major_place_has_religion():
	# Major cities (Athens, Babylon, Carthage, etc.) should all have a religion
	var major_places: Array = [&"athens", &"babylon", &"carthage", &"rome", &"memphis", &"persepolis"]
	for pid: StringName in major_places:
		var religions: Array = _religion.religions_in_place(pid)
		assert_gt(religions.size(), 0, "Major place %s should have at least one religion" % pid)


func test_dominant_religion_matches_cultural_sphere():
	# Athens should have Greek Olympian as dominant
	assert_eq(_religion.dominant_religion(&"athens"), &"greek_olympian")
	# Persepolis should have Zoroastrianism
	assert_eq(_religion.dominant_religion(&"persepolis"), &"zoroastrianism")
	# Memphis should have Egyptian polytheism
	assert_eq(_religion.dominant_religion(&"memphis"), &"egyptian_polytheism")
	# Rome should have Roman religio
	assert_eq(_religion.dominant_religion(&"rome"), &"roman_religio")
