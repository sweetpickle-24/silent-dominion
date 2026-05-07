extends GutTest
## Integration scenario: real chain hops with member selection.
## Verifies that dispatching a scheme selects real chain members
## (Lieutenant, Coordinator, Operative) and resolves successfully.

var _action: Action
var _chain: Chain
var _memoirs: Memoirs
var _resolved_events: Array = []
var _resolved_sub


func before_each():
	_action = Action.new()
	_action.name = "Action"
	add_child(_action)
	_chain = Chain.new()
	_chain.name = "Chain"
	add_child(_chain)
	_memoirs = Memoirs.new()
	_memoirs.name = "Memoirs"
	add_child(_memoirs)
	_resolved_events.clear()
	var eb: Node = get_node("/root/EventBus")
	_resolved_sub = eb.subscribe(
		preload("res://scripts/data/events/scheme_resolved_event.gd"),
		func(e): _resolved_events.append(e), 999)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if _resolved_sub:
		eb.unsubscribe(_resolved_sub)
	if is_instance_valid(_action):
		if _action._phase_advanced_sub:
			eb.unsubscribe(_action._phase_advanced_sub)
		if _action._cancelled_sub:
			eb.unsubscribe(_action._cancelled_sub)
	if is_instance_valid(_chain) and _chain._tick_subscription:
		eb.unsubscribe(_chain._tick_subscription)
	if is_instance_valid(_memoirs):
		if _memoirs._tick_sub:
			eb.unsubscribe(_memoirs._tick_sub)
		if _memoirs._scheme_resolved_sub:
			eb.unsubscribe(_memoirs._scheme_resolved_sub)
		if _memoirs._era_transitioned_sub:
			eb.unsubscribe(_memoirs._era_transitioned_sub)
	for node in [_chain, _memoirs, _action]:
		if is_instance_valid(node):
			remove_child(node)
			node.free()


func test_full_chain_with_real_members():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.PLANT_IDEA, &"athens", &"athens")
	assert_not_null(scheme)

	# Tick until resolved
	for day in range(1, 500):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.RESOLVED:
			break

	assert_eq(scheme.current_phase, SchemePhases.RESOLVED)
	assert_eq(scheme.outcome, SchemeOutcomes.SUCCESS)

	# All three chain roles should have been assigned
	assert_ne(scheme.assigned_lieutenant_id, &"", "Lieutenant should be assigned")
	assert_ne(scheme.assigned_coordinator_id, &"", "Coordinator should be assigned")
	assert_ne(scheme.assigned_operative_id, &"", "Operative should be assigned")

	# Lieutenant should be Theron (only lieutenant)
	assert_eq(scheme.assigned_lieutenant_id, &"theron")

	# Coordinator should be Helena (only coordinator)
	assert_eq(scheme.assigned_coordinator_id, &"helena_of_athens")

	# SchemeResolvedEvent should have fired
	assert_eq(_resolved_events.size(), 1)

	# Memoirs should have learned a pattern
	var lib: MemoirsLibrary = _memoirs.get_library(&"player")
	assert_not_null(lib)
	assert_eq(lib.patterns.size(), 1)
	assert_eq(lib.patterns[0].category, PatternCategories.PLANT_IDEA)


func test_persian_target_selects_appropriate_operative():
	# Dispatch targeting Persepolis — Sosthenes (Miletus, speaks Persian) should
	# score higher than Lykia (Corinth, Greek only) for a Persian region target.
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.OBSERVE, &"persepolis", &"persepolis")

	for day in range(1, 500):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.RESOLVED:
			break

	assert_eq(scheme.current_phase, SchemePhases.RESOLVED)
	# Sosthenes speaks Persian and should score higher for a Persian target
	assert_eq(scheme.assigned_operative_id, &"sosthenes",
		"Sosthenes (Persian speaker) should be selected for Persepolis target")
