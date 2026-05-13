extends GutTest

var _fp: FingerprintMechanic
var _fp_events: Array = []
var _fc_events: Array = []
var _fp_sub
var _fc_sub

func before_each():
	_fp = FingerprintMechanic.new(); _fp.name = "Fingerprint"; add_child(_fp)
	_fp_events.clear(); _fc_events.clear()
	var eb: Node = get_node("/root/EventBus")
	_fp_sub = eb.subscribe(preload("res://scripts/data/events/fingerprint_level_advanced_event.gd"), func(e): _fp_events.append(e), 999)
	_fc_sub = eb.subscribe(preload("res://scripts/data/events/first_contact_event.gd"), func(e): _fc_events.append(e), 999)

func after_each():
	var eb: Node = get_node("/root/EventBus")
	if _fp_sub: eb.unsubscribe(_fp_sub)
	if _fc_sub: eb.unsubscribe(_fc_sub)
	if is_instance_valid(_fp): remove_child(_fp); _fp.free()

func test_get_level_default_zero():
	assert_eq(_fp.get_level(&"player", &"the_veil"), 0)

func test_advance_level_fires_event():
	_fp.advance_level(&"player", &"the_veil", 1, 100)
	assert_eq(_fp.get_level(&"player", &"the_veil"), 1)
	assert_eq(_fp_events.size(), 1)
	assert_eq(_fp_events[0].new_level, 1)

func test_advance_to_1_fires_first_contact():
	_fp.advance_level(&"player", &"the_veil", 1, 200)
	assert_eq(_fc_events.size(), 1)
	assert_eq(_fc_events[0].detected_society_id, &"the_veil")

func test_first_contact_fires_only_once():
	_fp.advance_level(&"player", &"the_veil", 1, 200)
	# Try again from other direction
	_fp.advance_level(&"the_veil_founder", &"player_organisation", 1, 300)
	# Should only fire once per pair
	assert_eq(_fc_events.size(), 1, "First contact should fire once per pair")

func test_save_load_roundtrip():
	_fp.advance_level(&"player", &"the_veil", 2, 500)
	var state: Dictionary = _fp.snapshot_state()
	_fp._fingerprints.clear()
	assert_eq(_fp.get_level(&"player", &"the_veil"), 0)
	_fp.apply_state(state)
	assert_eq(_fp.get_level(&"player", &"the_veil"), 2)
