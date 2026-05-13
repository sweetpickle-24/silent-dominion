extends GutTest

func test_field_access():
	var c := CoverageAssignment.new()
	c.coverage_level = 50
	assert_eq(c.coverage_level, 50)

func test_detection_multiplier():
	var c := CoverageAssignment.new()
	c.coverage_level = 0
	assert_almost_eq(c.effective_detection_multiplier(), 0.0, 0.01)
	c.coverage_level = 50
	assert_almost_eq(c.effective_detection_multiplier(), 0.5, 0.01)
	c.coverage_level = 100
	assert_almost_eq(c.effective_detection_multiplier(), 1.0, 0.01)

func test_save_load_roundtrip():
	var c := CoverageAssignment.new()
	c.immortal_id = &"player"
	c.province_id = &"attica"
	c.coverage_level = 75
	var path := "user://test_coverage_roundtrip.tres"
	ResourceSaver.save(c, path)
	var loaded: CoverageAssignment = ResourceLoader.load(path) as CoverageAssignment
	assert_not_null(loaded)
	assert_eq(loaded.coverage_level, 75)
	DirAccess.remove_absolute(path)
