extends GutTest

# Integration: Player and Veil reach Level 1; first contact; reciprocate; player proposes
# treaty; Veil evaluates (via counterparty evaluation); treaty signed; treaty active;
# treaty expires; reputation contributions applied.

var _treaty: Treaty
var _first_contact: FirstContact


func before_each():
	_treaty = Treaty.new()
	_treaty.name = "Treaty"
	add_child(_treaty)
	_first_contact = FirstContact.new()
	_first_contact.name = "FirstContact"
	add_child(_first_contact)


func after_each():
	for node in [_treaty, _first_contact]:
		if is_instance_valid(node):
			remove_child(node)
			node.free()


func _make_primitive(category: StringName, kind: StringName, direction: StringName = &"two_way", params: Dictionary = {}) -> TreatyPrimitive:
	var p := TreatyPrimitive.new()
	p.id = StringName("%s_%s" % [category, kind])
	p.category = category
	p.kind = kind
	p.direction = direction
	p.parameters = params
	return p


func test_full_treaty_lifecycle():
	# 1. First contact: player detects Veil
	var fc_event := FirstContactEvent.new()
	fc_event.detecting_immortal_id = &"player"
	fc_event.detected_society_id = &"the_veil"
	fc_event.detected_immortal_id = &"the_veil_founder"
	fc_event.day = 100
	_first_contact._on_first_contact_event(fc_event)
	var state := _first_contact.get_contact_state(&"player", &"the_veil_founder")
	assert_eq(state.stage, &"a_aware")

	# 2. Veil initiates contact with shared intelligence
	_first_contact.initiate_contact(&"the_veil_founder", &"player", &"shared_intelligence", 200)
	state = _first_contact.get_contact_state(&"player", &"the_veil_founder")
	assert_eq(state.stage, &"contact_initiated")

	# 3. Player reciprocates
	_first_contact.respond_to_contact(&"the_veil_founder", &"player", &"reciprocated", 250)
	state = _first_contact.get_contact_state(&"player", &"the_veil_founder")
	assert_eq(state.stage, &"channel_open")

	# 4. Player proposes treaty
	var prims: Array[TreatyPrimitive] = [
		_make_primitive(&"restraint", &"no_host_recruitment"),
		_make_primitive(&"information", &"share_intelligence"),
		_make_primitive(&"term", &"duration", &"two_way", {"years": 20}),
	]
	var proposal := _treaty.propose_treaty(&"player", &"the_veil_founder", prims, 300)
	assert_not_null(proposal)

	# 5. Veil evaluates and counter-proposes (adding deconflict)
	var counter_prims: Array[TreatyPrimitive] = [
		_make_primitive(&"restraint", &"no_host_recruitment"),
		_make_primitive(&"information", &"share_intelligence"),
		_make_primitive(&"operational", &"deconflict_region", &"two_way", {"region": &"attica"}),
		_make_primitive(&"term", &"duration", &"two_way", {"years": 20}),
	]
	_treaty.counter_propose(proposal.id, counter_prims, &"the_veil_founder", 320)
	assert_eq(proposal.current_round, 2)

	# 6. Player accepts modified terms
	var treaty := _treaty.accept_proposal(proposal.id, &"player", 340)
	assert_not_null(treaty)
	assert_eq(treaty.status, &"active")
	assert_eq(treaty.primitives.size(), 4)

	# 7. Treaty expires at day 340 + 20*365 = 7640
	assert_eq(treaty.expires_at_day, 340 + (20 * 365))

	# 8. Verify reputation improved for both
	var player_rep := _treaty.get_reputation(&"player")
	var veil_rep := _treaty.get_reputation(&"the_veil_founder")
	assert_true(player_rep.reputation_score > 50, "Player reputation should improve after signing")
	assert_true(veil_rep.reputation_score > 50, "Veil reputation should improve after signing")
