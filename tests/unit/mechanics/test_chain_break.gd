extends GutTest

var _action: Action
var _chain: Chain
var _cancelled_events: Array = []
var _cancelled_sub


func before_each():
	_action = Action.new()
	_action.name = "Action"
	add_child(_action)
	_chain = Chain.new()
	_chain.name = "Chain"
	add_child(_chain)
	_cancelled_events.clear()
	var eb: Node = get_node("/root/EventBus")
	_cancelled_sub = eb.subscribe(
		preload("res://scripts/data/events/scheme_cancelled_event.gd"),
		func(e): _cancelled_events.append(e), 999)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if _cancelled_sub:
		eb.unsubscribe(_cancelled_sub)
		_cancelled_sub = null
	if is_instance_valid(_action):
		if _action._phase_advanced_sub:
			eb.unsubscribe(_action._phase_advanced_sub)
		if _action._cancelled_sub:
			eb.unsubscribe(_action._cancelled_sub)
	if is_instance_valid(_chain) and _chain._tick_subscription:
		eb.unsubscribe(_chain._tick_subscription)
	# Restore any killed characters
	var ir: Node = get_node("/root/ImmortalRegistry")
	for cid: StringName in ir.all_character_ids():
		var c: CharacterRecord = ir.get_character(cid)
		if c.death_day >= 0:
			c.death_day = -1
	if is_instance_valid(_chain):
		remove_child(_chain)
		_chain.free()
	if is_instance_valid(_action):
		remove_child(_action)
		_action.free()


func test_debug_kill_marks_dead():
	var ir: Node = get_node("/root/ImmortalRegistry")
	var theron: CharacterRecord = ir.get_character(&"theron")
	assert_true(theron.is_alive(0))
	_chain.debug_kill_character(&"theron", 5)
	assert_false(theron.is_alive(5))
	# Restore
	theron.death_day = -1


func test_chain_break_with_replacement():
	# Dispatch and advance to executing (operative assigned). We have 2 operatives
	# (Lykia and Sosthenes), so killing one should allow reassignment to the other.
	var scheme: SchemeRecord = _action.dispatch(ActionTypeValues.PLANT_IDEA, &"athens", &"athens")
	for day in range(1, 200):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.EXECUTING:
			break
	assert_eq(scheme.current_phase, SchemePhases.EXECUTING)
	var original_operative: StringName = scheme.assigned_operative_id
	assert_ne(original_operative, &"")

	# Kill the assigned operative
	var kill_day: int = scheme.current_phase_entered_at_day + 1
	_chain.debug_kill_character(original_operative, kill_day)

	# Chain-break check should detect dead operative and reassign to the other
	_chain._check_chain_breaks(kill_day + 1)

	# Should have been reassigned, not cancelled
	assert_eq(_cancelled_events.size(), 0, "Should reassign, not cancel")
	assert_ne(scheme.assigned_operative_id, original_operative, "Should have new operative")


func test_chain_break_cancels_when_no_replacement():
	# Dispatch and advance to acknowledged (lieutenant assigned = theron)
	var scheme: SchemeRecord = _action.dispatch(ActionTypeValues.PLANT_IDEA, &"athens", &"athens")
	for day in range(1, 100):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.ACKNOWLEDGED:
			break
	assert_eq(scheme.current_phase, SchemePhases.ACKNOWLEDGED)
	assert_eq(scheme.assigned_lieutenant_id, &"theron")

	# Kill Theron — he's the only lieutenant
	_chain.debug_kill_character(&"theron", 50)
	_chain._check_chain_breaks(51)

	# No replacement lieutenant → scheme cancelled
	assert_eq(_cancelled_events.size(), 1)
	assert_eq(_cancelled_events[0].reason, &"chain_break")
	assert_eq(_cancelled_events[0].scheme_id, scheme.id)
	# Scheme should be removed from active
	assert_eq(_action.get_active_schemes().size(), 0)
