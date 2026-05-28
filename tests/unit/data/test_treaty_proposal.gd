extends GutTest

func test_field_access():
	var tp := TreatyProposal.new()
	tp.id = &"proposal_001"
	tp.proposer_immortal_id = &"player"
	tp.counterparty_immortal_id = &"the_veil_founder"
	tp.counterparty_society_id = &"the_veil"
	tp.stage = &"negotiation"
	tp.current_round = 2
	assert_eq(tp.proposer_immortal_id, &"player")
	assert_eq(tp.stage, &"negotiation")
	assert_eq(tp.current_round, 2)

func test_defaults():
	var tp := TreatyProposal.new()
	assert_eq(tp.stage, &"drafting")
	assert_eq(tp.current_round, 1)
	assert_eq(tp.max_rounds, 5)
	assert_eq(tp.signed_at_day, -1)
	assert_eq(tp.expires_at_day, -1)
	assert_eq(tp.terminated_at_day, -1)

func test_save_load_roundtrip():
	var tp := TreatyProposal.new()
	tp.id = &"roundtrip_proposal"
	tp.proposer_immortal_id = &"player"
	tp.stage = &"signed"
	tp.signed_at_day = 500
	var path := "user://test_treaty_proposal_roundtrip.tres"
	ResourceSaver.save(tp, path)
	var loaded: TreatyProposal = ResourceLoader.load(path) as TreatyProposal
	assert_not_null(loaded)
	assert_eq(loaded.stage, &"signed")
	assert_eq(loaded.signed_at_day, 500)
	DirAccess.remove_absolute(path)
