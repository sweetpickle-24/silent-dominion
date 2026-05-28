extends GutTest

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


func _make_rule(id: StringName, condition: String, action_kind: StringName, params: Dictionary, priority: int = 100, tier: StringName = &"operational") -> SocietyAIRule:
	var r := SocietyAIRule.new()
	r.id = id
	r.priority = priority
	r.condition = condition
	r.action_kind = action_kind
	r.action_params = params
	r.cooldown_days = 1
	r.rule_tier = tier
	return r


func _setup_kingdom(kid: StringName) -> KingdomRecord:
	var k := KingdomRecord.new()
	k.id = kid
	k.display_name = "Test"
	k.ruler_character_id = &"ruler_athens"
	k.capital_place_id = &"athens"
	k.member_place_ids = [&"athens"]
	k.tax_level = 40
	k.treasury_condition = &"stable"
	_kingdom._kingdoms[kid] = k
	_kingdom._place_to_kingdom[&"athens"] = kid
	_ruler_ai._ensure_ruler_state(kid)
	return k


func test_full_fidelity_gets_extra_rules():
	var k := _setup_kingdom(&"fid_test")
	var rule_base := _make_rule(&"test:base", "true", &"adjust_tax_level", {"delta": 5}, 100)
	var rule_full := _make_rule(&"test:full_only", "true", &"adjust_tax_level", {"delta": 20}, 50, &"full_fidelity")
	_ruler_ai._rules_baseline = [rule_base]
	_ruler_ai._rules_full_fidelity = [rule_full]
	var runner: RuleListRunner = _ruler_ai._runners[&"fid_test"]
	runner.ensure_rule_state(rule_base.id)
	runner.ensure_rule_state(rule_full.id)

	# Build context and evaluate directly with merged rules (bypass _update_fidelity)
	var state: RulerState = _ruler_ai.get_ruler_state(&"fid_test")
	state.fidelity = &"full"
	var context: RuleContext = _ruler_ai._build_ruler_context(state, &"fid_test", 100)
	var rules: Array = _ruler_ai._rules_baseline.duplicate()
	rules.append_array(_ruler_ai._rules_full_fidelity)
	rules.sort_custom(func(a: SocietyAIRule, b: SocietyAIRule) -> bool: return a.priority < b.priority)
	var re: Node = get_node("/root/RuleEvaluator")
	runner.evaluate_rules(rules, 100, context, re,
		func(rule: SocietyAIRule) -> bool: return _ruler_ai._fire_decision(rule, state, &"fid_test", 100),
		true)
	assert_eq(k.tax_level, 60, "Full-fidelity should use the full rule (+20)")


func test_low_fidelity_skips_full_rules():
	var k := _setup_kingdom(&"low_test")
	var rule_base := _make_rule(&"test:base", "true", &"adjust_tax_level", {"delta": 5}, 100)
	var rule_full := _make_rule(&"test:full_only", "true", &"adjust_tax_level", {"delta": 20}, 50, &"full_fidelity")
	_ruler_ai._rules_baseline = [rule_base]
	_ruler_ai._rules_full_fidelity = [rule_full]
	_ruler_ai._runners[&"low_test"].ensure_rule_state(rule_base.id)
	_ruler_ai._runners[&"low_test"].ensure_rule_state(rule_full.id)

	# Force low fidelity
	_ruler_ai.get_ruler_state(&"low_test").fidelity = &"low"
	_ruler_ai._evaluate_ruler(&"low_test", 100)
	assert_eq(k.tax_level, 45, "Low-fidelity should only use baseline rule (+5)")


func test_reactive_rule_fires_on_treasury_crash():
	var k := _setup_kingdom(&"reactive_test")
	k.treasury_condition = &"broke"
	k.unrest = 60
	# Reactive rule triggers on KingdomTreasuryConditionChangedEvent
	var rule := _make_rule(&"test:reactive", "target.treasury_condition == \"broke\" and target.unrest > 50",
		&"adjust_tax_level", {"delta": -20}, 5)
	rule.reactive_trigger_event_classes = [&"KingdomTreasuryConditionChangedEvent"]
	_ruler_ai._rules_baseline = [rule]
	_ruler_ai._runners[&"reactive_test"].ensure_rule_state(rule.id)

	# Simulate the event
	var event := KingdomTreasuryConditionChangedEvent.new()
	event.kingdom_id = &"reactive_test"
	event.old_condition = &"strained"
	event.new_condition = &"broke"
	event.day = 100
	_ruler_ai._on_reactive_event(event)
	assert_eq(k.tax_level, 20, "Reactive rule should fire immediately on treasury crash")


func test_reactive_respects_cooldown():
	var k := _setup_kingdom(&"cool_test")
	k.treasury_condition = &"broke"
	k.unrest = 60
	var rule := _make_rule(&"test:reactive_cd", "target.treasury_condition == \"broke\"",
		&"adjust_tax_level", {"delta": -10}, 5)
	rule.reactive_trigger_event_classes = [&"KingdomTreasuryConditionChangedEvent"]
	rule.cooldown_days = 30
	_ruler_ai._rules_baseline = [rule]
	_ruler_ai._runners[&"cool_test"].ensure_rule_state(rule.id)

	var event := KingdomTreasuryConditionChangedEvent.new()
	event.kingdom_id = &"cool_test"
	event.old_condition = &"strained"
	event.new_condition = &"broke"
	event.day = 100
	_ruler_ai._on_reactive_event(event)
	assert_eq(k.tax_level, 30, "First reactive fire should work")

	# Second event within cooldown
	event.day = 110
	_ruler_ai._on_reactive_event(event)
	assert_eq(k.tax_level, 30, "Should not fire within cooldown")
