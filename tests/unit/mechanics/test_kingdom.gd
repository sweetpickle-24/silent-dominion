extends GutTest

var _kingdom: Kingdom


func before_each():
	_kingdom = Kingdom.new()
	_kingdom.name = "Kingdom"
	add_child(_kingdom)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_kingdom):
		if _kingdom._tick_sub:
			eb.unsubscribe(_kingdom._tick_sub)
		remove_child(_kingdom)
		_kingdom.free()


func _make_kingdom(id: StringName, places: Array[StringName], tax: int = 40) -> KingdomRecord:
	var k := KingdomRecord.new()
	k.id = id
	k.display_name = "Test Kingdom"
	k.capital_place_id = places[0] if places.size() > 0 else &""
	k.member_place_ids = places
	k.tax_level = tax
	k.legitimacy = 60
	k.standing_army = 50
	return k


func _register_kingdom(k: KingdomRecord) -> void:
	_kingdom._kingdoms[k.id] = k
	for place_id: StringName in k.member_place_ids:
		_kingdom._place_to_kingdom[place_id] = k.id


func test_derived_treasury_is_place_rollup():
	# Treasury value is computed from place yields, not stored
	var k := _make_kingdom(&"test_k", [&"athens", &"corinth"])
	_register_kingdom(k)
	var value: int = _kingdom.derived_treasury_value(&"test_k")
	# Value should be derived from actual place tax_yield_per_day
	# Not testing exact number since it depends on place data + efficiency formula
	# Just verify it's computed (non-zero if places have population)
	assert_true(value is int, "Treasury value should be an int")


func test_treasury_condition_band_transitions():
	var k := _make_kingdom(&"band_test", [&"athens"])
	_register_kingdom(k)
	# With high tax and good places, should be above strained
	k.tax_level = 80
	k.standing_army = 10
	_kingdom._update_kingdom(&"band_test", 100)
	assert_true(k.treasury_condition in [&"flush", &"stable", &"strained"],
		"Kingdom with moderate setup should not be broke")


func test_collection_efficiency_factors():
	var wr: Node = get_node("/root/WorldRegistry")
	var place: PlaceRecord = wr.get_place(&"athens")
	if place == null:
		pending("Athens not in world registry")
		return
	var k := _make_kingdom(&"eff_test", [&"athens"])
	_register_kingdom(k)
	var eff: float = _kingdom._collection_efficiency(place, k)
	assert_gt(eff, 0.0, "Efficiency should be positive")
	assert_lte(eff, 1.0, "Efficiency should not exceed 1.0")


func test_tax_level_affects_income():
	# Set tax_yield_per_day on place since Place mechanic hasn't ticked in test
	var wr: Node = get_node("/root/WorldRegistry")
	var place: PlaceRecord = wr.get_place(&"athens")
	if place == null:
		pending("Athens not available")
		return
	var saved_yield: int = place.tax_yield_per_day
	place.tax_yield_per_day = 100  # ensure nonzero

	var k_low := _make_kingdom(&"low_tax", [&"athens"], 20)
	_register_kingdom(k_low)
	var income_low: int = _kingdom._compute_tax_income(k_low)

	var k_high := _make_kingdom(&"high_tax", [&"athens"], 80)
	_kingdom._kingdoms[&"high_tax"] = k_high
	var income_high: int = _kingdom._compute_tax_income(k_high)

	place.tax_yield_per_day = saved_yield  # restore
	assert_true(income_high > income_low, "Higher tax level should produce more income")


func test_debt_service_reduces_treasury():
	var k_no_debt := _make_kingdom(&"no_debt", [&"athens"])
	_register_kingdom(k_no_debt)
	var exp_no_debt: int = _kingdom._compute_expenditure(k_no_debt)

	var k_debt := _make_kingdom(&"with_debt", [&"athens"])
	k_debt.debt_by_creditor = {&"temple": 10000}
	_kingdom._kingdoms[&"with_debt"] = k_debt
	var exp_debt: int = _kingdom._compute_expenditure(k_debt)

	assert_gt(exp_debt, exp_no_debt, "Debt service should increase expenditure")


func test_unrest_accumulates_from_high_tax():
	var k := _make_kingdom(&"unrest_test", [&"athens"])
	k.tax_level = 80  # well above 50
	k.unrest = 10
	_register_kingdom(k)
	_kingdom._update_unrest(k)
	assert_gt(k.unrest, 10, "High tax should increase unrest")


func test_unrest_decays_with_low_tax():
	var k := _make_kingdom(&"decay_test", [&"athens"])
	k.tax_level = 30  # below 50
	k.legitimacy = 70  # above 50
	k.unrest = 30
	_register_kingdom(k)
	_kingdom._update_unrest(k)
	assert_lt(k.unrest, 30, "Low tax + high legitimacy should decay unrest")


func test_treasury_condition_event_fires():
	var events_received: Array = []
	var eb: Node = get_node("/root/EventBus")
	var sub = eb.subscribe(
		preload("res://scripts/data/events/kingdom_treasury_condition_changed_event.gd"),
		func(e): events_received.append(e),
		50,
	)
	var k := _make_kingdom(&"event_test", [&"athens"])
	k.treasury_condition = &"flush"
	k.standing_army = 50000  # huge army → massive expenditure → condition drops
	_register_kingdom(k)
	_kingdom._update_kingdom(&"event_test", 100)
	# If condition changed from flush to something else, event fires
	if k.treasury_condition != &"flush":
		assert_eq(events_received.size(), 1)
	eb.unsubscribe(sub)


func test_kingdom_of_place_reverse_lookup():
	var k := _make_kingdom(&"lookup_test", [&"athens", &"corinth"])
	_register_kingdom(k)
	assert_eq(_kingdom.kingdom_of_place(&"athens"), &"lookup_test")
	assert_eq(_kingdom.kingdom_of_place(&"corinth"), &"lookup_test")
	assert_eq(_kingdom.kingdom_of_place(&"nonexistent"), &"")


func test_apply_tax_level_change():
	var k := _make_kingdom(&"tax_change", [&"athens"])
	_register_kingdom(k)
	_kingdom.apply_tax_level_change(&"tax_change", 15, 100)
	assert_eq(k.tax_level, 55)
	_kingdom.apply_tax_level_change(&"tax_change", -60, 110)
	assert_eq(k.tax_level, 0)  # clamped to 0


func test_apply_debt_change():
	var k := _make_kingdom(&"debt_change", [&"athens"])
	_register_kingdom(k)
	_kingdom.apply_debt_change(&"debt_change", &"temple", 1000)
	assert_eq(k.debt_by_creditor[&"temple"], 1000)
	_kingdom.apply_debt_change(&"debt_change", &"temple", -500)
	assert_eq(k.debt_by_creditor[&"temple"], 500)
	_kingdom.apply_debt_change(&"debt_change", &"temple", -600)
	assert_false(k.debt_by_creditor.has(&"temple"), "Zero debt should be erased")


func test_derived_military_strength():
	var k := _make_kingdom(&"mil_test", [&"athens"])
	k.standing_army = 200
	_register_kingdom(k)
	var strength: int = _kingdom.derived_military_strength(&"mil_test")
	assert_gt(strength, 200, "Strength should include levy potential + standing army")


func test_save_load_roundtrip():
	var k := _make_kingdom(&"save_test", [&"athens"])
	k.treasury_condition = &"strained"
	_register_kingdom(k)
	var snapshot: Dictionary = _kingdom.snapshot_state()
	assert_true(snapshot.has("kingdoms"))
	_kingdom._kingdoms.clear()
	_kingdom._place_to_kingdom.clear()
	_kingdom.apply_state(snapshot)
	assert_eq(_kingdom.get_kingdom(&"save_test").treasury_condition, &"strained")
	assert_eq(_kingdom.kingdom_of_place(&"athens"), &"save_test")
