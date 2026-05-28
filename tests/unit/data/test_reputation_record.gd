extends GutTest

func test_defaults():
	var r := ReputationRecord.new()
	assert_eq(r.reputation_score, 50)
	assert_eq(r.treaties_honoured, 0)
	assert_eq(r.treaties_broken, 0)

func test_apply_delta():
	var r := ReputationRecord.new()
	r.immortal_id = &"player"
	r.apply_delta(10, 100, "treaty signed")
	assert_eq(r.reputation_score, 60)
	assert_eq(r.events.size(), 1)
	assert_eq(r.events[0]["delta"], 10)

func test_reputation_clamped():
	var r := ReputationRecord.new()
	r.reputation_score = 95
	r.apply_delta(20, 100, "huge bonus")
	assert_eq(r.reputation_score, 100)
	r.apply_delta(-200, 200, "catastrophe")
	assert_eq(r.reputation_score, 0)
