extends GutTest

# Verify that advisor influence affects ruler decisions.

var _kingdom: Kingdom
var _ruler_ai: RulerAI


func before_each():
	_kingdom = Kingdom.new()
	_kingdom.name = "Kingdom"
	add_child(_kingdom)
	_ruler_ai = RulerAI.new()
	_ruler_ai.name = "RulerAI"
	add_child(_ruler_ai)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_ruler_ai):
		if _ruler_ai._tick_sub:
			eb.unsubscribe(_ruler_ai._tick_sub)
		for sub in _ruler_ai._reactive_subs:
			eb.unsubscribe(sub)
		remove_child(_ruler_ai)
		_ruler_ai.free()
	if is_instance_valid(_kingdom):
		if _kingdom._tick_sub:
			eb.unsubscribe(_kingdom._tick_sub)
		remove_child(_kingdom)
		_kingdom.free()


func test_advisor_influence_stored_on_ruler_state():
	var k := KingdomRecord.new()
	k.id = &"test_k"
	k.display_name = "Test"
	k.ruler_character_id = &"ruler_athens"
	k.capital_place_id = &"athens"
	k.member_place_ids = [&"athens"]
	k.tax_level = 40
	_kingdom._kingdoms[&"test_k"] = k
	_ruler_ai._ensure_ruler_state(&"test_k")

	var state: RulerState = _ruler_ai.get_ruler_state(&"test_k")
	state.advisor_influence = {
		&"advisor_military": 60,
		&"advisor_merchant": 40,
	}
	assert_eq(state.advisor_influence.size(), 2)


func test_purge_advisor_removes_influence():
	var k := KingdomRecord.new()
	k.id = &"test_k"
	k.display_name = "Test"
	k.ruler_character_id = &"ruler_athens"
	k.capital_place_id = &"athens"
	k.member_place_ids = [&"athens"]
	k.tax_level = 40
	_kingdom._kingdoms[&"test_k"] = k
	_ruler_ai._ensure_ruler_state(&"test_k")

	var state: RulerState = _ruler_ai.get_ruler_state(&"test_k")
	state.advisor_influence = {
		&"advisor_military": 60,
		&"advisor_merchant": 40,
	}

	_ruler_ai._apply_decision(&"purge_advisor", {"advisor_id": &"advisor_military"}, &"test_k", 100)
	assert_eq(state.advisor_influence.size(), 1)
	assert_false(state.advisor_influence.has(&"advisor_military"))
	assert_true(state.advisor_influence.has(&"advisor_merchant"))


func test_confidence_modifier_from_decisions():
	var state := RulerState.new()
	state.record_decision(&"raise_army", 100, &"success")
	assert_eq(state.confidence_modifier, 3)
	state.record_decision(&"adjust_tax_level", 110, &"success")
	assert_eq(state.confidence_modifier, 6)
	state.record_decision(&"take_loan", 120, &"failure")
	assert_eq(state.confidence_modifier, 1)  # 6 - 5
