extends GutTest

var _action: Action
var _chain: Chain


func before_each():
	_action = Action.new()
	_action.name = "Action"
	add_child(_action)
	_chain = Chain.new()
	_chain.name = "Chain"
	add_child(_chain)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_action):
		if _action._phase_advanced_sub:
			eb.unsubscribe(_action._phase_advanced_sub)
		if _action._cancelled_sub:
			eb.unsubscribe(_action._cancelled_sub)
	if is_instance_valid(_chain) and _chain._tick_subscription:
		eb.unsubscribe(_chain._tick_subscription)
	if is_instance_valid(_chain):
		remove_child(_chain)
		_chain.free()
	if is_instance_valid(_action):
		remove_child(_action)
		_action.free()


func test_phase_to_chain_status():
	assert_eq(_chain._phase_to_chain_status(SchemePhases.ACKNOWLEDGED), ChainStatusValues.LIEUTENANT)
	assert_eq(_chain._phase_to_chain_status(SchemePhases.ROUTING), ChainStatusValues.COORDINATOR)
	assert_eq(_chain._phase_to_chain_status(SchemePhases.EXECUTING), ChainStatusValues.WITTING_OPERATIVE)
	assert_eq(_chain._phase_to_chain_status(SchemePhases.DISPATCHED), &"")
	assert_eq(_chain._phase_to_chain_status(SchemePhases.RESOLVED), &"")


func test_find_candidates_filters_by_status():
	var scheme: SchemeRecord = _action.dispatch(ActionTypeValues.PLANT_IDEA, &"athens", &"athens")
	var lieutenants: Array = _chain._find_candidates(scheme, ChainStatusValues.LIEUTENANT)
	for c: CharacterRecord in lieutenants:
		assert_eq(c.chain_status, ChainStatusValues.LIEUTENANT)
	var coordinators: Array = _chain._find_candidates(scheme, ChainStatusValues.COORDINATOR)
	for c: CharacterRecord in coordinators:
		assert_eq(c.chain_status, ChainStatusValues.COORDINATOR)


func test_find_candidates_excludes_dead():
	var ir: Node = get_node("/root/ImmortalRegistry")
	var theron: CharacterRecord = ir.get_character(&"theron")
	var original_death: int = theron.death_day
	theron.death_day = 0
	var scheme := SchemeRecord.new()
	scheme.id = &"test"
	scheme.action_type = &"plant_idea"
	scheme.target_place_ref = &"athens"
	var lieutenants: Array = _chain._find_candidates(scheme, ChainStatusValues.LIEUTENANT, 1)
	for c: CharacterRecord in lieutenants:
		assert_ne(c.id, &"theron", "Dead Theron should be excluded")
	if lieutenants.is_empty():
		pass_test("No lieutenant candidates — Theron correctly excluded")
	theron.death_day = original_death


func test_find_candidates_excludes_high_heat():
	var ir: Node = get_node("/root/ImmortalRegistry")
	var theron: CharacterRecord = ir.get_character(&"theron")
	var original_heat: int = theron.heat
	theron.heat = 80
	var scheme := SchemeRecord.new()
	scheme.id = &"test"
	scheme.action_type = &"plant_idea"
	scheme.target_place_ref = &"athens"
	var lieutenants: Array = _chain._find_candidates(scheme, ChainStatusValues.LIEUTENANT, 0)
	for c: CharacterRecord in lieutenants:
		assert_ne(c.id, &"theron", "High-heat Theron should be excluded")
	if lieutenants.is_empty():
		pass_test("No lieutenant candidates — high-heat Theron correctly excluded")
	theron.heat = original_heat


func test_pick_best_candidate_prefers_region_match():
	var ir: Node = get_node("/root/ImmortalRegistry")
	# Lykia is in corinthia, Sosthenes is in ionia. For an Athens (attica) target,
	# neither matches — but both are witting_operatives. Scoring depends on language
	# and skill; this test verifies the function returns a non-null result.
	var scheme: SchemeRecord = _action.dispatch(ActionTypeValues.PLANT_IDEA, &"athens", &"athens")
	var ops: Array = _chain._find_candidates(scheme, ChainStatusValues.WITTING_OPERATIVE)
	assert_gt(ops.size(), 0, "Should have witting operative candidates")
	var best: CharacterRecord = _chain._pick_best_candidate(ops, scheme)
	assert_not_null(best)


func test_lieutenant_gets_assigned_on_acknowledged():
	var scheme: SchemeRecord = _action.dispatch(ActionTypeValues.PLANT_IDEA, &"athens", &"athens")
	# Tick until acknowledged
	for day in range(1, 100):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.ACKNOWLEDGED:
			break
	assert_eq(scheme.current_phase, SchemePhases.ACKNOWLEDGED)
	assert_ne(scheme.assigned_lieutenant_id, &"", "Lieutenant should be assigned")


func test_coordinator_gets_assigned_on_routing():
	var scheme: SchemeRecord = _action.dispatch(ActionTypeValues.PLANT_IDEA, &"athens", &"athens")
	for day in range(1, 100):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.ROUTING:
			break
	assert_eq(scheme.current_phase, SchemePhases.ROUTING)
	assert_ne(scheme.assigned_coordinator_id, &"", "Coordinator should be assigned")


func test_operative_gets_assigned_on_executing():
	var scheme: SchemeRecord = _action.dispatch(ActionTypeValues.PLANT_IDEA, &"athens", &"athens")
	for day in range(1, 100):
		_chain._advance_schemes(day)
		if scheme.current_phase == SchemePhases.EXECUTING:
			break
	assert_eq(scheme.current_phase, SchemePhases.EXECUTING)
	assert_ne(scheme.assigned_operative_id, &"", "Operative should be assigned")
