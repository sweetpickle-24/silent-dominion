extends GutTest
## Integration scenario: Veil dispatches a scheme and it flows through real chain hops.

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


func test_veil_scheme_resolves_through_chain():
	var veil_id: StringName = _ai._get_society_immortal_id(&"the_veil")
	assert_ne(veil_id, &"")

	# Dispatch a single Veil scheme directly
	var scheme: SchemeRecord = _action.dispatch(&"observe", &"athens", &"athens", veil_id)
	assert_not_null(scheme)
	assert_eq(scheme.immortal_id, veil_id)

	# Tick until resolved
	for day in range(1, 500):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.RESOLVED:
			break

	assert_eq(scheme.current_phase, SchemePhases.RESOLVED, "Veil scheme should resolve")
	assert_eq(scheme.outcome, SchemeOutcomes.SUCCESS)

	# Verify chain assignments were made
	# Lieutenant: the Veil founder acts as their own Lieutenant (fallback)
	assert_ne(scheme.assigned_lieutenant_id, &"", "Lieutenant should be assigned")
	# Coordinator: Aristion (only Veil coordinator)
	assert_eq(scheme.assigned_coordinator_id, &"veil_coordinator_athens",
		"Veil's only coordinator should be assigned")
	# Operative: one of the three Veil operatives
	assert_ne(scheme.assigned_operative_id, &"", "Operative should be assigned")
	var op_id: StringName = scheme.assigned_operative_id
	assert_true(op_id in [&"veil_operative_miletus", &"veil_operative_naucratis", &"veil_operative_memphis"],
		"Operative should be a Veil chain member")
