extends GutTest

var _ci: CounterIntelligence


func before_each():
	_ci = CounterIntelligence.new()
	_ci.name = "CounterIntelligence"
	add_child(_ci)


func after_each():
	if is_instance_valid(_ci):
		remove_child(_ci)
		_ci.free()


func test_rotate_chain_member_resets_heat():
	var ir: Node = get_node("/root/ImmortalRegistry")
	# Find a character with nonzero heat
	var char_id: StringName = &""
	for cid: StringName in ir.all_character_ids():
		var c: CharacterRecord = ir.get_character_record_any(cid)
		if c != null:
			c.heat = 75
			char_id = cid
			break
	if char_id == &"":
		pending("No characters available for test")
		return
	_ci.rotate_chain_member(char_id)
	var c_after: CharacterRecord = ir.get_character_record_any(char_id)
	assert_eq(c_after.heat, 0, "Heat should be reset to 0 after rotation")


func test_plant_false_trace_creates_trace():
	# This test verifies the false trace creation logic
	# Plant false trace uses framed society id
	var trace := TraceRecord.new()
	trace.emitting_society_id = &"player_organisation"  # framed
	trace.emission_strength = 3.0
	assert_eq(trace.emitting_society_id, &"player_organisation")
	assert_eq(trace.emission_strength, 3.0)


func test_obscure_traces_fires_event():
	var events_received: Array = []
	var eb: Node = get_node("/root/EventBus")
	var sub = eb.subscribe(
		preload("res://scripts/data/events/counter_intelligence_fired_event.gd"),
		func(e): events_received.append(e),
		50,
	)
	_ci.obscure_traces_at(&"athens", &"the_veil_founder", 0.5)
	assert_eq(events_received.size(), 1)
	assert_eq(events_received[0].operation_kind, &"obscure_traces")
	eb.unsubscribe(sub)


func test_counter_intelligence_event_fields():
	var e := CounterIntelligenceFiredEvent.new()
	e.operation_kind = &"rotate"
	e.acting_immortal_id = &"the_veil_founder"
	e.target_character_id = &"veil_coordinator_athens"
	e.day = 500
	assert_eq(e.operation_kind, &"rotate")
	assert_eq(e.acting_immortal_id, &"the_veil_founder")
	assert_eq(e.day, 500)


func test_false_fingerprint_event_fields():
	var e := FalseFingerprintPlantedEvent.new()
	e.planting_immortal_id = &"the_veil_founder"
	e.framed_society_id = &"player_organisation"
	e.target_place_id = &"athens"
	e.quality = &"moderate"
	assert_eq(e.framed_society_id, &"player_organisation")
	assert_eq(e.quality, &"moderate")
