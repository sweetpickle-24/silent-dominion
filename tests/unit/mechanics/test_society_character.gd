extends GutTest

var _sc: SocietyCharacter
var _action: Action
var _chain: Chain
var _disposition_events: Array = []
var _disp_sub


func _tick_until_resolved(scheme: SchemeRecord, max_days: int = 500) -> void:
	for day in range(1, max_days + 1):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.RESOLVED or scheme.outcome == &"cancelled":
			return


func before_each():
	_action = Action.new()
	_action.name = "Action"
	add_child(_action)
	_chain = Chain.new()
	_chain.name = "Chain"
	add_child(_chain)
	_sc = SocietyCharacter.new()
	_sc.name = "SocietyCharacter"
	add_child(_sc)
	_disposition_events.clear()
	var eb: Node = get_node("/root/EventBus")
	_disp_sub = eb.subscribe(
		preload("res://scripts/data/events/disposition_rule_fired_event.gd"),
		func(e): _disposition_events.append(e), 999)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if _disp_sub:
		eb.unsubscribe(_disp_sub)
		_disp_sub = null
	if is_instance_valid(_action) and _action._phase_advanced_sub:
		eb.unsubscribe(_action._phase_advanced_sub)
	if is_instance_valid(_action) and _action._cancelled_sub:
		eb.unsubscribe(_action._cancelled_sub)
	if is_instance_valid(_chain) and _chain._tick_subscription:
		eb.unsubscribe(_chain._tick_subscription)
	if is_instance_valid(_sc) and _sc._scheme_resolved_sub:
		eb.unsubscribe(_sc._scheme_resolved_sub)
	for node in [_sc, _chain, _action]:
		if is_instance_valid(node):
			remove_child(node)
			node.free()


func test_loads_veil():
	var veil: SocietyCharacterRecord = _sc.get_society(&"the_veil")
	assert_not_null(veil)
	assert_eq(veil.display_name, "The Veil")
	assert_eq(veil.disposition_baseline, 20)
	assert_eq(veil.disposition_modifier_rules.size(), 2)


func test_baseline_disposition():
	assert_eq(_sc.get_disposition(&"the_veil", &"player"), 20)


func test_corrupt_library_drops_disposition():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.CORRUPT_INSTITUTION, &"test_library", &"test_library")
	_tick_until_resolved(scheme)
	assert_eq(scheme.current_phase, SchemePhases.RESOLVED)
	assert_eq(_sc.get_disposition(&"the_veil", &"player"), -60)
	assert_eq(_disposition_events.size(), 1)
	assert_eq(_disposition_events[0].rule_id, &"veil_protects_libraries")
	assert_eq(_disposition_events[0].base_delta, -80)


func test_observe_does_not_fire_rules():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.OBSERVE, &"test_library", &"test_library")
	_tick_until_resolved(scheme)
	assert_eq(_sc.get_disposition(&"the_veil", &"player"), 20)
	assert_eq(_disposition_events.size(), 0)


func test_save_load_roundtrip():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.CORRUPT_INSTITUTION, &"test_library", &"test_library")
	_tick_until_resolved(scheme)
	assert_eq(_sc.get_disposition(&"the_veil", &"player"), -60)
	var state: Dictionary = _sc.snapshot_state()
	_sc.apply_state({})
	_sc.apply_state(state)
	assert_eq(_sc.get_disposition(&"the_veil", &"player"), -60)
