extends GutTest

var _action: Action
var _chain: Chain
var _phase_events: Array = []
var _phase_sub


func _tick_until_resolved(scheme: SchemeRecord, max_days: int = 500) -> void:
	for day in range(1, max_days + 1):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.RESOLVED or scheme.outcome == &"cancelled":
			return


func _tick_until_phase(scheme: SchemeRecord, target_phase: StringName, max_days: int = 500) -> void:
	for day in range(1, max_days + 1):
		_chain._advance_schemes(day)
		if scheme.current_phase == target_phase:
			return


func before_each():
	_action = Action.new()
	_action.name = "Action"
	add_child(_action)
	_chain = Chain.new()
	_chain.name = "Chain"
	add_child(_chain)
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
	if is_instance_valid(_action):
		if _action._phase_advanced_sub:
			eb.unsubscribe(_action._phase_advanced_sub)
		if _action._cancelled_sub:
			eb.unsubscribe(_action._cancelled_sub)
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
		ActionTypeValues.PLANT_IDEA, &"athens", &"athens")
	# Day 0 dispatch. Day 0 advance — 0 days in phase, shouldn't advance.
	_chain._advance_schemes(0)
	assert_eq(scheme.current_phase, SchemePhases.DISPATCHED)


func test_advances_through_all_phases():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.PLANT_IDEA, &"athens", &"athens")
	_tick_until_resolved(scheme)
	assert_eq(scheme.current_phase, SchemePhases.RESOLVED)
	assert_eq(scheme.outcome, SchemeOutcomes.SUCCESS)
	# Phase events should have fired for each transition
	assert_true(_phase_events.size() >= 4, "Should have at least 4 phase transitions")


func test_correct_phase_sequence():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.PLANT_IDEA, &"athens", &"athens")
	_tick_until_phase(scheme, SchemePhases.ACKNOWLEDGED)
	assert_eq(scheme.current_phase, SchemePhases.ACKNOWLEDGED)
	_tick_until_phase(scheme, SchemePhases.ROUTING)
	assert_eq(scheme.current_phase, SchemePhases.ROUTING)
	_tick_until_phase(scheme, SchemePhases.EXECUTING)
	assert_eq(scheme.current_phase, SchemePhases.EXECUTING)
	_tick_until_resolved(scheme)
	assert_eq(scheme.current_phase, SchemePhases.RESOLVED)


func test_resolved_scheme_not_advanced():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.PLANT_IDEA, &"athens", &"athens")
	_tick_until_resolved(scheme)
	_phase_events.clear()
	_chain._advance_schemes(999)
	assert_eq(_phase_events.size(), 0)


func test_lieutenant_assigned():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.PLANT_IDEA, &"athens", &"athens")
	_tick_until_phase(scheme, SchemePhases.ACKNOWLEDGED)
	assert_ne(scheme.assigned_lieutenant_id, &"", "Lieutenant should be assigned")


func test_full_lifecycle():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.SEED_RUMOR, &"athens", &"athens")
	assert_eq(_action.get_active_schemes().size(), 1)
	_tick_until_resolved(scheme)
	assert_eq(_action.get_active_schemes().size(), 0)
	assert_eq(scheme.outcome, SchemeOutcomes.SUCCESS)
