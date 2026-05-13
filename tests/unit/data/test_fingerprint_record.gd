extends GutTest

func test_field_access():
	var f := FingerprintRecord.new()
	f.investigator_immortal_id = &"player"
	f.target_society_id = &"the_veil"
	f.current_level = 3
	assert_eq(f.current_level, 3)

func test_defaults():
	var f := FingerprintRecord.new()
	assert_eq(f.current_level, 0)
	assert_eq(f.first_detected_at_day, -1)

func test_save_load_roundtrip():
	var f := FingerprintRecord.new()
	f.investigator_immortal_id = &"player"
	f.target_society_id = &"the_veil"
	f.current_level = 2
	f.first_detected_at_day = 100
	var path := "user://test_fingerprint_roundtrip.tres"
	ResourceSaver.save(f, path)
	var loaded: FingerprintRecord = ResourceLoader.load(path) as FingerprintRecord
	assert_not_null(loaded)
	assert_eq(loaded.current_level, 2)
	DirAccess.remove_absolute(path)
