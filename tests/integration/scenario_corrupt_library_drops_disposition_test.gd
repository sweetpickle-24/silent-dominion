extends GutTest
## Integration scenario test: corrupting a library drops Veil disposition.
## Per architecture.md §8 step 8 and D1 integration test list.
##
## Verifies the full loop: player dispatches corrupt_institution targeting a library,
## scheme resolves, SocietyCharacter evaluates Veil's disposition rules,
## disposition drops, DispositionRuleFiredEvent fires with correct attribution.

var _action: Action
var _chain: Chain
var _memoirs: Memoirs
var _sc: SocietyCharacter

var _resolved_events: Array = []
var _disposition_events: Array = []
var _resolved_sub
var _disp_sub


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
	_sc = SocietyCharacter.new()
	_sc.name = "SocietyCharacter"
	add_child(_sc)

	_resolved_events.clear()
	_disposition_events.clear()
	var eb: Node = get_node("/root/EventBus")
	_resolved_sub = eb.subscribe(
		preload("res://scripts/data/events/scheme_resolved_event.gd"),
		func(e): _resolved_events.append(e), 999)
	_disp_sub = eb.subscribe(
		preload("res://scripts/data/events/disposition_rule_fired_event.gd"),
		func(e): _disposition_events.append(e), 999)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	for sub in [_resolved_sub, _disp_sub]:
		if sub:
			eb.unsubscribe(sub)
	if is_instance_valid(_action):
		if _action._phase_advanced_sub:
			eb.unsubscribe(_action._phase_advanced_sub)
		if _action._cancelled_sub:
			eb.unsubscribe(_action._cancelled_sub)
	if is_instance_valid(_chain) and _chain._tick_subscription:
		eb.unsubscribe(_chain._tick_subscription)
	if is_instance_valid(_sc) and _sc._scheme_resolved_sub:
		eb.unsubscribe(_sc._scheme_resolved_sub)
	if is_instance_valid(_memoirs):
		if _memoirs._tick_sub:
			eb.unsubscribe(_memoirs._tick_sub)
		if _memoirs._scheme_resolved_sub:
			eb.unsubscribe(_memoirs._scheme_resolved_sub)
	for node in [_sc, _chain, _memoirs, _action]:
		if is_instance_valid(node):
			remove_child(node)
			node.free()


func test_corrupt_library_drops_veil_disposition():
	# Verify initial disposition.
	var initial: int = _sc.get_disposition(&"the_veil", &"player")
	assert_eq(initial, 20, "Veil baseline disposition should be 20")

	# Dispatch corrupt_institution targeting the library fixture.
	_action.dispatch(
		ActionTypeValues.CORRUPT_INSTITUTION,
		&"test_library",
		&"test_library",
	)

	# Advance through all phases (variable timing with real chain selection).
	var scheme: SchemeRecord = _action.get_active_schemes()[0]
	for day in range(1, 500):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.RESOLVED:
			break

	# SchemeResolvedEvent should have fired.
	assert_eq(_resolved_events.size(), 1)
	assert_eq(_resolved_events[0].outcome, SchemeOutcomes.SUCCESS)

	# Exactly one DispositionRuleFiredEvent.
	assert_eq(_disposition_events.size(), 1)
	var de: DispositionRuleFiredEvent = _disposition_events[0]
	assert_eq(de.rule_id, &"veil_protects_libraries")
	assert_eq(de.source_society_id, &"the_veil")
	assert_eq(de.target_immortal_id, &"player")
	assert_eq(de.base_delta, -80)
	assert_eq(de.scaled_delta, -80)
	assert_eq(de.attribution_tag, &"veil_protects_libraries")

	# Final disposition: 20 + (-80) = -60.
	assert_eq(_sc.get_disposition(&"the_veil", &"player"), -60)
