extends GutTest

var _treaty: Treaty


func before_each():
	_treaty = Treaty.new()
	_treaty.name = "Treaty"
	add_child(_treaty)


func after_each():
	if is_instance_valid(_treaty):
		remove_child(_treaty)
		_treaty.free()


func _make_primitive(category: StringName, kind: StringName, direction: StringName = &"two_way", params: Dictionary = {}) -> TreatyPrimitive:
	var p := TreatyPrimitive.new()
	p.id = StringName("%s_%s" % [category, kind])
	p.category = category
	p.kind = kind
	p.direction = direction
	p.parameters = params
	return p


func test_propose_creates_proposal():
	var prims: Array[TreatyPrimitive] = [_make_primitive(&"restraint", &"no_host_recruitment")]
	var proposal: TreatyProposal = _treaty.propose_treaty(&"player", &"the_veil_founder", prims, 100)
	assert_not_null(proposal)
	assert_eq(proposal.stage, &"negotiation")
	assert_eq(proposal.proposer_immortal_id, &"player")
	assert_eq(proposal.primitives.size(), 1)
	assert_eq(proposal.history.size(), 1)


func test_propose_counter_counter_accept():
	var prims: Array[TreatyPrimitive] = [_make_primitive(&"restraint", &"no_host_recruitment")]
	var proposal := _treaty.propose_treaty(&"player", &"the_veil_founder", prims, 100)
	# Counter-propose with modified primitives
	var counter_prims: Array[TreatyPrimitive] = [
		_make_primitive(&"restraint", &"no_host_recruitment"),
		_make_primitive(&"information", &"share_intelligence"),
	]
	_treaty.counter_propose(proposal.id, counter_prims, &"the_veil_founder", 110)
	assert_eq(proposal.current_round, 2)
	assert_eq(proposal.primitives.size(), 2)
	# Player counter-proposes back
	var final_prims: Array[TreatyPrimitive] = [_make_primitive(&"restraint", &"no_host_recruitment")]
	_treaty.counter_propose(proposal.id, final_prims, &"player", 120)
	assert_eq(proposal.current_round, 3)
	# Veil accepts
	var treaty: TreatyRecord = _treaty.accept_proposal(proposal.id, &"the_veil_founder", 130)
	assert_not_null(treaty)
	assert_eq(treaty.status, &"active")
	assert_eq(proposal.stage, &"signed")


func test_propose_reject():
	var prims: Array[TreatyPrimitive] = [_make_primitive(&"restraint", &"no_host_recruitment")]
	var proposal := _treaty.propose_treaty(&"player", &"the_veil_founder", prims, 100)
	_treaty.reject_proposal(proposal.id, &"the_veil_founder", "unacceptable", 110)
	assert_eq(proposal.stage, &"terminated")
	assert_eq(proposal.termination_reason, "unacceptable")


func test_max_rounds_terminates():
	var prims: Array[TreatyPrimitive] = [_make_primitive(&"restraint", &"no_host_recruitment")]
	var proposal := _treaty.propose_treaty(&"player", &"the_veil_founder", prims, 100)
	proposal.max_rounds = 3
	# Round 2
	_treaty.counter_propose(proposal.id, prims, &"the_veil_founder", 110)
	assert_eq(proposal.current_round, 2)
	# Round 3
	_treaty.counter_propose(proposal.id, prims, &"player", 120)
	assert_eq(proposal.current_round, 3)
	# Round 4 — should terminate
	var result := _treaty.counter_propose(proposal.id, prims, &"the_veil_founder", 130)
	assert_eq(result.stage, &"terminated")
	assert_eq(result.termination_reason, "max_rounds_reached")


func test_violation_detection():
	var prims: Array[TreatyPrimitive] = [_make_primitive(&"restraint", &"no_host_recruitment")]
	var proposal := _treaty.propose_treaty(&"player", &"the_veil_founder", prims, 100)
	var treaty := _treaty.accept_proposal(proposal.id, &"the_veil_founder", 110)
	assert_not_null(treaty)
	# Action that violates no_host_recruitment
	var violation: Dictionary = _treaty.find_treaty_violation(&"cultivate_to_host", &"some_char", &"player")
	assert_false(violation.is_empty(), "Should detect violation")
	assert_eq(violation["treaty"].id, treaty.id)


func test_reputation_updates_on_signing():
	var prims: Array[TreatyPrimitive] = [_make_primitive(&"restraint", &"no_host_recruitment")]
	var proposal := _treaty.propose_treaty(&"player", &"the_veil_founder", prims, 100)
	_treaty.accept_proposal(proposal.id, &"the_veil_founder", 110)
	var player_rep: ReputationRecord = _treaty.get_reputation(&"player")
	var veil_rep: ReputationRecord = _treaty.get_reputation(&"the_veil_founder")
	assert_eq(player_rep.reputation_score, 51, "+1 for signing")
	assert_eq(veil_rep.reputation_score, 51, "+1 for signing")


func test_reputation_on_violation():
	var prims: Array[TreatyPrimitive] = [_make_primitive(&"restraint", &"no_host_recruitment")]
	var proposal := _treaty.propose_treaty(&"player", &"the_veil_founder", prims, 100)
	var treaty := _treaty.accept_proposal(proposal.id, &"the_veil_founder", 110)
	_treaty.record_violation(treaty, &"player", &"cultivate_to_host", &"some_char", 200)
	var player_rep: ReputationRecord = _treaty.get_reputation(&"player")
	var veil_rep: ReputationRecord = _treaty.get_reputation(&"the_veil_founder")
	# Player: +1 signing, -10 violation = 41
	assert_eq(player_rep.reputation_score, 41)
	# Veil: +1 signing, -2 counterparty of violation = 49
	assert_eq(veil_rep.reputation_score, 49)


func test_perpetual_vs_duration_bounded():
	# Duration-bounded treaty
	var prims_d: Array[TreatyPrimitive] = [
		_make_primitive(&"restraint", &"no_host_recruitment"),
		_make_primitive(&"term", &"duration", &"two_way", {"years": 50}),
	]
	var proposal_d := _treaty.propose_treaty(&"player", &"the_veil_founder", prims_d, 100)
	var treaty_d := _treaty.accept_proposal(proposal_d.id, &"the_veil_founder", 110)
	assert_eq(treaty_d.expires_at_day, 110 + (50 * 365))
	# Perpetual treaty
	var prims_p: Array[TreatyPrimitive] = [
		_make_primitive(&"restraint", &"no_host_recruitment"),
		_make_primitive(&"term", &"perpetual_until_broken"),
	]
	var proposal_p := _treaty.propose_treaty(&"player", &"the_veil_founder", prims_p, 200)
	var treaty_p := _treaty.accept_proposal(proposal_p.id, &"the_veil_founder", 210)
	assert_eq(treaty_p.expires_at_day, -1, "Perpetual treaty has no expiry")
