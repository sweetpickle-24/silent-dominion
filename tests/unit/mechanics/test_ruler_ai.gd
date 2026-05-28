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


func _make_kingdom_with_ruler(kid: StringName, ruler_id: StringName, places: Array[StringName], tax: int = 40) -> KingdomRecord:
	var k := KingdomRecord.new()
	k.id = kid
	k.display_name = "Test Kingdom"
	k.ruler_character_id = ruler_id
	k.capital_place_id = places[0] if places.size() > 0 else &""
	k.member_place_ids = places
	k.tax_level = tax
	k.legitimacy = 60
	k.standing_army = 50
	return k


func _register_test_kingdom(k: KingdomRecord) -> void:
	_kingdom._kingdoms[k.id] = k
	for place_id: StringName in k.member_place_ids:
		_kingdom._place_to_kingdom[place_id] = k.id
	_ruler_ai._ensure_ruler_state(k.id)


func _make_rule(id: StringName, condition: String, action_kind: StringName, params: Dictionary = {}, priority: int = 100, cooldown: int = 30, tier: StringName = &"operational") -> SocietyAIRule:
	var r := SocietyAIRule.new()
	r.id = id
	r.priority = priority
	r.condition = condition
	r.action_kind = action_kind
	r.action_params = params
	r.cooldown_days = cooldown
	r.rule_tier = tier
	return r


func test_ruler_runs_rule_and_fires_decision():
	var k := _make_kingdom_with_ruler(&"test_k", &"ruler_athens", [&"athens"])
	_register_test_kingdom(k)
	# Add a rule that always fires
	var rule := _make_rule(&"test:always", "true", &"adjust_tax_level", {"delta": 5})
	_ruler_ai._rules_baseline = [rule]
	_ruler_ai._runners[&"test_k"].ensure_rule_state(rule.id)
	# Evaluate
	_ruler_ai._evaluate_ruler(&"test_k", 100)
	assert_eq(k.tax_level, 45, "Tax should have increased by 5")
	var state: RulerState = _ruler_ai.get_ruler_state(&"test_k")
	assert_eq(state.recent_decisions.size(), 1)


func test_trait_gated_rule_fires_for_matching_traits():
	var k := _make_kingdom_with_ruler(&"test_k", &"ruler_persia", [&"athens"])
	_register_test_kingdom(k)
	# Rule: only fires if ruler.ambition > 65 (Persia ruler has 75)
	var rule := _make_rule(&"test:ambitious", "self.ambition > 65", &"adjust_tax_level", {"delta": 10})
	_ruler_ai._rules_baseline = [rule]
	_ruler_ai._runners[&"test_k"].ensure_rule_state(rule.id)
	_ruler_ai._evaluate_ruler(&"test_k", 100)
	assert_eq(k.tax_level, 50, "Ambitious ruler should raise tax")


func test_trait_gated_rule_skips_non_matching():
	var k := _make_kingdom_with_ruler(&"test_k", &"ruler_athens", [&"athens"])
	_register_test_kingdom(k)
	# Athens ruler has ambition=55, below 65
	var rule := _make_rule(&"test:ambitious", "self.ambition > 65", &"adjust_tax_level", {"delta": 10})
	_ruler_ai._rules_baseline = [rule]
	_ruler_ai._runners[&"test_k"].ensure_rule_state(rule.id)
	_ruler_ai._evaluate_ruler(&"test_k", 100)
	assert_eq(k.tax_level, 40, "Non-ambitious ruler should not fire ambitious rule")


func test_adjust_tax_level_decision():
	var k := _make_kingdom_with_ruler(&"test_k", &"ruler_athens", [&"athens"])
	_register_test_kingdom(k)
	_ruler_ai._apply_decision(&"adjust_tax_level", {"delta": -15}, &"test_k", 100)
	assert_eq(k.tax_level, 25)


func test_raise_army_decision():
	var k := _make_kingdom_with_ruler(&"test_k", &"ruler_athens", [&"athens"])
	_register_test_kingdom(k)
	_ruler_ai._apply_decision(&"raise_army", {"amount": 100}, &"test_k", 100)
	assert_eq(k.standing_army, 150)


func test_take_loan_decision():
	var k := _make_kingdom_with_ruler(&"test_k", &"ruler_athens", [&"athens"])
	_register_test_kingdom(k)
	_ruler_ai._apply_decision(&"take_loan", {"creditor": &"temple", "amount": 1000}, &"test_k", 100)
	assert_eq(k.debt_by_creditor[&"temple"], 1000)


func test_service_debt_decision():
	var k := _make_kingdom_with_ruler(&"test_k", &"ruler_athens", [&"athens"])
	k.debt_by_creditor = {&"temple": 500}
	_register_test_kingdom(k)
	_ruler_ai._apply_decision(&"service_debt", {"amount": 200}, &"test_k", 100)
	assert_eq(k.debt_by_creditor[&"temple"], 300)


func test_shift_faction_favor_decision():
	var k := _make_kingdom_with_ruler(&"test_k", &"ruler_athens", [&"athens"])
	_register_test_kingdom(k)
	_ruler_ai._apply_decision(&"shift_faction_favor", {"faction": &"military", "delta": 15}, &"test_k", 100)
	assert_eq(k.faction_military, 40)


func test_set_rivalry_tension_decision():
	var k := _make_kingdom_with_ruler(&"test_k", &"ruler_athens", [&"athens"])
	_register_test_kingdom(k)
	_ruler_ai._apply_decision(&"set_rivalry_tension", {"other_kingdom": &"sparta", "delta": 20}, &"test_k", 100)
	assert_eq(k.rivalry_tensions[&"sparta"], 20)


func test_invest_in_place_decision():
	var k := _make_kingdom_with_ruler(&"test_k", &"ruler_athens", [&"athens"])
	_register_test_kingdom(k)
	var wr: Node = get_node("/root/WorldRegistry")
	var place: PlaceRecord = wr.get_place(&"athens")
	if place == null:
		pending("Athens not available")
		return
	var old_infra: int = place.infrastructure_level
	_ruler_ai._apply_decision(&"invest_in_place", {"place_id": &"athens"}, &"test_k", 100)
	assert_eq(place.infrastructure_level, old_infra + 1)
	place.infrastructure_level = old_infra  # restore


func test_cooldown_respected():
	var k := _make_kingdom_with_ruler(&"test_k", &"ruler_athens", [&"athens"])
	_register_test_kingdom(k)
	var rule := _make_rule(&"test:cooldown", "true", &"adjust_tax_level", {"delta": 5}, 100, 30)
	_ruler_ai._rules_baseline = [rule]
	_ruler_ai._runners[&"test_k"].ensure_rule_state(rule.id)
	# Fire on day 100
	_ruler_ai._evaluate_ruler(&"test_k", 100)
	assert_eq(k.tax_level, 45)
	# Try on day 110 — within 30-day cooldown
	_ruler_ai._evaluate_ruler(&"test_k", 110)
	assert_eq(k.tax_level, 45, "Should not fire within cooldown")
	# Day 131 — past cooldown
	_ruler_ai._evaluate_ruler(&"test_k", 131)
	assert_eq(k.tax_level, 50, "Should fire after cooldown expires")


func test_ruler_decision_event_fires():
	var events: Array = []
	var eb: Node = get_node("/root/EventBus")
	var sub = eb.subscribe(
		preload("res://scripts/data/events/ruler_decision_made_event.gd"),
		func(e): events.append(e),
		50,
	)
	var k := _make_kingdom_with_ruler(&"test_k", &"ruler_athens", [&"athens"])
	_register_test_kingdom(k)
	var rule := _make_rule(&"test:event", "true", &"adjust_tax_level", {"delta": 5})
	_ruler_ai._rules_baseline = [rule]
	_ruler_ai._runners[&"test_k"].ensure_rule_state(rule.id)
	_ruler_ai._evaluate_ruler(&"test_k", 100)
	assert_eq(events.size(), 1)
	assert_eq(events[0].decision, &"adjust_tax_level")
	assert_eq(events[0].kingdom_id, &"test_k")
	eb.unsubscribe(sub)


func test_fidelity_low_skips_full_fidelity_rules():
	var k := _make_kingdom_with_ruler(&"test_k", &"ruler_athens", [&"athens"])
	_register_test_kingdom(k)
	# Baseline rule
	var rule_base := _make_rule(&"test:base", "true", &"adjust_tax_level", {"delta": 5}, 100, 1)
	# Full-fidelity rule with higher priority (lower number)
	var rule_full := _make_rule(&"test:full", "true", &"adjust_tax_level", {"delta": 20}, 50, 1, &"full_fidelity")
	_ruler_ai._rules_baseline = [rule_base]
	_ruler_ai._rules_full_fidelity = [rule_full]
	_ruler_ai._runners[&"test_k"].ensure_rule_state(rule_base.id)
	_ruler_ai._runners[&"test_k"].ensure_rule_state(rule_full.id)
	# Force low fidelity
	_ruler_ai.get_ruler_state(&"test_k").fidelity = &"low"
	_ruler_ai._evaluate_ruler(&"test_k", 100)
	assert_eq(k.tax_level, 45, "Low-fidelity should only run baseline rule (+5)")


func test_save_load_roundtrip():
	var k := _make_kingdom_with_ruler(&"test_k", &"ruler_athens", [&"athens"])
	_register_test_kingdom(k)
	_ruler_ai.get_ruler_state(&"test_k").confidence_modifier = 10
	_ruler_ai._runners[&"test_k"].set_rule_memory(&"test_rule", &"last_target", &"athens")
	var snapshot: Dictionary = _ruler_ai.snapshot_state()
	assert_true(snapshot.has("ruler_states"))
	assert_true(snapshot.has("runners"))
	# Clear and restore
	_ruler_ai._ruler_states.clear()
	_ruler_ai._runners.clear()
	_ruler_ai.apply_state(snapshot)
	var restored: RulerState = _ruler_ai.get_ruler_state(&"test_k")
	assert_not_null(restored)
	assert_eq(restored.confidence_modifier, 10)
