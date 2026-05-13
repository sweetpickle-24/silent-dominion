extends GutTest

var _investigation: InvestigationMechanic
var _trace: TraceMechanic
var _fp: FingerprintMechanic

func before_each():
	_fp = FingerprintMechanic.new(); _fp.name = "Fingerprint"; add_child(_fp)
	_trace = TraceMechanic.new(); _trace.name = "Trace"; add_child(_trace)
	_investigation = InvestigationMechanic.new(); _investigation.name = "Investigation"; add_child(_investigation)

func after_each():
	for node in [_investigation, _trace, _fp]:
		if is_instance_valid(node): remove_child(node); node.free()

func _make_trace(place_id: StringName, society_id: StringName, strength: float, day: int) -> void:
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

func test_low_coverage_misses_faint_trace():
	_investigation.set_coverage(&"player", &"attica", 5)
	_make_trace(&"athens", &"the_veil", 0.5, 10)
	_investigation._process_investigator(&"player", 11)
	assert_eq(_investigation.get_detected_count(&"player", &"the_veil"), 0, "Low coverage should miss faint trace")

func test_high_coverage_detects_trace():
	_investigation.set_coverage(&"player", &"attica", 80)
	_make_trace(&"athens", &"the_veil", 15.0, 10)
	_investigation._process_investigator(&"player", 11)
	assert_gt(_investigation.get_detected_count(&"player", &"the_veil"), 0, "High coverage should detect loud trace")

func test_same_trace_counted_once():
	_investigation.set_coverage(&"player", &"attica", 80)
	_make_trace(&"athens", &"the_veil", 15.0, 10)
	_investigation._process_investigator(&"player", 11)
	_investigation._process_investigator(&"player", 12)
	assert_eq(_investigation.get_detected_count(&"player", &"the_veil"), 1, "Same trace counted once")

func test_detection_advances_fingerprint():
	_investigation.set_coverage(&"player", &"attica", 80)
	# Add enough traces to cross Level 1 threshold (5)
	for i in range(6):
		var t := TraceRecord.new()
		t.id = StringName("t_%d" % i)
		t.emitting_immortal_id = &"the_veil_founder"
		t.emitting_society_id = &"the_veil"
		t.target_place_id = &"athens"
		t.emission_strength = 15.0
		t.emitted_at_day = i * 10
		t.expires_at_day = t.emitted_at_day + 730
		if not _trace._traces_by_place.has(&"athens"):
			_trace._traces_by_place[&"athens"] = []
		_trace._traces_by_place[&"athens"].append(t)
	_investigation._process_investigator(&"player", 100)
	assert_gte(_fp.get_level(&"player", &"the_veil"), 1, "Should reach at least Level 1")

func test_save_load_roundtrip():
	_investigation.set_coverage(&"player", &"attica", 60)
	var state: Dictionary = _investigation.snapshot_state()
	assert_eq(_investigation.get_coverage(&"player", &"attica"), 60)
	_investigation._coverage.clear()
	_investigation.apply_state(state)
	assert_eq(_investigation.get_coverage(&"player", &"attica"), 60)
