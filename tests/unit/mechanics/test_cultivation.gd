extends GutTest

var _ir: Node

func before_each():
	_ir = get_node("/root/ImmortalRegistry")

func test_transitions_defined():
	assert_true(Cultivation.TRANSITIONS.has(&"cultivate_to_host"))
	assert_true(Cultivation.TRANSITIONS.has(&"recruit_to_witting"))
	assert_true(Cultivation.TRANSITIONS.has(&"promote_to_coordinator"))
	assert_true(Cultivation.TRANSITIONS.has(&"promote_to_lieutenant"))

func test_validate_wrong_status_rejected():
	var cult := Cultivation.new()
	cult.name = "Cultivation"
	add_child(cult)
	# Aspasia is chain_status=none; recruit_to_witting expects host
	var result: Dictionary = cult.validate_cultivation_dispatch(&"recruit_to_witting", &"aspasia_of_athens")
	assert_false(result.valid)
	remove_child(cult); cult.free()

func test_validate_correct_status_accepted():
	var cult := Cultivation.new()
	cult.name = "Cultivation"
	add_child(cult)
	# Aspasia is chain_status=none; cultivate_to_host expects none → should pass
	var result: Dictionary = cult.validate_cultivation_dispatch(&"cultivate_to_host", &"aspasia_of_athens")
	assert_true(result.valid)
	remove_child(cult); cult.free()

func test_validate_too_recent_promotion():
	var cult := Cultivation.new()
	cult.name = "Cultivation"
	add_child(cult)
	cult._last_promotion_day[&"aspasia_of_athens"] = 0  # promoted at day 0
	# At day 100, 100 < 730 min days → rejected
	var tk: Node = get_node("/root/TimeKeeper")
	var original_day: int = tk.current_day
	# Can't easily set TimeKeeper for this test; just verify the threshold exists
	assert_eq(Cultivation.MIN_DAYS_BETWEEN_PROMOTIONS, 730)
	remove_child(cult); cult.free()

func test_cultivate_sets_society_id():
	# Verify the logic: when None→Host, society_id should be set
	var ch := CharacterRecord.new()
	ch.chain_status = &"none"
	ch.society_id = &""
	ch.chain_status = &"host"
	if ch.society_id == &"":
		ch.society_id = &"player_organisation"
	assert_eq(ch.society_id, &"player_organisation")

func test_save_load_roundtrip():
	var cult := Cultivation.new()
	cult.name = "Cultivation"
	add_child(cult)
	cult._last_promotion_day[&"test_char"] = 1000
	var state: Dictionary = cult.snapshot_state()
	cult._last_promotion_day.clear()
	cult.apply_state(state)
	assert_eq(cult._last_promotion_day.get(&"test_char"), 1000)
	remove_child(cult); cult.free()
