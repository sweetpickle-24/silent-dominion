extends GutTest

var _action: Action
var _chain: Chain
var _trace: TraceMechanic

func before_each():
	_action = Action.new(); _action.name = "Action"; add_child(_action)
	_chain = Chain.new(); _chain.name = "Chain"; add_child(_chain)
	_trace = TraceMechanic.new(); _trace.name = "Trace"; add_child(_trace)

func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_action):
		if _action._phase_advanced_sub: eb.unsubscribe(_action._phase_advanced_sub)
		if _action._cancelled_sub: eb.unsubscribe(_action._cancelled_sub)
	if is_instance_valid(_chain) and _chain._tick_subscription:
		eb.unsubscribe(_chain._tick_subscription)
	for node in [_trace, _chain, _action]:
		if is_instance_valid(node): remove_child(node); node.free()

func test_scheme_resolved_emits_trace():
	var scheme: SchemeRecord = _action.dispatch(&"observe", &"athens", &"athens")
	for day in range(1, 500):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.RESOLVED: break
	var traces: Array = _trace.get_traces_at_place(&"athens")
	assert_gt(traces.size(), 0, "Trace should be emitted at target place")
	assert_eq(traces[0].emitting_society_id, &"player_organisation")

func test_trace_expires_after_730_days():
	var scheme: SchemeRecord = _action.dispatch(&"observe", &"athens", &"athens")
	for day in range(1, 500):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.RESOLVED: break
	# Prune at day 800 — trace should still exist (730 days from emission)
	var resolve_day: int = scheme.resolved_at_day
	var event := GameDayTickedEvent.new()
	event.day = resolve_day + 731
	_trace._on_game_day_ticked(event)
	var traces: Array = _trace.get_traces_at_place(&"athens")
	assert_eq(traces.size(), 0, "Trace should expire after 730 days")

func test_get_all_traces_for_society():
	var scheme: SchemeRecord = _action.dispatch(&"observe", &"athens", &"athens")
	for day in range(1, 500):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.RESOLVED: break
	var all_traces: Array = _trace.get_all_traces_for_society(&"player_organisation", scheme.resolved_at_day)
	assert_gt(all_traces.size(), 0)

func test_save_load_roundtrip():
	var scheme: SchemeRecord = _action.dispatch(&"observe", &"athens", &"athens")
	for day in range(1, 500):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.RESOLVED: break
	var state: Dictionary = _trace.snapshot_state()
	_trace._traces_by_place.clear()
	assert_eq(_trace.get_traces_at_place(&"athens").size(), 0)
	_trace.apply_state(state)
	assert_gt(_trace.get_traces_at_place(&"athens").size(), 0)
