extends GutTest

# Verify that different ruler traits produce different decisions
# given identical kingdom situations.

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


func _make_rule(id: StringName, condition: String, action_kind: StringName, params: Dictionary, priority: int = 100) -> SocietyAIRule:
	var r := SocietyAIRule.new()
	r.id = id
	r.priority = priority
	r.condition = condition
	r.action_kind = action_kind
	r.action_params = params
	r.cooldown_days = 1
	return r


func _setup_kingdom(kid: StringName, ruler_id: StringName) -> KingdomRecord:
	var k := KingdomRecord.new()
	k.id = kid
	k.display_name = "Test"
	k.ruler_character_id = ruler_id
	k.capital_place_id = &"athens"
	k.member_place_ids = [&"athens"]
	k.tax_level = 40
	k.legitimacy = 60
	k.standing_army = 100
	k.treasury_condition = &"flush"
	_kingdom._kingdoms[kid] = k
	_kingdom._place_to_kingdom[&"athens"] = kid
	_ruler_ai._ensure_ruler_state(kid)
	return k


func test_ambitious_ruler_expands_cautious_does_not():
	# Persia (ambition 75) vs Cyrene (ambition 45)
	var k_ambitious := _setup_kingdom(&"k_ambitious", &"ruler_persia")
	var k_cautious := _setup_kingdom(&"k_cautious", &"ruler_cyrene")
	# Remove athens from k_cautious to avoid place conflict
	k_cautious.capital_place_id = &"corinth"
	k_cautious.member_place_ids = [&"corinth"]

	var rule := _make_rule(&"test:expand", "self.ambition > 65 and target.treasury_condition == \"flush\"",
		&"set_rivalry_tension", {"other_kingdom": &"sparta", "delta": 15}, 60)
	_ruler_ai._rules_baseline = [rule]
	_ruler_ai._runners[&"k_ambitious"].ensure_rule_state(rule.id)
	_ruler_ai._runners[&"k_cautious"].ensure_rule_state(rule.id)

	_ruler_ai._evaluate_ruler(&"k_ambitious", 100)
	_ruler_ai._evaluate_ruler(&"k_cautious", 100)

	assert_eq(k_ambitious.rivalry_tensions.get(&"sparta", 0), 15, "Ambitious ruler should expand rivalry")
	assert_eq(k_cautious.rivalry_tensions.get(&"sparta", 0), 0, "Cautious ruler should not expand")


func test_ruthless_vs_moderate_tax_behavior():
	# Sparta (ruthlessness 70) vs Athens (ruthlessness 35)
	var k_ruth := _setup_kingdom(&"k_ruth", &"ruler_sparta")
	k_ruth.treasury_condition = &"strained"
	var k_mod := _setup_kingdom(&"k_mod", &"ruler_athens")
	k_mod.treasury_condition = &"strained"
	k_mod.capital_place_id = &"corinth"
	k_mod.member_place_ids = [&"corinth"]

	var rule := _make_rule(&"test:ruthless_tax", "self.ruthlessness > 60 and target.treasury_condition == \"strained\"",
		&"adjust_tax_level", {"delta": 15}, 50)
	_ruler_ai._rules_baseline = [rule]
	_ruler_ai._runners[&"k_ruth"].ensure_rule_state(rule.id)
	_ruler_ai._runners[&"k_mod"].ensure_rule_state(rule.id)

	_ruler_ai._evaluate_ruler(&"k_ruth", 100)
	_ruler_ai._evaluate_ruler(&"k_mod", 100)

	assert_eq(k_ruth.tax_level, 55, "Ruthless ruler should aggressively raise taxes")
	assert_eq(k_mod.tax_level, 40, "Moderate ruler should not fire ruthless rule")
