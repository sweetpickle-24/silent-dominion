extends GutTest

var _trace: TraceMechanic

func before_each():
	_trace = TraceMechanic.new(); _trace.name = "Trace"; add_child(_trace)

func after_each():
	if is_instance_valid(_trace): remove_child(_trace); _trace.free()

func _add_trace(place_id: StringName, society_id: StringName, strength: float, day: int) -> void:
	var t := TraceRecord.new()
	t.id = StringName("test_trace_%d" % day)
	t.emitting_immortal_id = &"the_veil_founder"
	t.emitting_society_id = society_id
	t.target_place_id = place_id
	t.emission_strength = strength
	t.emitted_at_day = day
	t.expires_at_day = day + 730
	if not _trace._traces_by_place.has(place_id):
		_trace._traces_by_place[place_id] = []
	_trace._traces_by_place[place_id].append(t)

func test_trace_stored_at_place():
	_add_trace(&"athens", &"the_veil", 5.0, 10)
	var traces: Array = _trace.get_traces_at_place(&"athens")
	assert_eq(traces.size(), 1)
	assert_eq(traces[0].emitting_society_id, &"the_veil")

func test_trace_expires_after_730_days():
	_add_trace(&"athens", &"the_veil", 5.0, 0)
	var event := GameDayTickedEvent.new()
	event.day = 731
	_trace._on_game_day_ticked(event)
	assert_eq(_trace.get_traces_at_place(&"athens").size(), 0, "Trace should expire")

func test_trace_half_strength_after_365():
	_add_trace(&"athens", &"the_veil", 10.0, 0)
	var traces: Array = _trace.get_traces_at_place(&"athens")
	assert_eq(traces[0].current_strength_at(365), 5.0)

func test_get_all_traces_for_society():
	_add_trace(&"athens", &"the_veil", 5.0, 10)
	_add_trace(&"miletus", &"the_veil", 3.0, 20)
	_add_trace(&"athens", &"player_organisation", 2.0, 15)
	var veil_traces: Array = _trace.get_all_traces_for_society(&"the_veil", 50)
	assert_eq(veil_traces.size(), 2)

func test_save_load_roundtrip():
	_add_trace(&"athens", &"the_veil", 5.0, 10)
	var state: Dictionary = _trace.snapshot_state()
	_trace._traces_by_place.clear()
	assert_eq(_trace.get_traces_at_place(&"athens").size(), 0)
	_trace.apply_state(state)
	assert_eq(_trace.get_traces_at_place(&"athens").size(), 1)
