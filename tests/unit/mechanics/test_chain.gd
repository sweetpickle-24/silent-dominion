extends GutTest

var _action: Action
var _chain: Chain
var _phase_events: Array = []
var _phase_sub


func before_each():
	_action = Action.new()
	_action.name = "Action"
	add_child(_action)
	_chain = Chain.new()
	_chain.name = "Chain"
	add_child(_chain)
	# Chain._ready() calls get_node("../Action") — we need them as siblings.
	# Since they're both children of the test node, ../Action resolves.
	_phase_events.clear()
	var eb: Node = get_node("/root/EventBus")
	_phase_sub = eb.subscribe(
		preload("res://scripts/data/events/scheme_phase_advanced_event.gd"),
		func(e): _phase_events.append(e), 999)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if _phase_sub:
		eb.unsubscribe(_phase_sub)
		_phase_sub = null
	if is_instance_valid(_action) and _action._phase_advanced_sub:
		eb.unsubscribe(_action._phase_advanced_sub)
	if is_instance_valid(_chain) and _chain._tick_subscription:
		eb.unsubscribe(_chain._tick_subscription)
	if is_instance_valid(_chain):
		remove_child(_chain)
		_chain.free()
	if is_instance_valid(_action):
		remove_child(_action)
		_action.free()


func test_no_advance_mid_phase():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.PLANT_IDEA, &"target", &"place")
	# Day 1: only 1 day in dispatched phase (needs 2). No advance.
	_chain._advance_schemes(1)
	assert_eq(_phase_events.size(), 0)
	assert_eq(scheme.current_phase, SchemePhases.DISPATCHED)


func test_advance_at_threshold():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.PLANT_IDEA, &"target", &"place")
	# Day 2: 2 days in dispatched phase (threshold=2). Should advance.
	_chain._advance_schemes(2)
	assert_eq(_phase_events.size(), 1)
	assert_eq(_phase_events[0].old_phase, SchemePhases.DISPATCHED)
	assert_eq(_phase_events[0].new_phase, SchemePhases.ACKNOWLEDGED)


func test_correct_phase_sequence():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.PLANT_IDEA, &"target", &"place")
	# dispatched (day 0) -> acknowledged (day 2) -> routing (day 5) -> executing (day 10) -> resolved (day 30)
	_chain._advance_schemes(2)
	assert_eq(scheme.current_phase, SchemePhases.ACKNOWLEDGED)
	_chain._advance_schemes(5)
	assert_eq(scheme.current_phase, SchemePhases.ROUTING)
	_chain._advance_schemes(10)
	assert_eq(scheme.current_phase, SchemePhases.EXECUTING)
	_chain._advance_schemes(30)
	assert_eq(scheme.current_phase, SchemePhases.RESOLVED)


func test_resolved_scheme_not_advanced():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.PLANT_IDEA, &"target", &"place")
	# Run all the way to resolved.
	_chain._advance_schemes(2)
	_chain._advance_schemes(5)
	_chain._advance_schemes(10)
	_chain._advance_schemes(30)
	_phase_events.clear()
	# Now try again at day 31 — resolved scheme has no further transitions.
	# Scheme was already removed from active list by Action, so Chain sees nothing.
	_chain._advance_schemes(31)
	assert_eq(_phase_events.size(), 0)


func test_multiple_schemes_independent():
	var s1: SchemeRecord = _action.dispatch(
		ActionTypeValues.PLANT_IDEA, &"t1", &"p1")
	# Dispatch second scheme 1 day later (simulate by setting entered_at_day)
	var s2: SchemeRecord = _action.dispatch(
		ActionTypeValues.CULTIVATE, &"t2", &"p2")
	s2.current_phase_entered_at_day = 1  # simulates dispatch at day 1

	_chain._advance_schemes(2)
	# s1 dispatched at day 0, 2 days elapsed -> advances
	# s2 dispatched at day 1, 1 day elapsed -> does not advance
	assert_eq(s1.current_phase, SchemePhases.ACKNOWLEDGED)
	assert_eq(s2.current_phase, SchemePhases.DISPATCHED)

	_chain._advance_schemes(3)
	# s2 now has 2 days -> advances
	assert_eq(s2.current_phase, SchemePhases.ACKNOWLEDGED)


func test_full_30_day_lifecycle():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.SEED_RUMOR, &"athens", &"athens")
	var initial_active: int = _action.get_active_schemes().size()
	assert_eq(initial_active, 1)

	# Tick through all phases
	_chain._advance_schemes(2)   # dispatched -> acknowledged
	_chain._advance_schemes(5)   # acknowledged -> routing
	_chain._advance_schemes(10)  # routing -> executing
	_chain._advance_schemes(30)  # executing -> resolved

	# Scheme should be resolved and removed
	assert_eq(_action.get_active_schemes().size(), 0)
	assert_eq(scheme.outcome, SchemeOutcomes.SUCCESS)
	assert_eq(scheme.current_phase, SchemePhases.RESOLVED)
