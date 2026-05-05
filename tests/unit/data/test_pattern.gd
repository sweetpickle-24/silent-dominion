extends GutTest


func _make_pattern(id: StringName = &"test_p", category: StringName = PatternCategories.BRIBE) -> Pattern:
	var p := Pattern.new()
	p.id = id
	p.name = "Test Pattern"
	p.category = category
	p.era = &"ancient"
	p.last_validated_day = 0
	return p


func test_field_access():
	var p := _make_pattern()
	assert_eq(p.id, &"test_p")
	assert_eq(p.name, "Test Pattern")
	assert_eq(p.category, PatternCategories.BRIBE)
	assert_eq(p.staleness_state, StalenessValues.FRESH)
	assert_eq(p.suspected_corruption_level, 0)
	assert_eq(p.success_count, 0)
	assert_eq(p.failure_count, 0)


func test_is_automation_eligible_fresh():
	var p := _make_pattern()
	assert_true(p.is_automation_eligible())


func test_is_automation_eligible_stale():
	var p := _make_pattern()
	p.staleness_state = StalenessValues.STALE
	assert_false(p.is_automation_eligible())


func test_is_automation_eligible_high_corruption():
	var p := _make_pattern()
	p.suspected_corruption_level = 80
	assert_false(p.is_automation_eligible())


func test_is_automation_eligible_aging_moderate_corruption():
	var p := _make_pattern()
	p.staleness_state = StalenessValues.AGING
	p.suspected_corruption_level = 79
	assert_true(p.is_automation_eligible())


func test_mark_validated():
	var p := _make_pattern()
	p.staleness_state = StalenessValues.AGING
	p.mark_validated(1000)
	assert_eq(p.last_validated_day, 1000)
	assert_eq(p.staleness_state, StalenessValues.FRESH)
	assert_eq(p.success_count, 1)


func test_mark_misfired():
	var p := _make_pattern()
	p.mark_misfired(500)
	assert_eq(p.last_misfired_day, 500)
	assert_eq(p.failure_count, 1)


func test_total_applications():
	var p := _make_pattern()
	p.success_count = 3
	p.failure_count = 2
	assert_eq(p.total_applications(), 5)


func test_empirical_success_rate_no_applications():
	var p := _make_pattern()
	assert_almost_eq(p.empirical_success_rate(), 0.5, 0.001)


func test_empirical_success_rate_with_data():
	var p := _make_pattern()
	p.success_count = 3
	p.failure_count = 1
	assert_almost_eq(p.empirical_success_rate(), 0.75, 0.001)


func test_save_load_roundtrip():
	var p := _make_pattern()
	p.success_count = 5
	p.failure_count = 2
	p.staleness_state = StalenessValues.AGING
	p.suspected_corruption_level = 30
	p.last_validated_day = 1000
	p.last_misfired_day = 900
	p.region_scope = &"attica"

	var path: String = "user://test_pattern_roundtrip.tres"
	ResourceSaver.save(p, path)
	var loaded: Pattern = ResourceLoader.load(path) as Pattern

	assert_not_null(loaded)
	assert_eq(loaded.id, &"test_p")
	assert_eq(loaded.success_count, 5)
	assert_eq(loaded.failure_count, 2)
	assert_eq(loaded.staleness_state, StalenessValues.AGING)
	assert_eq(loaded.suspected_corruption_level, 30)
	assert_eq(loaded.last_validated_day, 1000)
	assert_eq(loaded.last_misfired_day, 900)
	assert_eq(loaded.region_scope, &"attica")

	DirAccess.remove_absolute(path)
