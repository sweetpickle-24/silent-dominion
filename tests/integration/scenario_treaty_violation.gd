extends GutTest

# Integration: Treaty signed; player dispatches scheme that violates a restraint
# primitive; violation detected; reputation drops.

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


func test_treaty_violation_flow():
	# 1. Sign a treaty with no-host-recruitment restraint
	var prims: Array[TreatyPrimitive] = [
		_make_primitive(&"restraint", &"no_host_recruitment"),
		_make_primitive(&"term", &"perpetual_until_broken"),
	]
	var proposal := _treaty.propose_treaty(&"player", &"the_veil_founder", prims, 100)
	var treaty := _treaty.accept_proposal(proposal.id, &"the_veil_founder", 110)
	assert_not_null(treaty)
	assert_eq(treaty.status, &"active")

	# 2. Player dispatches cultivate_to_host — violates no_host_recruitment
	var violation := _treaty.find_treaty_violation(&"cultivate_to_host", &"some_scholar", &"player")
	assert_false(violation.is_empty(), "Should detect treaty violation")

	# 3. Record the violation
	_treaty.record_violation(treaty, &"player", &"cultivate_to_host", &"some_scholar", 200)
	assert_eq(treaty.violations.size(), 1)

	# 4. Player reputation drops
	var player_rep := _treaty.get_reputation(&"player")
	# +1 signing, -10 violation = 41
	assert_eq(player_rep.reputation_score, 41)

	# 5. Veil terminates treaty after violation
	_treaty.terminate_treaty(treaty.id, &"the_veil_founder", "unacceptable_violation", 300)
	assert_eq(treaty.status, &"violated_terminated")
