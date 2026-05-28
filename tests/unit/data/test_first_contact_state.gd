extends GutTest

func test_field_access():
	var fc := FirstContactState.new()
	fc.immortal_a_id = &"player"
	fc.immortal_b_id = &"the_veil_founder"
	fc.stage = &"contact_initiated"
	fc.contact_initiator_id = &"the_veil_founder"
	fc.opening_gesture_kind = &"shared_intelligence"
	assert_eq(fc.stage, &"contact_initiated")
	assert_eq(fc.opening_gesture_kind, &"shared_intelligence")

func test_defaults():
	var fc := FirstContactState.new()
	assert_eq(fc.stage, &"unaware")
	assert_eq(fc.first_aware_day, -1)
	assert_eq(fc.contact_initiated_day, -1)

func test_save_load_roundtrip():
	var fc := FirstContactState.new()
	fc.immortal_a_id = &"player"
	fc.immortal_b_id = &"the_veil_founder"
	fc.stage = &"channel_open"
	fc.first_aware_day = 50
	var path := "user://test_first_contact_state_roundtrip.tres"
	ResourceSaver.save(fc, path)
	var loaded: FirstContactState = ResourceLoader.load(path) as FirstContactState
	assert_not_null(loaded)
	assert_eq(loaded.stage, &"channel_open")
	assert_eq(loaded.first_aware_day, 50)
	DirAccess.remove_absolute(path)
