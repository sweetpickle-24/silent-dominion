extends GutTest

func test_field_access():
	var tr := TreatyRecord.new()
	tr.id = &"treaty_001"
	tr.signatory_a_immortal_id = &"player"
	tr.signatory_b_immortal_id = &"the_veil_founder"
	tr.signed_at_day = 1000
	tr.expires_at_day = 19250  # ~50 years
	tr.status = &"active"
	assert_eq(tr.signatory_a_immortal_id, &"player")
	assert_eq(tr.signed_at_day, 1000)
	assert_eq(tr.status, &"active")

func test_perpetual_treaty_has_no_expiry():
	var tr := TreatyRecord.new()
	tr.expires_at_day = -1
	assert_eq(tr.expires_at_day, -1)

func test_save_load_roundtrip():
	var tr := TreatyRecord.new()
	tr.id = &"roundtrip_treaty"
	tr.signatory_a_immortal_id = &"player"
	tr.signatory_b_immortal_id = &"the_veil_founder"
	tr.status = &"active"
	tr.signed_at_day = 200
	var path := "user://test_treaty_record_roundtrip.tres"
	ResourceSaver.save(tr, path)
	var loaded: TreatyRecord = ResourceLoader.load(path) as TreatyRecord
	assert_not_null(loaded)
	assert_eq(loaded.status, &"active")
	assert_eq(loaded.signed_at_day, 200)
	DirAccess.remove_absolute(path)
