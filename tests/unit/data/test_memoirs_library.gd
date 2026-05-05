extends GutTest


func _make_pattern(id: StringName, category: StringName = PatternCategories.BRIBE) -> Pattern:
	var p := Pattern.new()
	p.id = id
	p.name = "Pattern %s" % id
	p.category = category
	p.era = &"ancient"
	return p


func test_add_and_get_pattern():
	var lib := MemoirsLibrary.new()
	lib.immortal_id = &"player"
	var p := _make_pattern(&"p1")
	lib.patterns.append(p)
	assert_eq(lib.get_pattern(&"p1"), p)
	assert_null(lib.get_pattern(&"nonexistent"))


func test_patterns_by_category():
	var lib := MemoirsLibrary.new()
	lib.patterns.append(_make_pattern(&"p1", PatternCategories.BRIBE))
	lib.patterns.append(_make_pattern(&"p2", PatternCategories.CULTIVATE))
	lib.patterns.append(_make_pattern(&"p3", PatternCategories.BRIBE))
	var bribes: Array[Pattern] = lib.patterns_by_category(PatternCategories.BRIBE)
	assert_eq(bribes.size(), 2)
	var cultivates: Array[Pattern] = lib.patterns_by_category(PatternCategories.CULTIVATE)
	assert_eq(cultivates.size(), 1)
	var removes: Array[Pattern] = lib.patterns_by_category(PatternCategories.REMOVE)
	assert_eq(removes.size(), 0)


func test_save_load_roundtrip():
	var lib := MemoirsLibrary.new()
	lib.immortal_id = &"test_immortal"
	lib.patterns.append(_make_pattern(&"p1", PatternCategories.BRIBE))
	lib.patterns.append(_make_pattern(&"p2", PatternCategories.CULTIVATE))
	lib.patterns.append(_make_pattern(&"p3", PatternCategories.REMOVE))

	var path: String = "user://test_memoirs_library_roundtrip.tres"
	ResourceSaver.save(lib, path)
	var loaded: MemoirsLibrary = ResourceLoader.load(path) as MemoirsLibrary

	assert_not_null(loaded)
	assert_eq(loaded.immortal_id, &"test_immortal")
	assert_eq(loaded.patterns.size(), 3)
	assert_eq(loaded.get_pattern(&"p1").category, PatternCategories.BRIBE)
	assert_eq(loaded.get_pattern(&"p3").category, PatternCategories.REMOVE)

	DirAccess.remove_absolute(path)
