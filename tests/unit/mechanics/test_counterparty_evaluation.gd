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


func _make_veil_society() -> SocietyCharacterRecord:
	var s := SocietyCharacterRecord.new()
	s.society_id = &"the_veil"
	s.disposition_baseline = 60  # somewhat positive to make tests meaningful
	s.value_weights = {
		&"knowledge_preservation": 100,
		&"institutional_health_scholarly": 80,
		&"institutional_security": 40,
		&"intellectual_freedom": 70,
	}
	s.forbidden_moves = [&"book_burning", &"library_destruction", &"scholar_persecution"]
	return s


func _make_proposal(prims: Array[TreatyPrimitive]) -> TreatyProposal:
	var proposal := TreatyProposal.new()
	proposal.id = &"test_proposal"
	proposal.proposer_immortal_id = &"player"
	proposal.counterparty_immortal_id = &"the_veil_founder"
	proposal.primitives = prims
	proposal.stage = &"negotiation"
	return proposal


func test_veil_rejects_forbidden_move():
	var society := _make_veil_society()
	var prims: Array[TreatyPrimitive] = [
		_make_primitive(&"operational", &"book_burning"),
	]
	var proposal := _make_proposal(prims)
	var result: Dictionary = _treaty.evaluate_proposal_as_counterparty(proposal, society)
	assert_eq(result["decision"], &"reject")
	assert_eq(result["reason"], "forbidden_move")


func test_veil_accepts_library_protection():
	var society := _make_veil_society()
	# High-value-alignment primitives + positive disposition = accept
	var prims: Array[TreatyPrimitive] = [
		_make_primitive(&"information", &"share_intelligence"),
		_make_primitive(&"restraint", &"no_host_recruitment"),
	]
	var proposal := _make_proposal(prims)
	var result: Dictionary = _treaty.evaluate_proposal_as_counterparty(proposal, society)
	assert_eq(result["decision"], &"accept", "Veil should accept aligned proposal with positive disposition")


func test_high_paranoia_counter_proposes_more_restraints():
	var society := _make_veil_society()
	society.disposition_baseline = 50  # neutral
	var character := CharacterRecord.new()
	character.ambition = 80
	character.paranoia = 80  # dangerous_ruler pattern
	var prims: Array[TreatyPrimitive] = [
		_make_primitive(&"information", &"share_intelligence"),
	]
	var proposal := _make_proposal(prims)
	var result_with_paranoia: Dictionary = _treaty.evaluate_proposal_as_counterparty(proposal, society, character)
	# Compare with non-paranoid character
	var character_calm := CharacterRecord.new()
	character_calm.ambition = 50
	character_calm.paranoia = 50
	var result_calm: Dictionary = _treaty.evaluate_proposal_as_counterparty(proposal, society, character_calm)
	assert_true(result_with_paranoia["score"] < result_calm["score"], "Paranoid evaluator should score lower")


func test_corruption_profile_accepts_resource_transfer():
	var society := _make_veil_society()
	society.disposition_baseline = 50
	var character := CharacterRecord.new()
	character.greed = 85
	character.loyalty = 20  # corruption_profile
	# Proposal with resources flowing to them
	var prims: Array[TreatyPrimitive] = [
		_make_primitive(&"resource", &"transfer_silver", &"from_them"),
	]
	var proposal := _make_proposal(prims)
	var result: Dictionary = _treaty.evaluate_proposal_as_counterparty(proposal, society, character)
	# Non-corrupt character
	var character_honest := CharacterRecord.new()
	character_honest.greed = 40
	character_honest.loyalty = 70
	var result_honest: Dictionary = _treaty.evaluate_proposal_as_counterparty(proposal, society, character_honest)
	assert_true(result["score"] > result_honest["score"], "Corrupt evaluator should score resource-to-them higher")


func test_apex_predator_rejects_restraint_primitives():
	var society := _make_veil_society()
	society.disposition_baseline = 50
	var character := CharacterRecord.new()
	character.paranoia = 80
	character.ruthlessness = 85
	character.public_position_tier = PublicPositionValues.MAXIMAL  # apex_predator
	var prims: Array[TreatyPrimitive] = [
		_make_primitive(&"restraint", &"no_host_recruitment"),
		_make_primitive(&"restraint", &"no_surveillance_escalation"),
	]
	var proposal := _make_proposal(prims)
	var result: Dictionary = _treaty.evaluate_proposal_as_counterparty(proposal, society, character)
	assert_true(result["score"] < 30.0, "Apex predator should reject restraint-heavy proposal")
