extends GutTest
## Integration scenario test: scheme dispatch through chain hops.
## Per architecture.md §8 step 7 and D1 integration test list.
##
## Verifies the full Action -> Chain -> Action -> Memoirs loop:
## 1. Action.dispatch creates a scheme and fires SchemeDispatchedEvent
## 2. Chain advances phases on day-tick when timing thresholds are met
## 3. Action consumes SchemePhaseAdvanced and updates scheme state
## 4. When resolved, Action fires SchemeResolvedEvent
## 5. Memoirs consumes SchemeResolved and learns a new Pattern

var _action: Action
var _chain: Chain
var _memoirs: Memoirs

var _dispatched_events: Array = []
var _phase_events: Array = []
var _resolved_events: Array = []
var _dispatch_sub
var _phase_sub
var _resolved_sub


func before_each():
	# Build a minimal mechanic scene.
	_action = Action.new()
	_action.name = "Action"
	add_child(_action)

	_chain = Chain.new()
	_chain.name = "Chain"
	add_child(_chain)

	_memoirs = Memoirs.new()
	_memoirs.name = "Memoirs"
	add_child(_memoirs)

	_dispatched_events.clear()
	_phase_events.clear()
	_resolved_events.clear()

	var eb: Node = get_node("/root/EventBus")
	_dispatch_sub = eb.subscribe(
		preload("res://scripts/data/events/scheme_dispatched_event.gd"),
		func(e): _dispatched_events.append(e), 999)
	_phase_sub = eb.subscribe(
		preload("res://scripts/data/events/scheme_phase_advanced_event.gd"),
		func(e): _phase_events.append(e), 999)
	_resolved_sub = eb.subscribe(
		preload("res://scripts/data/events/scheme_resolved_event.gd"),
		func(e): _resolved_events.append(e), 999)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	for sub in [_dispatch_sub, _phase_sub, _resolved_sub]:
		if sub:
			eb.unsubscribe(sub)
	# Unsubscribe mechanic-internal subscriptions.
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


func test_full_scheme_lifecycle():
	# --- Day 0: Dispatch ---
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.PLANT_IDEA, &"athens", &"athens")
	assert_not_null(scheme)
	assert_eq(scheme.current_phase, SchemePhases.DISPATCHED)
	assert_eq(_dispatched_events.size(), 1)
	assert_eq(_dispatched_events[0].action_type, ActionTypeValues.PLANT_IDEA)

	# Verify scheme is active.
	assert_eq(_action.get_active_schemes().size(), 1)

	# Advance through all phases (variable timing with real chain selection).
	for day in range(1, 500):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.RESOLVED:
			break
	assert_eq(scheme.current_phase, SchemePhases.RESOLVED)

	# Verify SchemeResolvedEvent fired.
	assert_eq(_resolved_events.size(), 1)
	assert_eq(_resolved_events[0].outcome, SchemeOutcomes.SUCCESS)
	assert_eq(_resolved_events[0].action_type, ActionTypeValues.PLANT_IDEA)
	assert_eq(_resolved_events[0].target_ref, &"athens")

	# Scheme removed from active list.
	assert_eq(_action.get_active_schemes().size(), 0)

	# --- Memoirs learned a pattern ---
	var lib: MemoirsLibrary = _memoirs.get_library(&"player")
	assert_not_null(lib)
	assert_eq(lib.patterns.size(), 1)
	var learned: Pattern = lib.patterns[0]
	assert_eq(learned.category, PatternCategories.PLANT_IDEA)
	assert_eq(learned.region_scope, &"attica")  # from athens fixture
	assert_eq(learned.learned_from_event_id, scheme.id)
	assert_eq(learned.success_count, 1)
	assert_eq(learned.staleness_state, StalenessValues.FRESH)


func test_observe_does_not_learn():
	# Observe is intelligence gathering, not a manipulation pattern.
	var observe_scheme: SchemeRecord = _action.dispatch(ActionTypeValues.OBSERVE, &"delphi", &"delphi")
	for day in range(1, 500):
		_chain._advance_schemes(day)
		if observe_scheme.current_phase == SchemePhases.RESOLVED:
			break
	# Resolved but no pattern learned (observe maps to &"" category).
	var lib: MemoirsLibrary = _memoirs.get_library(&"player")
	assert_eq(lib.patterns.size(), 0)
