extends GutTest


func test_field_access():
	var rec := PlaceRecord.new()
	rec.id = &"athens"
	rec.name = "Athens"
	rec.place_type = &"city"
	rec.province = &"attica"
	rec.founded_day = -100000
	assert_eq(rec.id, &"athens")
	assert_eq(rec.name, "Athens")
	assert_eq(rec.place_type, &"city")
	assert_eq(rec.province, &"attica")
	assert_eq(rec.founded_day, -100000)


func test_defaults():
	var rec := PlaceRecord.new()
	assert_eq(rec.id, &"")
	assert_eq(rec.name, "")
	assert_eq(rec.place_type, &"")
	assert_eq(rec.province, &"")
	assert_eq(rec.founded_day, 0)


func test_save_load_roundtrip():
	var rec := PlaceRecord.new()
	rec.id = &"test_roundtrip_place"
	rec.name = "Roundtrip City"
	rec.place_type = &"city"
	rec.province = &"test_region"
	rec.founded_day = -50000

	var path: String = "user://test_place_record_roundtrip.tres"
	ResourceSaver.save(rec, path)
	var loaded: PlaceRecord = ResourceLoader.load(path) as PlaceRecord

	assert_not_null(loaded, "Loaded resource should not be null")
	assert_eq(loaded.id, &"test_roundtrip_place")
	assert_eq(loaded.name, "Roundtrip City")
	assert_eq(loaded.place_type, &"city")
	assert_eq(loaded.province, &"test_region")
	assert_eq(loaded.founded_day, -50000)

	DirAccess.remove_absolute(path)
