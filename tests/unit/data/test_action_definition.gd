extends GutTest


func test_field_access():
	var ad := ActionDefinition.new()
	ad.id = &"test_action"
	ad.display_name = "Test Action"
	ad.tier = 2
	ad.baseline_exposure_cost = 3.5
	ad.baseline_bandwidth_cost = 2
	ad.baseline_financial_cost = 200
	ad.baseline_time_days = 60
	ad.required_capabilities.append(&"trade_network")
	assert_eq(ad.id, &"test_action")
	assert_eq(ad.tier, 2)
	assert_eq(ad.baseline_exposure_cost, 3.5)
	assert_eq(ad.required_capabilities.size(), 1)


func test_save_load_roundtrip():
	var ad := ActionDefinition.new()
	ad.id = &"roundtrip_action"
	ad.display_name = "Roundtrip"
	ad.tier = 3
	ad.baseline_exposure_cost = 8.0
	ad.baseline_time_days = 180
	ad.phase_timing_overrides = {&"executing": 60}

	var path: String = "user://test_action_definition_roundtrip.tres"
	ResourceSaver.save(ad, path)
	var loaded: ActionDefinition = ResourceLoader.load(path) as ActionDefinition
	assert_not_null(loaded)
	assert_eq(loaded.id, &"roundtrip_action")
	assert_eq(loaded.tier, 3)
	assert_eq(loaded.phase_timing_overrides.get(&"executing"), 60)
	DirAccess.remove_absolute(path)


func test_chain_loads_all_definitions():
	# Chain is in the main scene; access it if available, otherwise create local
	var chain := Chain.new()
	chain.name = "Chain"
	add_child(chain)
	assert_eq(chain.get_all_action_definitions().size(), 17, "Should load 13 action definitions")
	assert_not_null(chain.get_action_definition(&"observe"))
	assert_not_null(chain.get_action_definition(&"corrupt_institution"))
	assert_null(chain.get_action_definition(&"nonexistent"))
	remove_child(chain)
	chain.free()
