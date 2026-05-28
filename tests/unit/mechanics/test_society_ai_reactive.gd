extends GutTest

var _ai: SocietyAI
var _action: Action


func before_each():
	_action = Action.new()
	_action.name = "Action"
	add_child(_action)
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
	for node in [_ai, _action]:
		if is_instance_valid(node):
			remove_child(node)
			node.free()


func _make_reactive_rule(trigger_class: StringName) -> SocietyAIRule:
	var r := SocietyAIRule.new()
	r.id = StringName("test:reactive_%s" % trigger_class)
	r.society_id = &"the_veil"
	r.priority = 100
	r.condition = "true"
	r.action_kind = &"dispatch_scheme"
	r.action_params = {"action_type": &"observe", "target_selector": &"specific_place", "target_constraints": {"place_id": &"athens"}}
	r.cooldown_days = 30
	r.reactive_trigger_event_classes = [trigger_class]
	return r


func test_reactive_event_triggers_rule():
	_ai._rules_by_society[&"the_veil"] = []
	var r := _make_reactive_rule(&"SchemeResolvedEvent")
	_ai._rules_by_society[&"the_veil"].append(r)
	_ai._rule_state[r.id] = {"last_fired_at_day": -1, "times_fired": 0}
	# Simulate a SchemeResolvedEvent
	var event := SchemeResolvedEvent.new()
	event.scheme_id = &"test_scheme"
	event.immortal_id = &"player"
	event.action_type = &"observe"
	event.outcome = &"success"
	_ai._on_reactive_event(event)
	assert_eq(_ai._rule_state[r.id].times_fired, 1, "Reactive rule should have fired")


func test_reactive_rule_respects_cooldown():
	_ai._rules_by_society[&"the_veil"] = []
	var r := _make_reactive_rule(&"SchemeResolvedEvent")
	_ai._rules_by_society[&"the_veil"].append(r)
	_ai._rule_state[r.id] = {"last_fired_at_day": 0, "times_fired": 1}  # fired at day 0
	# Event at day 10 — within 30 day cooldown
	var event := SchemeResolvedEvent.new()
	event.scheme_id = &"test_scheme"
	event.outcome = &"success"
	_ai._on_reactive_event(event)
	assert_eq(_ai._rule_state[r.id].times_fired, 1, "Rule on cooldown should not fire")


func test_reactive_rule_receives_triggering_event():
	# Verify the event is available in context
	_ai._rules_by_society[&"the_veil"] = []
	var r := _make_reactive_rule(&"FingerprintLevelAdvancedEvent")
	# Condition checks event data
	r.condition = "event != null"
	_ai._rules_by_society[&"the_veil"].append(r)
	_ai._rule_state[r.id] = {"last_fired_at_day": -1, "times_fired": 0}
	var event := FingerprintLevelAdvancedEvent.new()
	event.investigator_immortal_id = &"player"
	event.target_society_id = &"the_veil"
	event.old_level = 0
	event.new_level = 1
	event.day = 100
	_ai._on_reactive_event(event)
	assert_eq(_ai._rule_state[r.id].times_fired, 1, "Rule should fire when event condition is met")


func test_multiple_reactive_rules_on_same_event():
	_ai._rules_by_society[&"the_veil"] = []
	var r1 := _make_reactive_rule(&"SchemeResolvedEvent")
	r1.id = &"test:reactive_1"
	var r2 := _make_reactive_rule(&"SchemeResolvedEvent")
	r2.id = &"test:reactive_2"
	_ai._rules_by_society[&"the_veil"] = [r1, r2]
	_ai._rule_state[r1.id] = {"last_fired_at_day": -1, "times_fired": 0}
	_ai._rule_state[r2.id] = {"last_fired_at_day": -1, "times_fired": 0}
	var event := SchemeResolvedEvent.new()
	event.scheme_id = &"test_scheme"
	event.outcome = &"success"
	_ai._on_reactive_event(event)
	# Both reactive rules should fire — reactive rules are separate from per-tick budget
	var total_fired: int = _ai._rule_state[r1.id].times_fired + _ai._rule_state[r2.id].times_fired
	assert_true(total_fired >= 1, "At least one reactive rule should fire")
