extends GutTest

# Data validation: verify authored kingdom data is consistent with existing places.

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


func test_kingdoms_loaded():
	assert_eq(_kingdom.kingdom_count(), 8, "Should load 8 starting kingdoms")


func test_every_kingdom_has_valid_capital():
	var wr: Node = get_node("/root/WorldRegistry")
	for kid: StringName in _kingdom.all_kingdom_ids():
		var k: KingdomRecord = _kingdom.get_kingdom(kid)
		assert_ne(k.capital_place_id, &"", "Kingdom %s should have a capital" % kid)
		var capital: PlaceRecord = wr.get_place(k.capital_place_id)
		assert_not_null(capital, "Capital %s of kingdom %s should exist in WorldRegistry" % [k.capital_place_id, kid])


func test_every_member_place_exists():
	var wr: Node = get_node("/root/WorldRegistry")
	for kid: StringName in _kingdom.all_kingdom_ids():
		var k: KingdomRecord = _kingdom.get_kingdom(kid)
		for place_id: StringName in k.member_place_ids:
			var place: PlaceRecord = wr.get_place(place_id)
			assert_not_null(place, "Place %s in kingdom %s should exist" % [place_id, kid])


func test_no_place_in_multiple_kingdoms():
	var place_owners: Dictionary = {}
	for kid: StringName in _kingdom.all_kingdom_ids():
		var k: KingdomRecord = _kingdom.get_kingdom(kid)
		for place_id: StringName in k.member_place_ids:
			assert_false(place_owners.has(place_id),
				"Place %s assigned to both %s and %s" % [place_id, place_owners.get(place_id, ""), kid])
			place_owners[place_id] = kid


func test_reverse_lookup_works():
	assert_eq(_kingdom.kingdom_of_place(&"athens"), &"athens")
	assert_eq(_kingdom.kingdom_of_place(&"persepolis"), &"achaemenid_persia")
	assert_eq(_kingdom.kingdom_of_place(&"rome"), &"roman_republic")
	# Unassigned places return empty
	assert_eq(_kingdom.kingdom_of_place(&"delphi"), &"")
	assert_eq(_kingdom.kingdom_of_place(&"mount_athos"), &"")
