extends GutTest

# Integration: a ruler ages → dies → successor takes throne → RulerSucceededEvent
# → new RulerState runs decisions → legitimacy hit applied.
# Closes the 11.14a succession-risk loop.

var _kingdom: Kingdom
var _ruler_ai: RulerAI
var _mortality: Mortality


func before_each():
	_kingdom = Kingdom.new()
	_kingdom.name = "Kingdom"
	add_child(_kingdom)
	_ruler_ai = RulerAI.new()
	_ruler_ai.name = "RulerAI"
	add_child(_ruler_ai)
	_mortality = Mortality.new()
	_mortality.name = "Mortality"
	add_child(_mortality)


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
	if is_instance_valid(_mortality):
		if _mortality._tick_sub:
			eb.unsubscribe(_mortality._tick_sub)
		remove_child(_mortality)
		_mortality.free()


func test_full_succession_flow():
	# Use the real authored kingdoms
	assert_gt(_kingdom.kingdom_count(), 0)

	# Pick a kingdom and directly kill its ruler via Mortality
	var kid: StringName = _kingdom.all_kingdom_ids()[0]
	var k: KingdomRecord = _kingdom.get_kingdom(kid)
	var old_ruler_id: StringName = k.ruler_character_id
	var old_legitimacy: int = k.legitimacy

	var ir: Node = get_node("/root/ImmortalRegistry")
	# Verify the ruler exists and is not immortal
	var ruler: CharacterRecord = ir.get_character_record_any(old_ruler_id)
	if ruler == null or ir.is_immortal(old_ruler_id):
		pending("Ruler not available or is immortal")
		return

	# Collect succession events
	var succession_events: Array = []
	var eb: Node = get_node("/root/EventBus")
	var sub = eb.subscribe(
		preload("res://scripts/data/events/ruler_succeeded_event.gd"),
		func(e): succession_events.append(e),
		50,
	)

	# Kill the ruler
	_mortality.kill_character_by_cause(old_ruler_id, &"old_age", 500)

	# Verify succession happened
	assert_eq(succession_events.size(), 1, "Succession event should fire")
	assert_ne(k.ruler_character_id, old_ruler_id, "New ruler should replace old")
	assert_lt(k.legitimacy, old_legitimacy, "Legitimacy should drop on succession")

	# Verify new ruler has a RulerState and can make decisions
	var new_state: RulerState = _ruler_ai.get_ruler_state(kid)
	assert_not_null(new_state, "New ruler should have RulerState")
	assert_eq(new_state.ruler_character_id, k.ruler_character_id)

	# Verify the new ruler can evaluate rules (doesn't crash)
	var rule := SocietyAIRule.new()
	rule.id = &"test:succ_rule"
	rule.priority = 100
	rule.condition = "true"
	rule.action_kind = &"adjust_tax_level"
	rule.action_params = {"delta": 5}
	rule.cooldown_days = 1
	_ruler_ai._rules_baseline = [rule]
	var runner: RuleListRunner = _ruler_ai.get_runner(kid)
	if runner != null:
		runner.ensure_rule_state(rule.id)
	_ruler_ai._evaluate_ruler(kid, 600)
	assert_eq(new_state.recent_decisions.size(), 1, "New ruler should make decisions")

	eb.unsubscribe(sub)

	# Restore old ruler (so other tests aren't affected)
	k.ruler_character_id = old_ruler_id
	ir.set_character_death_day(old_ruler_id, -1)
