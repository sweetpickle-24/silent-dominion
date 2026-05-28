extends GutTest

# Integration: a player chain member dies of old age → CharacterDiedEvent fires
# → chain-break handling (the Chain mechanic checks is_alive and reacts).

var _mortality: Mortality


func before_each():
	_mortality = Mortality.new()
	_mortality.name = "Mortality"
	add_child(_mortality)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_mortality):
		if _mortality._tick_sub:
			eb.unsubscribe(_mortality._tick_sub)
		remove_child(_mortality)
		_mortality.free()


func test_chain_member_death_flow():
	var ir: Node = get_node("/root/ImmortalRegistry")
	# Find a chain member (non-immortal, alive, with chain_status)
	var target_id: StringName = &""
	for cid: StringName in ir.all_character_ids():
		var c: CharacterRecord = ir.get_character(cid)
		if c != null and c.is_alive(0) and c.chain_status != ChainStatusValues.NONE and not ir.is_immortal(cid):
			target_id = cid
			break
	if target_id == &"":
		pending("No mortal chain members available")
		return

	var target: CharacterRecord = ir.get_character(target_id)
	var original_status: StringName = target.chain_status

	# Collect events
	var events: Array = []
	var eb: Node = get_node("/root/EventBus")
	var sub = eb.subscribe(
		preload("res://scripts/data/events/character_died_event.gd"),
		func(e): events.append(e),
		50,
	)

	# Kill the chain member
	_mortality.kill_character_by_cause(target_id, &"old_age", 100)

	# Verify death
	assert_false(target.is_alive(101), "Character should be dead")
	assert_eq(events.size(), 1, "CharacterDiedEvent should fire")
	assert_true(events[0].was_chain_member, "Event should mark chain member")
	assert_eq(events[0].chain_status, original_status)

	eb.unsubscribe(sub)
	# Restore for other tests
	ir.set_character_death_day(target_id, -1)
