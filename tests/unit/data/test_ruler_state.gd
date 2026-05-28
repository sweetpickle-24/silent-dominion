extends GutTest

func test_field_access():
	var rs := RulerState.new()
	rs.ruler_character_id = &"darius"
	rs.kingdom_id = &"persia"
	rs.goal_weights = {&"maintain_power": 80, &"secure_succession": 40}
	rs.fidelity = &"full"
	assert_eq(rs.ruler_character_id, &"darius")
	assert_eq(rs.fidelity, &"full")

func test_record_decision():
	var rs := RulerState.new()
	rs.record_decision(&"adjust_tax_level", 100, &"success")
	assert_eq(rs.recent_decisions.size(), 1)
	assert_eq(rs.confidence_modifier, 3)
	rs.record_decision(&"raise_army", 110, &"failure")
	assert_eq(rs.confidence_modifier, -2)  # 3 - 5

func test_save_load_roundtrip():
	var rs := RulerState.new()
	rs.ruler_character_id = &"test_ruler"
	rs.kingdom_id = &"test_kingdom"
	rs.confidence_modifier = 10
	var path := "user://test_ruler_state_roundtrip.tres"
	ResourceSaver.save(rs, path)
	var loaded: RulerState = ResourceLoader.load(path) as RulerState
	assert_not_null(loaded)
	assert_eq(loaded.confidence_modifier, 10)
	DirAccess.remove_absolute(path)
