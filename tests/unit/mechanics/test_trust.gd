extends GutTest

var _ir: Node

func before_each():
	_ir = get_node("/root/ImmortalRegistry")

func test_trust_gain_on_success():
	var theron: CharacterRecord = _ir.get_character(&"theron")
	var before: int = theron.trust_score
	theron.trust_score = clampi(theron.trust_score + Trust.TRUST_GAIN_PER_SUCCESS, 0, 100)
	assert_eq(theron.trust_score, before + Trust.TRUST_GAIN_PER_SUCCESS)
	theron.trust_score = before  # restore

func test_trust_loss_asymmetric():
	assert_gt(Trust.TRUST_LOSS_PER_FAILURE, Trust.TRUST_GAIN_PER_SUCCESS, "Loss should exceed gain")

func test_trust_clamped():
	var ch := CharacterRecord.new()
	ch.trust_score = 99
	ch.trust_score = clampi(ch.trust_score + Trust.TRUST_GAIN_PER_SUCCESS, 0, 100)
	assert_eq(ch.trust_score, 100)
	ch.trust_score = 2
	ch.trust_score = clampi(ch.trust_score - Trust.TRUST_LOSS_PER_FAILURE, 0, 100)
	assert_eq(ch.trust_score, 0)

func test_trust_decay_threshold():
	assert_eq(Trust.TRUST_DECAY_THRESHOLD_DAYS, 365)
	assert_eq(Trust.TRUST_DECAY_PER_YEAR, 5)

func test_save_load_roundtrip():
	var trust := Trust.new()
	trust.name = "Trust"
	add_child(trust)
	trust._last_contact_day[&"test_char"] = 500
	var state: Dictionary = trust.snapshot_state()
	trust._last_contact_day.clear()
	trust.apply_state(state)
	assert_eq(trust._last_contact_day.get(&"test_char"), 500)
	remove_child(trust); trust.free()
