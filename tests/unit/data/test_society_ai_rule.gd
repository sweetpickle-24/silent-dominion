extends GutTest


func test_field_access():
	var r := SocietyAIRule.new()
	r.id = &"test_rule"
	r.society_id = &"the_veil"
	r.priority = 50
	r.rule_tier = &"priority"
	r.condition = 'world.day > 100'
	r.action_kind = &"dispatch_scheme"
	r.action_params = {"action_type": &"observe", "target_selector": &"specific_place"}
	r.cooldown_days = 90
	assert_eq(r.id, &"test_rule")
	assert_eq(r.society_id, &"the_veil")
	assert_eq(r.priority, 50)
	assert_eq(r.cooldown_days, 90)


func test_save_load_roundtrip():
	var r := SocietyAIRule.new()
	r.id = &"roundtrip_rule"
	r.society_id = &"the_veil"
	r.priority = 100
	r.condition = 'true'
	r.action_kind = &"dispatch_scheme"
	r.action_params = {"action_type": &"observe"}
	r.cooldown_days = 30
	var path: String = "user://test_society_ai_rule_roundtrip.tres"
	ResourceSaver.save(r, path)
	var loaded: SocietyAIRule = ResourceLoader.load(path) as SocietyAIRule
	assert_not_null(loaded)
	assert_eq(loaded.id, &"roundtrip_rule")
	assert_eq(loaded.priority, 100)
	assert_eq(loaded.cooldown_days, 30)
	DirAccess.remove_absolute(path)


func test_rules_loaded_from_data():
	# SocietyAI is in the main scene; create a local one to verify loading
	var ai := SocietyAI.new()
	ai.name = "SocietyAI"
	add_child(ai)
	assert_gt(ai._rules_by_society.size(), 0, "Should have loaded at least one society's rules")
	assert_true(ai._rules_by_society.has(&"the_veil"), "Should have Veil rules")
	assert_eq(ai._rules_by_society[&"the_veil"].size(), 12, "Should have 12 Veil rules")
	remove_child(ai)
	ai.free()
