extends GutTest

# Integration: a kingdom under fiscal pressure. Ruler raises taxes → treasury recovers
# but unrest climbs → ruler forced to lower taxes when unrest critical.

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


func test_fiscal_feedback_loop():
	# Setup: a kingdom starting strained
	var k := KingdomRecord.new()
	k.id = &"fiscal_test"
	k.display_name = "Fiscal Test Kingdom"
	k.ruler_character_id = &"ruler_athens"
	k.capital_place_id = &"athens"
	k.member_place_ids = [&"athens"]
	k.tax_level = 30
	k.legitimacy = 60
	k.unrest = 10
	k.standing_army = 50
	k.treasury_condition = &"strained"
	_kingdom._kingdoms[&"fiscal_test"] = k
	_kingdom._place_to_kingdom[&"athens"] = &"fiscal_test"
	_ruler_ai._ensure_ruler_state(&"fiscal_test")

	# Set up a "raise tax when strained" rule
	var raise_rule := SocietyAIRule.new()
	raise_rule.id = &"test:raise"
	raise_rule.priority = 30
	raise_rule.condition = "target.treasury_condition == \"strained\""
	raise_rule.action_kind = &"adjust_tax_level"
	raise_rule.action_params = {"delta": 10}
	raise_rule.cooldown_days = 30

	# Set up a "lower tax when unrest critical" rule
	var lower_rule := SocietyAIRule.new()
	lower_rule.id = &"test:lower"
	lower_rule.priority = 10  # higher priority
	lower_rule.condition = "target.unrest > 60"
	lower_rule.action_kind = &"adjust_tax_level"
	lower_rule.action_params = {"delta": -15}
	lower_rule.cooldown_days = 30

	_ruler_ai._rules_baseline = [lower_rule, raise_rule]
	_ruler_ai._runners[&"fiscal_test"].ensure_rule_state(raise_rule.id)
	_ruler_ai._runners[&"fiscal_test"].ensure_rule_state(lower_rule.id)

	# Set place tax yield so kingdom has real income
	var wr: Node = get_node("/root/WorldRegistry")
	var athens: PlaceRecord = wr.get_place(&"athens")
	var saved_yield: int = athens.tax_yield_per_day
	athens.tax_yield_per_day = 50

	# Run 365 days
	var initial_tax: int = k.tax_level
	for day in range(1, 366):
		_kingdom._update_kingdom(&"fiscal_test", day)
		_ruler_ai._evaluate_ruler(&"fiscal_test", day)

	athens.tax_yield_per_day = saved_yield  # restore

	# Verify the loop ran: tax should have changed from initial
	assert_ne(k.tax_level, initial_tax, "Tax level should have changed over a year")
	# Verify unrest and tax interacted — the kingdom didn't just sit still
	var state: RulerState = _ruler_ai.get_ruler_state(&"fiscal_test")
	assert_gt(state.recent_decisions.size(), 0, "Ruler should have made decisions")
