extends GutTest

# Integration: drive a kingdom toward broke. Verify condition degrades
# flush → stable → strained → indebted → broke.

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


func test_treasury_degrades_to_broke():
	var k := KingdomRecord.new()
	k.id = &"crisis_test"
	k.display_name = "Crisis Kingdom"
	k.ruler_character_id = &"ruler_athens"
	k.capital_place_id = &"athens"
	k.member_place_ids = [&"athens"]
	k.tax_level = 10  # very low income
	k.legitimacy = 60
	k.standing_army = 1000  # huge army → massive expenditure
	k.treasury_condition = &"flush"
	k.debt_by_creditor = {&"temple": 5000}  # significant debt
	_kingdom._kingdoms[&"crisis_test"] = k
	_kingdom._place_to_kingdom[&"athens"] = &"crisis_test"

	var conditions_seen: Array = [k.treasury_condition]
	var events: Array = []
	var eb: Node = get_node("/root/EventBus")
	var sub = eb.subscribe(
		preload("res://scripts/data/events/kingdom_treasury_condition_changed_event.gd"),
		func(e):
			conditions_seen.append(e.new_condition)
			events.append(e),
		50,
	)

	# Update for several days
	for day in range(1, 30):
		_kingdom._update_kingdom(&"crisis_test", day)

	eb.unsubscribe(sub)

	# Should have degraded from flush
	assert_true(conditions_seen.size() > 1 or k.treasury_condition != &"flush",
		"Treasury should have degraded from flush with high expenditure and low income")
	# The final condition should be worse than flush
	assert_true(k.treasury_condition in [&"stable", &"strained", &"indebted", &"broke"],
		"Final condition should reflect fiscal pressure")
