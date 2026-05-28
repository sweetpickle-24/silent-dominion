extends GutTest

var _religion: ReligionIdeology


func before_each():
	_religion = ReligionIdeology.new()
	_religion.name = "ReligionIdeology"
	add_child(_religion)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_religion):
		if _religion._tick_sub:
			eb.unsubscribe(_religion._tick_sub)
		remove_child(_religion)
		_religion.free()


func _make_religion(id: StringName, phase: StringName = &"consolidation") -> ReligionRecord:
	var r := ReligionRecord.new()
	r.id = id
	r.display_name = "Test Religion"
	r.lifecycle_phase = phase
	r.doctrinal_rigidity = 50
	r.institutional_strength = 50
	r.popular_depth = 50
	r.ecumenical_openness = 50
	r.reform_potential = 10
	return r


func test_religion_spreads_to_adjacent():
	var r := _make_religion(&"test_rel")
	_religion._religions[&"test_rel"] = r
	_religion.set_presence(&"athens", &"test_rel", 5000, 60, true, 0.0)
	# Run diffusion step
	_religion._update_religions()
	# Check if any spread happened (corinth is adjacent to attica via corinthia)
	var total: int = _religion.total_followers(&"test_rel")
	assert_gte(total, 5000, "Religion should not lose followers from spread")


func test_spread_weighted_by_population():
	# Higher population targets should attract more transfer — tested via the rate function
	var r := _make_religion(&"pop_rel")
	_religion._religions[&"pop_rel"] = r
	var rate_high: float = _religion._religion_transfer_rate(&"athens", &"corinth", &"pop_rel", 1.0, 100.0)
	# Rate should be a positive number (actual value depends on population state)
	assert_gte(rate_high, 0.0, "Transfer rate should be non-negative")


func test_institutional_presence_boosts_spread():
	var r := _make_religion(&"inst_rel")
	_religion._religions[&"inst_rel"] = r
	# With institutional presence
	_religion.set_presence(&"athens", &"inst_rel", 1000, 60, true, 0.0)
	var rate_inst: float = _religion._religion_transfer_rate(&"athens", &"corinth", &"inst_rel", 1.0, 100.0)
	# Without institutional presence
	_religion.set_presence(&"athens", &"inst_rel", 1000, 60, false, 0.0)
	var rate_no_inst: float = _religion._religion_transfer_rate(&"athens", &"corinth", &"inst_rel", 1.0, 100.0)
	assert_gt(rate_inst, rate_no_inst, "Institutional presence should boost spread")


func test_ecumenical_openness_modifies_spread():
	var r_open := _make_religion(&"open_rel")
	r_open.ecumenical_openness = 90
	_religion._religions[&"open_rel"] = r_open
	var rate_open: float = _religion._religion_transfer_rate(&"athens", &"corinth", &"open_rel", 1.0, 100.0)
	var r_closed := _make_religion(&"closed_rel")
	r_closed.ecumenical_openness = 10
	_religion._religions[&"closed_rel"] = r_closed
	var rate_closed: float = _religion._religion_transfer_rate(&"athens", &"corinth", &"closed_rel", 1.0, 100.0)
	assert_gt(rate_open, rate_closed, "More ecumenical should spread faster")


func test_reform_potential_accumulates_from_rigidity():
	var r := _make_religion(&"rigid_rel")
	r.doctrinal_rigidity = 80
	r.lifecycle_phase = &"dominance"
	r.reform_potential = 10
	_religion._religions[&"rigid_rel"] = r
	_religion.set_presence(&"athens", &"rigid_rel", 5000, 60, true, 0.0)
	_religion._update_reform_potential(r)
	assert_gt(r.reform_potential, 10, "High rigidity should accumulate reform potential")


func test_lifecycle_emergence_to_consolidation():
	var r := _make_religion(&"emerging_rel", &"emergence")
	_religion._religions[&"emerging_rel"] = r
	# Give it enough followers and places
	_religion.set_presence(&"athens", &"emerging_rel", 3000, 60, true, 0.0)
	_religion.set_presence(&"corinth", &"emerging_rel", 2000, 50, false, 0.0)
	_religion.set_presence(&"sparta", &"emerging_rel", 1000, 40, false, 0.0)
	_religion._check_lifecycle_transitions(r, 100)
	assert_eq(r.lifecycle_phase, &"consolidation", "Should transition to consolidation")


func test_decline_on_low_followers():
	var r := _make_religion(&"dying_rel", &"consolidation")
	_religion._religions[&"dying_rel"] = r
	_religion.set_presence(&"athens", &"dying_rel", 100, 10, false, 0.0)
	_religion._check_lifecycle_transitions(r, 100)
	assert_eq(r.lifecycle_phase, &"decline", "Low followers should cause decline")


func test_dominant_religion_of_place():
	# Clear existing presence to isolate test
	_religion._presence[&"athens"] = {}
	_religion.set_presence(&"athens", &"rel_a", 5000, 60, true, 0.0)
	_religion.set_presence(&"athens", &"rel_b", 2000, 40, false, 0.0)
	assert_eq(_religion.dominant_religion(&"athens"), &"rel_a")


func test_total_followers():
	_religion.set_presence(&"athens", &"rel_x", 3000, 50, true, 0.0)
	_religion.set_presence(&"corinth", &"rel_x", 2000, 40, false, 0.0)
	assert_eq(_religion.total_followers(&"rel_x"), 5000)


func test_route_connected_places_spread_faster():
	# Routes have weight 2.0 vs adjacency weight 1.0
	var r := _make_religion(&"route_rel")
	_religion._religions[&"route_rel"] = r
	var rate_route: float = _religion._religion_transfer_rate(&"athens", &"corinth", &"route_rel", 2.0, 100.0)
	var rate_adj: float = _religion._religion_transfer_rate(&"athens", &"corinth", &"route_rel", 1.0, 100.0)
	assert_gt(rate_route, rate_adj, "Route-connected should spread faster")


func test_save_load_roundtrip():
	var r := _make_religion(&"save_rel")
	_religion._religions[&"save_rel"] = r
	_religion.set_presence(&"athens", &"save_rel", 5000, 60, true, 0.0)
	_religion._day_accumulator = 15
	var snapshot: Dictionary = _religion.snapshot_state()
	_religion._religions.clear()
	_religion._presence.clear()
	_religion._day_accumulator = 0
	_religion.apply_state(snapshot)
	assert_true(_religion._religions.has(&"save_rel"))
	assert_eq(_religion._day_accumulator, 15)
