extends GutTest
## Integration scenario: the Veil dispatches schemes autonomously over several years.

var _action: Action
var _chain: Chain
var _ai: SocietyAI


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
	if is_instance_valid(_ai) and _ai._tick_sub:
		eb.unsubscribe(_ai._tick_sub)
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


func test_veil_dispatches_over_five_years():
	# Verify rules loaded
	assert_true(_ai._rules_by_society.has(&"the_veil"))
	assert_eq(_ai._rules_by_society[&"the_veil"].size(), 12)

	var veil_id: StringName = _ai._get_society_immortal_id(&"the_veil")
	assert_ne(veil_id, &"", "Veil should have an immortal")

	# Advance 1825 days (5 years), evaluating rules each day
	var total_dispatched: int = 0
	var max_concurrent: int = 0
	for day in range(1, 1826):
		_ai._evaluate_society_rules(&"the_veil", day)
		_chain._advance_schemes(day)
		var active: Array = _action.get_active_schemes(veil_id)
		if active.size() > max_concurrent:
			max_concurrent = active.size()
		# Count resolved schemes
		total_dispatched = _ai._rule_state.values().reduce(
			func(acc, s): return acc + s.get("times_fired", 0), 0)

	assert_gt(total_dispatched, 1, "Veil should have dispatched at least some schemes over 5 years")
	assert_lte(max_concurrent, SocietyAI.MAX_CONCURRENT_SCHEMES_PER_SOCIETY,
		"Should never exceed concurrent scheme cap")

	# All Veil schemes should target real places
	for scheme: SchemeRecord in _action.get_active_schemes(veil_id):
		assert_ne(scheme.target_place_ref, &"", "Scheme should have a target place")
