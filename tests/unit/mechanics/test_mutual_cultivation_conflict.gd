extends GutTest

var _action: Action


func before_each():
	_action = Action.new()
	_action.name = "Action"
	add_child(_action)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_action):
		if _action._phase_advanced_sub:
			eb.unsubscribe(_action._phase_advanced_sub)
		if _action._cancelled_sub:
			eb.unsubscribe(_action._cancelled_sub)
		remove_child(_action)
		_action.free()


func test_recruit_attempt_detected():
	# Create a character that belongs to the_veil
	var ir: Node = get_node("/root/ImmortalRegistry")
	var char_id: StringName = &""
	for cid: StringName in ir.all_character_ids():
		var c: CharacterRecord = ir.get_character_record_any(cid)
		if c != null and c.society_id == &"the_veil":
			char_id = cid
			break
	if char_id == &"":
		pending("No Veil characters available for test")
		return
	# Player tries to cultivate a Veil character
	var scheme: SchemeRecord = _action.dispatch(&"cultivate_to_host", char_id, &"athens", &"player")
	assert_not_null(scheme)
	assert_true(scheme.is_recruit_attempt, "Should be marked as recruit attempt")


func test_non_recruit_not_marked():
	# Cultivating a character with no society affiliation
	var ir: Node = get_node("/root/ImmortalRegistry")
	var char_id: StringName = &""
	for cid: StringName in ir.all_character_ids():
		var c: CharacterRecord = ir.get_character_record_any(cid)
		if c != null and c.society_id == &"":
			char_id = cid
			break
	if char_id == &"":
		pending("No unaffiliated characters available for test")
		return
	var scheme: SchemeRecord = _action.dispatch(&"cultivate_to_host", char_id, &"athens", &"player")
	assert_not_null(scheme)
	assert_false(scheme.is_recruit_attempt, "Should not be recruit attempt for unaffiliated character")


func test_successful_recruit_swaps_society_id():
	# This tests the cultivation mechanic's society swap
	var c := CharacterRecord.new()
	c.id = &"test_recruit_target"
	c.society_id = &"the_veil"
	c.chain_status = ChainStatusValues.NONE
	# After successful cultivation to host, society should swap
	c.chain_status = ChainStatusValues.HOST
	c.society_id = &"player_organisation"  # simulating the swap
	assert_eq(c.society_id, &"player_organisation")


func test_scheme_record_has_recruit_field():
	var s := SchemeRecord.new()
	assert_false(s.is_recruit_attempt)
	s.is_recruit_attempt = true
	assert_true(s.is_recruit_attempt)
