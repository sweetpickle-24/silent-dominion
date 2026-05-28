extends GutTest

var _ai: SocietyAI
var _action: Action
var _chain: Chain


func before_each():
	_action = Action.new()
	_action.name = "Action"
	add_child(_action)
	_chain = Chain.new()
	_chain.name = "Chain"
	add_child(_chain)
	_ai = SocietyAI.new()
	_ai.name = "SocietyAI"
	add_child(_ai)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_ai):
		if _ai._tick_sub:
			eb.unsubscribe(_ai._tick_sub)
		for sub in _ai._reactive_subs:
			eb.unsubscribe(sub)
	if is_instance_valid(_action):
		if _action._phase_advanced_sub:
			eb.unsubscribe(_action._phase_advanced_sub)
		if _action._cancelled_sub:
			eb.unsubscribe(_action._cancelled_sub)
	if is_instance_valid(_chain) and _chain._tick_subscription:
		eb.unsubscribe(_chain._tick_subscription)
	for node in [_ai, _chain, _action]:
		if is_instance_valid(node):
			remove_child(node)
			node.free()


func test_no_rules_no_dispatch():
	# Clear rules and evaluate — should dispatch nothing
	_ai._rules_by_society.clear()
	_ai._evaluate_society_rules(&"the_veil", 100)
	var veil_immortal_id: StringName = _ai._get_society_immortal_id(&"the_veil")
	var schemes: Array = _action.get_active_schemes(veil_immortal_id)
	assert_eq(schemes.size(), 0)


func test_rule_condition_false_no_dispatch():
	# Replace rules with one that has condition "false"
	_ai._rules_by_society[&"the_veil"] = []
	var r := SocietyAIRule.new()
	r.id = &"test:never_fires"
	r.society_id = &"the_veil"
	r.priority = 100
	r.condition = "false"
	r.action_kind = &"dispatch_scheme"
	r.action_params = {"action_type": &"observe", "target_selector": &"specific_place", "target_constraints": {"place_id": &"athens"}}
	r.cooldown_days = 1
	_ai._rules_by_society[&"the_veil"].append(r)
	_ai._rule_state[r.id] = {"last_fired_at_day": -1, "times_fired": 0}
	_ai._evaluate_society_rules(&"the_veil", 100)
	var schemes: Array = _action.get_active_schemes(_ai._get_society_immortal_id(&"the_veil"))
	assert_eq(schemes.size(), 0, "False condition should not dispatch")


func test_rule_fires_and_updates_state():
	_ai._rules_by_society[&"the_veil"] = []
	var r := SocietyAIRule.new()
	r.id = &"test:always_fires"
	r.society_id = &"the_veil"
	r.priority = 100
	r.condition = "true"
	r.action_kind = &"dispatch_scheme"
	r.action_params = {"action_type": &"observe", "target_selector": &"specific_place", "target_constraints": {"place_id": &"athens"}}
	r.cooldown_days = 30
	_ai._rules_by_society[&"the_veil"].append(r)
	_ai._rule_state[r.id] = {"last_fired_at_day": -1, "times_fired": 0}
	_ai._evaluate_society_rules(&"the_veil", 100)
	assert_eq(_ai._rule_state[r.id].last_fired_at_day, 100, "Rule should have updated last_fired_at_day")
	assert_eq(_ai._rule_state[r.id].times_fired, 1)


func test_rule_on_cooldown_skipped():
	_ai._rules_by_society[&"the_veil"] = []
	var r := SocietyAIRule.new()
	r.id = &"test:cooldown"
	r.society_id = &"the_veil"
	r.priority = 100
	r.condition = "true"
	r.action_kind = &"dispatch_scheme"
	r.action_params = {"action_type": &"observe", "target_selector": &"specific_place", "target_constraints": {"place_id": &"athens"}}
	r.cooldown_days = 30
	_ai._rules_by_society[&"the_veil"].append(r)
	_ai._rule_state[r.id] = {"last_fired_at_day": 95, "times_fired": 1}
	_ai._evaluate_society_rules(&"the_veil", 100)  # 100 - 95 = 5 < 30 cooldown
	assert_eq(_ai._rule_state[r.id].times_fired, 1, "Rule on cooldown should not fire again")


func test_concurrent_scheme_cap():
	# Fill up to MAX_CONCURRENT_SCHEMES_PER_SOCIETY
	var veil_id: StringName = _ai._get_society_immortal_id(&"the_veil")
	for i in range(SocietyAI.MAX_CONCURRENT_SCHEMES_PER_SOCIETY):
		_action.dispatch(&"observe", &"athens", &"athens", veil_id)
	_ai._rules_by_society[&"the_veil"] = []
	var r := SocietyAIRule.new()
	r.id = &"test:capped"
	r.society_id = &"the_veil"
	r.priority = 100
	r.condition = "true"
	r.action_kind = &"dispatch_scheme"
	r.action_params = {"action_type": &"observe", "target_selector": &"specific_place", "target_constraints": {"place_id": &"miletus"}}
	r.cooldown_days = 1
	_ai._rules_by_society[&"the_veil"].append(r)
	_ai._rule_state[r.id] = {"last_fired_at_day": -1, "times_fired": 0}
	_ai._evaluate_society_rules(&"the_veil", 100)
	var total: Array = _action.get_active_schemes(veil_id)
	assert_eq(total.size(), SocietyAI.MAX_CONCURRENT_SCHEMES_PER_SOCIETY, "Should not exceed cap")


func test_priority_ordering():
	_ai._rules_by_society[&"the_veil"] = []
	var r_low := SocietyAIRule.new()
	r_low.id = &"test:low_priority"
	r_low.society_id = &"the_veil"
	r_low.priority = 50
	r_low.condition = "true"
	r_low.action_kind = &"dispatch_scheme"
	r_low.action_params = {"action_type": &"observe", "target_selector": &"specific_place", "target_constraints": {"place_id": &"athens"}}
	r_low.cooldown_days = 1
	var r_high := SocietyAIRule.new()
	r_high.id = &"test:high_priority"
	r_high.society_id = &"the_veil"
	r_high.priority = 200
	r_high.condition = "true"
	r_high.action_kind = &"dispatch_scheme"
	r_high.action_params = {"action_type": &"observe", "target_selector": &"specific_place", "target_constraints": {"place_id": &"miletus"}}
	r_high.cooldown_days = 1
	_ai._rules_by_society[&"the_veil"] = [r_low, r_high]
	_ai._rules_by_society[&"the_veil"].sort_custom(func(a, b): return a.priority < b.priority)
	_ai._rule_state[r_low.id] = {"last_fired_at_day": -1, "times_fired": 0}
	_ai._rule_state[r_high.id] = {"last_fired_at_day": -1, "times_fired": 0}
	_ai._evaluate_society_rules(&"the_veil", 100)
	# Lower priority fires first; only one rule per tick
	assert_eq(_ai._rule_state[r_low.id].times_fired, 1, "Low priority rule should fire")
	assert_eq(_ai._rule_state[r_high.id].times_fired, 0, "High priority rule should not fire (one per tick)")
