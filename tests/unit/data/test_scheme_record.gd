extends GutTest


func test_field_access():
	var s := SchemeRecord.new()
	s.id = &"scheme_1"
	s.immortal_id = &"player"
	s.action_type = ActionTypeValues.PLANT_IDEA
	s.target_ref = &"athens"
	s.target_place_ref = &"athens"
	s.current_phase = SchemePhases.DISPATCHED
	s.dispatched_at_day = 10
	s.current_phase_entered_at_day = 10
	assert_eq(s.id, &"scheme_1")
	assert_eq(s.action_type, ActionTypeValues.PLANT_IDEA)
	assert_eq(s.current_phase, SchemePhases.DISPATCHED)


func test_defaults():
	var s := SchemeRecord.new()
	assert_eq(s.current_phase, SchemePhases.DRAFTED)
	assert_eq(s.outcome, &"")
	assert_eq(s.resolved_at_day, -1)


func test_phase_history():
	var s := SchemeRecord.new()
	s.phase_history.append({"phase": SchemePhases.DISPATCHED, "entered_at_day": 0})
	s.phase_history.append({"phase": SchemePhases.ACKNOWLEDGED, "entered_at_day": 2})
	assert_eq(s.phase_history.size(), 2)
	assert_eq(s.phase_history[1].phase, SchemePhases.ACKNOWLEDGED)


func test_save_load_roundtrip():
	var s := SchemeRecord.new()
	s.id = &"roundtrip_scheme"
	s.immortal_id = &"player"
	s.action_type = ActionTypeValues.CULTIVATE
	s.current_phase = SchemePhases.EXECUTING
	s.dispatched_at_day = 5
	s.current_phase_entered_at_day = 15

	var path: String = "user://test_scheme_record_roundtrip.tres"
	ResourceSaver.save(s, path)
	var loaded: SchemeRecord = ResourceLoader.load(path) as SchemeRecord
	assert_not_null(loaded)
	assert_eq(loaded.id, &"roundtrip_scheme")
	assert_eq(loaded.action_type, ActionTypeValues.CULTIVATE)
	assert_eq(loaded.current_phase, SchemePhases.EXECUTING)
	DirAccess.remove_absolute(path)
