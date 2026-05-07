extends GutTest

# ImmortalRegistry is an autoload that loads at startup from data/.


func test_immortals_loaded():
	var ir: Node = get_node("/root/ImmortalRegistry")
	assert_eq(ir.immortal_count(), 2, "Should have loaded 2 immortals")


func test_characters_loaded():
	var ir: Node = get_node("/root/ImmortalRegistry")
	assert_eq(ir.character_count(), 9, "Should have loaded 9 characters")


func test_get_player():
	var ir: Node = get_node("/root/ImmortalRegistry")
	var player: ImmortalRecord = ir.get_player()
	assert_not_null(player)
	assert_eq(player.id, &"player")
	assert_true(player.is_player())
	assert_not_null(player.character)
	assert_eq(player.character.current_place, &"athens")


func test_get_immortal_unknown():
	var ir: Node = get_node("/root/ImmortalRegistry")
	assert_null(ir.get_immortal(&"nonexistent"))


func test_get_character():
	var ir: Node = get_node("/root/ImmortalRegistry")
	var theron: CharacterRecord = ir.get_character(&"theron")
	assert_not_null(theron)
	assert_eq(theron.name, "Theron of Piraeus")
	assert_eq(theron.chain_status, ChainStatusValues.LIEUTENANT)
	assert_eq(theron.current_place, &"athens")


func test_get_character_record_any():
	var ir: Node = get_node("/root/ImmortalRegistry")
	# Works for character ids
	var theron: CharacterRecord = ir.get_character_record_any(&"theron")
	assert_not_null(theron)
	assert_eq(theron.name, "Theron of Piraeus")
	# Works for immortal ids (returns the embedded character)
	var player_char: CharacterRecord = ir.get_character_record_any(&"player")
	assert_not_null(player_char)
	assert_eq(player_char.current_place, &"athens")
	# Returns null for unknown ids
	assert_null(ir.get_character_record_any(&"nonexistent"))


func test_characters_at_place():
	var ir: Node = get_node("/root/ImmortalRegistry")
	var athens_chars: Array = ir.characters_at_place(&"athens")
	# Theron, Helena, Kleitos, Aspasia, Eumenes are at Athens
	assert_eq(athens_chars.size(), 5)
	var miletus_chars: Array = ir.characters_at_place(&"miletus")
	# Sosthenes is at Miletus
	assert_eq(miletus_chars.size(), 1)
	assert_eq(miletus_chars[0].id, &"sosthenes")


func test_all_immortal_ids():
	var ir: Node = get_node("/root/ImmortalRegistry")
	var ids: Array = ir.all_immortal_ids()
	assert_eq(ids.size(), 2)
	assert_has(ids, &"player")
	assert_has(ids, &"the_veil_founder")
