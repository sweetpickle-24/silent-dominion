extends GutTest

var _action: Action
var _dispatched_events: Array = []
var _resolved_events: Array = []
var _dispatch_sub
var _resolved_sub


func before_each():
	_action = Action.new()
	_action.name = "Action"
	add_child(_action)
	_dispatched_events.clear()
	_resolved_events.clear()
	var eb: Node = get_node("/root/EventBus")
	_dispatch_sub = eb.subscribe(
		preload("res://scripts/data/events/scheme_dispatched_event.gd"),
		func(e): _dispatched_events.append(e), 999)
	_resolved_sub = eb.subscribe(
		preload("res://scripts/data/events/scheme_resolved_event.gd"),
		func(e): _resolved_events.append(e), 999)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if _dispatch_sub:
		eb.unsubscribe(_dispatch_sub)
		_dispatch_sub = null
	if _resolved_sub:
		eb.unsubscribe(_resolved_sub)
		_resolved_sub = null
	# Unsubscribe Action's internal subscription before freeing.
	if is_instance_valid(_action) and _action._phase_advanced_sub:
		eb.unsubscribe(_action._phase_advanced_sub)
	if is_instance_valid(_action):
		remove_child(_action)
		_action.free()


func test_dispatch_creates_scheme():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.PLANT_IDEA, &"athens", &"athens")
	assert_not_null(scheme)
	assert_eq(scheme.current_phase, SchemePhases.DISPATCHED)
	assert_eq(scheme.action_type, ActionTypeValues.PLANT_IDEA)
	assert_eq(scheme.immortal_id, &"player")


func test_dispatch_fires_event():
	_action.dispatch(ActionTypeValues.SEED_RUMOR, &"athens", &"athens")
	assert_eq(_dispatched_events.size(), 1)
	assert_eq(_dispatched_events[0].action_type, ActionTypeValues.SEED_RUMOR)


func test_get_active_schemes():
	_action.dispatch(ActionTypeValues.OBSERVE, &"t1", &"t1")
	_action.dispatch(ActionTypeValues.CULTIVATE, &"t2", &"t2")
	var schemes: Array = _action.get_active_schemes()
	assert_eq(schemes.size(), 2)


func test_get_scheme_by_id():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.PLANT_IDEA, &"target", &"place")
	var found: SchemeRecord = _action.get_scheme(scheme.id)
	assert_eq(found, scheme)


func test_get_scheme_unknown_returns_null():
	assert_null(_action.get_scheme(&"nonexistent"))


func test_phase_advance_updates_scheme():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.PLANT_IDEA, &"target", &"place")
	var event := SchemePhaseAdvancedEvent.new()
	event.scheme_id = scheme.id
	event.immortal_id = &"player"
	event.old_phase = SchemePhases.DISPATCHED
	event.new_phase = SchemePhases.ACKNOWLEDGED
	event.days_in_old_phase = 2
	get_node("/root/EventBus").dispatch(event)
	assert_eq(scheme.current_phase, SchemePhases.ACKNOWLEDGED)
	assert_eq(scheme.phase_history.size(), 2)


func test_resolved_phase_fires_resolved_event():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.PLANT_IDEA, &"target", &"place")
	var event := SchemePhaseAdvancedEvent.new()
	event.scheme_id = scheme.id
	event.immortal_id = &"player"
	event.old_phase = SchemePhases.EXECUTING
	event.new_phase = SchemePhases.RESOLVED
	event.days_in_old_phase = 20
	get_node("/root/EventBus").dispatch(event)
	assert_eq(_resolved_events.size(), 1)
	assert_eq(_resolved_events[0].outcome, SchemeOutcomes.SUCCESS)


func test_resolved_removes_from_active():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.PLANT_IDEA, &"target", &"place")
	var event := SchemePhaseAdvancedEvent.new()
	event.scheme_id = scheme.id
	event.immortal_id = &"player"
	event.old_phase = SchemePhases.EXECUTING
	event.new_phase = SchemePhases.RESOLVED
	event.days_in_old_phase = 20
	get_node("/root/EventBus").dispatch(event)
	assert_eq(_action.get_active_schemes().size(), 0)


func test_save_load_roundtrip():
	_action.dispatch(ActionTypeValues.PLANT_IDEA, &"t1", &"p1")
	_action.dispatch(ActionTypeValues.CULTIVATE, &"t2", &"p2")
	var state: Dictionary = _action.snapshot_state()
	_action.apply_state({})
	assert_eq(_action.get_active_schemes().size(), 0)
	_action.apply_state(state)
	assert_eq(_action.get_active_schemes().size(), 2)
