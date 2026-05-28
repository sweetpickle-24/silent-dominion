extends GutTest

# Integration: two kingdoms with identical fiscal situation but different ruler traits.
# Verify they make different decisions → divergent trajectories.

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


func test_different_traits_different_outcomes():
	# Kingdom A: ruthless ruler (ruler_sparta, ruthlessness=70)
	var k_a := KingdomRecord.new()
	k_a.id = &"kingdom_a"
	k_a.display_name = "Kingdom A"
	k_a.ruler_character_id = &"ruler_sparta"
	k_a.capital_place_id = &"sparta"
	k_a.member_place_ids = [&"sparta"]
	k_a.tax_level = 40
	k_a.legitimacy = 60
	k_a.treasury_condition = &"strained"
	k_a.standing_army = 100
	_kingdom._kingdoms[&"kingdom_a"] = k_a
	_kingdom._place_to_kingdom[&"sparta"] = &"kingdom_a"

	# Kingdom B: moderate ruler (ruler_athens, ruthlessness=35)
	var k_b := KingdomRecord.new()
	k_b.id = &"kingdom_b"
	k_b.display_name = "Kingdom B"
	k_b.ruler_character_id = &"ruler_athens"
	k_b.capital_place_id = &"corinth"
	k_b.member_place_ids = [&"corinth"]
	k_b.tax_level = 40
	k_b.legitimacy = 60
	k_b.treasury_condition = &"strained"
	k_b.standing_army = 100
	_kingdom._kingdoms[&"kingdom_b"] = k_b
	_kingdom._place_to_kingdom[&"corinth"] = &"kingdom_b"

	_ruler_ai._ensure_ruler_state(&"kingdom_a")
	_ruler_ai._ensure_ruler_state(&"kingdom_b")

	# Rule: ruthless rulers raise tax aggressively
	var rule := SocietyAIRule.new()
	rule.id = &"test:ruthless_tax"
	rule.priority = 50
	rule.condition = "self.ruthlessness > 60 and target.treasury_condition == \"strained\""
	rule.action_kind = &"adjust_tax_level"
	rule.action_params = {"delta": 15}
	rule.cooldown_days = 30
	_ruler_ai._rules_baseline = [rule]
	_ruler_ai._runners[&"kingdom_a"].ensure_rule_state(rule.id)
	_ruler_ai._runners[&"kingdom_b"].ensure_rule_state(rule.id)

	_ruler_ai._evaluate_ruler(&"kingdom_a", 100)
	_ruler_ai._evaluate_ruler(&"kingdom_b", 100)

	assert_ne(k_a.tax_level, k_b.tax_level, "Different ruler traits should produce different decisions")
	assert_eq(k_a.tax_level, 55, "Ruthless ruler should raise tax aggressively")
	assert_eq(k_b.tax_level, 40, "Moderate ruler should not fire ruthless rule")
