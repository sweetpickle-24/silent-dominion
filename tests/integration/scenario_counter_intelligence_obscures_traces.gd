extends GutTest

# Integration: Veil's counter-intel fires when local heat is high;
# verify heat resets; event fires; false fingerprint creates trace.

var _ci: CounterIntelligence


func before_each():
	_ci = CounterIntelligence.new()
	_ci.name = "CounterIntelligence"
	add_child(_ci)


func after_each():
	if is_instance_valid(_ci):
		remove_child(_ci)
		_ci.free()


func test_counter_intel_rotate_resets_heat():
	var ir: Node = get_node("/root/ImmortalRegistry")
	var target_id: StringName = &""
	for cid: StringName in ir.all_character_ids():
		var c: CharacterRecord = ir.get_character_record_any(cid)
		if c != null and c.society_id == &"the_veil":
			c.heat = 80
			target_id = cid
			break
	if target_id == &"":
		pending("No Veil character for test")
		return
	# Rotate the character
	_ci.rotate_chain_member(target_id)
	var c: CharacterRecord = ir.get_character_record_any(target_id)
	assert_eq(c.heat, 0, "Heat should be 0 after rotation")


func test_counter_intel_obscure_fires_event():
	var events_received: Array = []
	var eb: Node = get_node("/root/EventBus")
	var sub = eb.subscribe(
		preload("res://scripts/data/events/counter_intelligence_fired_event.gd"),
		func(e): events_received.append(e),
		50,
	)
	_ci.obscure_traces_at(&"athens", &"the_veil_founder", 0.5)
	assert_eq(events_received.size(), 1, "Should fire CI event")
	assert_eq(events_received[0].operation_kind, &"obscure_traces")
	eb.unsubscribe(sub)


func test_false_fingerprint_fires_two_events():
	var ci_events: Array = []
	var fp_events: Array = []
	var eb: Node = get_node("/root/EventBus")
	var sub1 = eb.subscribe(
		preload("res://scripts/data/events/counter_intelligence_fired_event.gd"),
		func(e): ci_events.append(e),
		50,
	)
	var sub2 = eb.subscribe(
		preload("res://scripts/data/events/false_fingerprint_planted_event.gd"),
		func(e): fp_events.append(e),
		50,
	)
	_ci.plant_false_trace(&"corinth", &"player_organisation", &"observe", &"the_veil_founder")
	assert_eq(ci_events.size(), 1, "Should fire CI event")
	assert_eq(fp_events.size(), 1, "Should fire false fingerprint event")
	assert_eq(fp_events[0].framed_society_id, &"player_organisation")
	assert_eq(fp_events[0].quality, &"moderate")
	eb.unsubscribe(sub1)
	eb.unsubscribe(sub2)
