extends GutTest

func test_field_access():
	var k := KingdomRecord.new()
	k.id = &"persia"
	k.display_name = "Achaemenid Persia"
	k.ruler_character_id = &"darius_placeholder"
	k.capital_place_id = &"persepolis"
	k.member_place_ids = [&"persepolis", &"susa", &"ecbatana"]
	k.tax_level = 50
	k.legitimacy = 70
	assert_eq(k.id, &"persia")
	assert_eq(k.member_place_ids.size(), 3)
	assert_eq(k.tax_level, 50)

func test_dominant_faction():
	var k := KingdomRecord.new()
	k.faction_military = 40
	k.faction_clergy = 10
	k.faction_merchants = 25
	k.faction_nobility = 25
	assert_eq(k.dominant_faction(), &"military")

func test_total_debt():
	var k := KingdomRecord.new()
	k.debt_by_creditor = {&"merchant_guild": 500, &"temple": 200}
	assert_eq(k.total_debt(), 700)

func test_save_load_roundtrip():
	var k := KingdomRecord.new()
	k.id = &"roundtrip_kingdom"
	k.display_name = "Test Kingdom"
	k.tax_level = 60
	k.treasury_condition = &"strained"
	var path := "user://test_kingdom_record_roundtrip.tres"
	ResourceSaver.save(k, path)
	var loaded: KingdomRecord = ResourceLoader.load(path) as KingdomRecord
	assert_not_null(loaded)
	assert_eq(loaded.tax_level, 60)
	assert_eq(loaded.treasury_condition, &"strained")
	DirAccess.remove_absolute(path)
