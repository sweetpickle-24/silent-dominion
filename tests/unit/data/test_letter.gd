extends GutTest


func test_field_access():
	var l := Letter.new()
	l.id = &"letter_1"
	l.immortal_id = &"player"
	l.subject = "Test subject"
	l.body = "Test body"
	l.day_received = 42
	l.content_category = &"scheme_status"
	assert_eq(l.id, &"letter_1")
	assert_eq(l.subject, "Test subject")
	assert_eq(l.day_received, 42)
	assert_false(l.is_read)


func test_mark_read():
	var l := Letter.new()
	l.id = &"letter_2"
	assert_false(l.is_read)
	l.mark_read(100)
	assert_true(l.is_read)
	assert_eq(l.read_day, 100)


func test_save_load_roundtrip():
	var l := Letter.new()
	l.id = &"roundtrip_letter"
	l.subject = "Roundtrip"
	l.body = "Body text"
	l.day_received = 50
	l.is_read = true
	l.read_day = 55
	l.tier = &"archive"
	var path: String = "user://test_letter_roundtrip.tres"
	ResourceSaver.save(l, path)
	var loaded: Letter = ResourceLoader.load(path) as Letter
	assert_not_null(loaded)
	assert_eq(loaded.id, &"roundtrip_letter")
	assert_eq(loaded.tier, &"archive")
	assert_true(loaded.is_read)
	DirAccess.remove_absolute(path)
