extends GutTest


func test_field_access():
	var c := CharacterRecord.new()
	c.id = &"test_char"
	c.name = "Test Character"
	c.birth_day = -10000
	c.profession = ProfessionValues.SCHOLAR
	c.region = &"attica"
	c.current_place = &"athens"
	c.ambition = 75
	c.intellect = 90
	assert_eq(c.id, &"test_char")
	assert_eq(c.profession, ProfessionValues.SCHOLAR)
	assert_eq(c.ambition, 75)
	assert_eq(c.intellect, 90)


func test_is_alive():
	var c := CharacterRecord.new()
	c.death_day = -1
	assert_true(c.is_alive(100), "death_day=-1 means alive")
	c.death_day = 50
	assert_true(c.is_alive(49), "should be alive before death_day")
	assert_false(c.is_alive(50), "should be dead at death_day")
	assert_false(c.is_alive(100), "should be dead after death_day")


func test_age_in_days():
	var c := CharacterRecord.new()
	c.birth_day = -10000
	assert_eq(c.age_in_days(0), 10000)
	assert_eq(c.age_in_days(365), 10365)


func test_get_trait():
	var c := CharacterRecord.new()
	c.ambition = 80
	c.paranoia = 30
	c.curiosity = 95
	assert_eq(c.get_trait(TraitValues.AMBITION), 80)
	assert_eq(c.get_trait(TraitValues.PARANOIA), 30)
	assert_eq(c.get_trait(TraitValues.CURIOSITY), 95)
	assert_eq(c.get_trait(TraitValues.LOYALTY), 50)  # default


func test_save_load_roundtrip():
	var c := CharacterRecord.new()
	c.id = &"roundtrip_char"
	c.name = "Roundtrip"
	c.birth_day = -5000
	c.profession = ProfessionValues.MERCHANT
	c.ambition = 70
	c.heat = 15
	c.trust_score = 85
	c.languages.append(&"greek")
	c.languages.append(&"persian")

	var path: String = "user://test_character_record_roundtrip.tres"
	ResourceSaver.save(c, path)
	var loaded: CharacterRecord = ResourceLoader.load(path) as CharacterRecord
	assert_not_null(loaded)
	assert_eq(loaded.id, &"roundtrip_char")
	assert_eq(loaded.ambition, 70)
	assert_eq(loaded.heat, 15)
	assert_eq(loaded.trust_score, 85)
	assert_eq(loaded.languages.size(), 2)
	DirAccess.remove_absolute(path)
