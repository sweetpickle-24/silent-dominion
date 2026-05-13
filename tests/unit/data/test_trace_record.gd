extends GutTest

func test_field_access():
	var t := TraceRecord.new()
	t.id = &"trace_1"
	t.emitting_society_id = &"the_veil"
	t.emission_strength = 3.5
	t.emitted_at_day = 100
	assert_eq(t.id, &"trace_1")
	assert_eq(t.emission_strength, 3.5)

func test_current_strength_decay():
	var t := TraceRecord.new()
	t.emission_strength = 10.0
	t.emitted_at_day = 0
	assert_eq(t.current_strength_at(0), 10.0)     # same day
	assert_eq(t.current_strength_at(364), 10.0)    # day 364: still full
	assert_eq(t.current_strength_at(365), 5.0)     # day 365: half
	assert_eq(t.current_strength_at(729), 5.0)     # day 729: still half
	assert_eq(t.current_strength_at(730), 0.0)     # day 730: expired

func test_save_load_roundtrip():
	var t := TraceRecord.new()
	t.id = &"roundtrip_trace"
	t.emitting_society_id = &"the_veil"
	t.emission_strength = 5.0
	t.emitted_at_day = 50
	var path := "user://test_trace_roundtrip.tres"
	ResourceSaver.save(t, path)
	var loaded: TraceRecord = ResourceLoader.load(path) as TraceRecord
	assert_not_null(loaded)
	assert_eq(loaded.emission_strength, 5.0)
	DirAccess.remove_absolute(path)
