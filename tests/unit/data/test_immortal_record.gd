extends GutTest


func test_construct_with_character():
	var c := CharacterRecord.new()
	c.id = &"test_char"
	c.name = "Test"
	c.ambition = 80

	var ir := ImmortalRecord.new()
	ir.id = &"test_immortal"
	ir.character = c
	ir.accumulated_legend = 50

	assert_eq(ir.id, &"test_immortal")
	assert_eq(ir.character.name, "Test")
	assert_eq(ir.character.ambition, 80)
	assert_eq(ir.accumulated_legend, 50)


func test_is_player():
	var player := ImmortalRecord.new()
	player.id = &"player"
	assert_true(player.is_player())

	var other := ImmortalRecord.new()
	other.id = &"the_veil_founder"
	assert_false(other.is_player())


func test_save_load_roundtrip():
	var c := CharacterRecord.new()
	c.id = &"embedded_char"
	c.name = "Embedded"
	c.intellect = 95
	c.curiosity = 90

	var ir := ImmortalRecord.new()
	ir.id = &"roundtrip_immortal"
	ir.canonical_name = "Secret Name"
	ir.character = c
	ir.current_cover_identity = &"merchant_cover"
	ir.accumulated_legend = 25
	ir.society_id = &"the_veil"

	var path: String = "user://test_immortal_record_roundtrip.tres"
	ResourceSaver.save(ir, path)
	var loaded: ImmortalRecord = ResourceLoader.load(path) as ImmortalRecord
	assert_not_null(loaded)
	assert_eq(loaded.id, &"roundtrip_immortal")
	assert_eq(loaded.canonical_name, "Secret Name")
	assert_eq(loaded.character.intellect, 95)
	assert_eq(loaded.society_id, &"the_veil")
	DirAccess.remove_absolute(path)
