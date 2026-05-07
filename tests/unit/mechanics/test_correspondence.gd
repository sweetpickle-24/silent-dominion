extends GutTest

var _action: Action
var _chain: Chain
var _inbox: Inbox
var _correspondence: Correspondence
var _letter_events: Array = []
var _letter_sub


func before_each():
	_action = Action.new()
	_action.name = "Action"
	add_child(_action)
	_chain = Chain.new()
	_chain.name = "Chain"
	add_child(_chain)
	_inbox = Inbox.new()
	_inbox.name = "Inbox"
	add_child(_inbox)
	_correspondence = Correspondence.new()
	_correspondence.name = "Letter"
	add_child(_correspondence)
	_letter_events.clear()
	var eb: Node = get_node("/root/EventBus")
	_letter_sub = eb.subscribe(
		preload("res://scripts/data/events/letter_arrived_in_inbox_event.gd"),
		func(e): _letter_events.append(e), 999)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if _letter_sub:
		eb.unsubscribe(_letter_sub)
		_letter_sub = null
	if is_instance_valid(_action):
		if _action._phase_advanced_sub:
			eb.unsubscribe(_action._phase_advanced_sub)
		if _action._cancelled_sub:
			eb.unsubscribe(_action._cancelled_sub)
	if is_instance_valid(_chain) and _chain._tick_subscription:
		eb.unsubscribe(_chain._tick_subscription)
	if is_instance_valid(_inbox) and _inbox._tick_subscription:
		eb.unsubscribe(_inbox._tick_subscription)
	for sub in _correspondence._subscriptions:
		eb.unsubscribe(sub)
	for node in [_correspondence, _inbox, _chain, _action]:
		if is_instance_valid(node):
			remove_child(node)
			node.free()


func test_templates_loaded():
	assert_gt(_correspondence._templates.size(), 0, "Should have loaded templates")


func test_era_transition_generates_letter():
	var event := EraTransitionedEvent.new()
	event.old_era = &"ancient"
	event.new_era = &"classical_collapse"
	event.transition_day = 255500
	event.description = "Test transition"
	_correspondence._on_era_transitioned(event)
	var active: Array = _inbox.get_active_letters()
	assert_eq(active.size(), 1, "Era transition should produce a letter")
	assert_eq(active[0].content_category, &"world_state")
	assert_eq(_letter_events.size(), 1)


func test_scheme_resolved_generates_letter():
	var scheme: SchemeRecord = _action.dispatch(
		ActionTypeValues.CORRUPT_INSTITUTION, &"athens", &"athens")
	for day in range(1, 500):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.RESOLVED:
			break
	# SchemeResolved should have generated a letter
	var letters: Array = _inbox.get_active_letters()
	var resolved_letters: Array = []
	for l: Letter in letters:
		if l.triggering_event_class == &"SchemeResolvedEvent":
			resolved_letters.append(l)
	assert_gt(resolved_letters.size(), 0, "Scheme resolution should produce a letter")


func test_small_disposition_delta_no_letter():
	# DispositionRuleFiredEvent with delta < 20 should NOT generate a letter
	var event := DispositionRuleFiredEvent.new()
	event.source_society_id = &"the_veil"
	event.target_immortal_id = &"player"
	event.scaled_delta = -10
	event.attribution_tag = &"test"
	_correspondence._on_disposition_rule_fired(event)
	var letters: Array = _inbox.get_active_letters()
	var disp_letters: Array = []
	for l: Letter in letters:
		if l.triggering_event_class == &"DispositionRuleFiredEvent":
			disp_letters.append(l)
	assert_eq(disp_letters.size(), 0, "Small delta should not produce letter")


func test_large_disposition_delta_generates_letter():
	var event := DispositionRuleFiredEvent.new()
	event.source_society_id = &"the_veil"
	event.target_immortal_id = &"player"
	event.scaled_delta = -80
	event.attribution_tag = &"veil_protects_libraries"
	_correspondence._on_disposition_rule_fired(event)
	var letters: Array = _inbox.get_active_letters()
	var disp_letters: Array = []
	for l: Letter in letters:
		if l.triggering_event_class == &"DispositionRuleFiredEvent":
			disp_letters.append(l)
	assert_gt(disp_letters.size(), 0, "Large delta should produce letter")


func test_fill_slots():
	var result: String = _correspondence._fill_slots("Hello {name}, day {day}.", {"name": "Theron", "day": "42"})
	assert_eq(result, "Hello Theron, day 42.")
