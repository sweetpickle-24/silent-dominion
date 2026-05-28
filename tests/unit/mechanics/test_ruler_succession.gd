extends GutTest

var _kingdom: Kingdom
var _ruler_ai: RulerAI
var _mortality: Mortality


func before_each():
	_kingdom = Kingdom.new()
	_kingdom.name = "Kingdom"
	add_child(_kingdom)
	_ruler_ai = RulerAI.new()
	_ruler_ai.name = "RulerAI"
	add_child(_ruler_ai)
	_mortality = Mortality.new()
	_mortality.name = "Mortality"
	add_child(_mortality)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_ruler_ai):
		if _ruler_ai._tick_sub:
			eb.unsubscribe(_ruler_ai._tick_sub)
		for sub in _ruler_ai._reactive_subs:
			eb.unsubscribe(sub)
		remove_child(_ruler_ai)
		_ruler_ai.free()
	if is_instance_valid(_kingdom):
		if _kingdom._tick_sub:
			eb.unsubscribe(_kingdom._tick_sub)
		remove_child(_kingdom)
		_kingdom.free()
	if is_instance_valid(_mortality):
		if _mortality._tick_sub:
			eb.unsubscribe(_mortality._tick_sub)
		remove_child(_mortality)
		_mortality.free()


func _setup_test_kingdom() -> KingdomRecord:
	var k := KingdomRecord.new()
	k.id = &"succ_test"
	k.display_name = "Succession Test Kingdom"
	k.ruler_character_id = &"ruler_athens"
	k.capital_place_id = &"athens"
	k.member_place_ids = [&"athens"]
	k.tax_level = 40
	k.legitimacy = 70
	k.standing_army = 50
	_kingdom._kingdoms[&"succ_test"] = k
	_kingdom._place_to_kingdom[&"athens"] = &"succ_test"
	_ruler_ai._ensure_ruler_state(&"succ_test")
	return k


func test_ruler_death_triggers_succession():
	var k := _setup_test_kingdom()
	var events: Array = []
	var eb: Node = get_node("/root/EventBus")
	var sub = eb.subscribe(
		preload("res://scripts/data/events/ruler_succeeded_event.gd"),
		func(e): events.append(e),
		50,
	)
	# Kill the ruler
	var death_event := CharacterDiedEvent.new()
	death_event.character_id = &"ruler_athens"
	death_event.was_ruler = true
	death_event.kingdom_id = &"succ_test"
	death_event.day = 100
	_ruler_ai._on_character_died(death_event)
	assert_eq(events.size(), 1, "RulerSucceededEvent should fire")
	assert_eq(events[0].kingdom_id, &"succ_test")
	assert_ne(events[0].new_ruler_id, &"ruler_athens", "New ruler should differ from dead one")
	assert_ne(k.ruler_character_id, &"ruler_athens", "Kingdom should have new ruler")
	eb.unsubscribe(sub)


func test_succession_legitimacy_hit():
	var k := _setup_test_kingdom()
	var initial_leg: int = k.legitimacy
	var death_event := CharacterDiedEvent.new()
	death_event.character_id = &"ruler_athens"
	death_event.was_ruler = true
	death_event.kingdom_id = &"succ_test"
	death_event.day = 100
	_ruler_ai._on_character_died(death_event)
	assert_lt(k.legitimacy, initial_leg, "Succession should reduce legitimacy")


func test_successor_gets_new_ruler_state():
	var k := _setup_test_kingdom()
	var death_event := CharacterDiedEvent.new()
	death_event.character_id = &"ruler_athens"
	death_event.was_ruler = true
	death_event.kingdom_id = &"succ_test"
	death_event.day = 100
	_ruler_ai._on_character_died(death_event)
	var new_state: RulerState = _ruler_ai.get_ruler_state(&"succ_test")
	assert_not_null(new_state, "New RulerState should exist")
	assert_eq(new_state.ruler_character_id, k.ruler_character_id)
	assert_eq(new_state.recent_decisions.size(), 0, "Fresh ruler has no decisions")


func test_successor_traits_influenced_by_dominant_faction():
	var k := _setup_test_kingdom()
	k.faction_military = 50
	k.faction_clergy = 10
	k.faction_merchants = 20
	k.faction_nobility = 20
	assert_eq(k.dominant_faction(), &"military")
	var successor: CharacterRecord = _ruler_ai._generate_successor(k, 100)
	assert_gt(successor.ambition, 50, "Military faction successor should have higher ambition")
	assert_gt(successor.ruthlessness, 50, "Military faction successor should have higher ruthlessness")


func test_successor_registered_in_immortal_registry():
	var k := _setup_test_kingdom()
	var ir: Node = get_node("/root/ImmortalRegistry")
	var death_event := CharacterDiedEvent.new()
	death_event.character_id = &"ruler_athens"
	death_event.was_ruler = true
	death_event.kingdom_id = &"succ_test"
	death_event.day = 9999  # unique day to avoid ID collision with other tests
	_ruler_ai._on_character_died(death_event)
	# Verify the new ruler exists in the registry
	var new_ruler: CharacterRecord = ir.get_character_record_any(k.ruler_character_id)
	assert_not_null(new_ruler, "New ruler should be registered in ImmortalRegistry")
	# Verify the new ruler exists
	var new_ruler: CharacterRecord = ir.get_character_record_any(k.ruler_character_id)
	assert_not_null(new_ruler)


func test_non_ruler_death_does_not_trigger_succession():
	var k := _setup_test_kingdom()
	var old_ruler: StringName = k.ruler_character_id
	# A non-ruler dies
	var death_event := CharacterDiedEvent.new()
	death_event.character_id = &"theron"
	death_event.was_ruler = false
	death_event.kingdom_id = &""
	death_event.day = 100
	_ruler_ai._on_character_died(death_event)
	assert_eq(k.ruler_character_id, old_ruler, "Non-ruler death should not change ruler")
