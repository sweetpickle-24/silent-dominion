extends GutTest

var _helpers: Node

func before_each():
	_helpers = autofree(preload("res://scripts/utils/helpers.gd").new())
	_helpers.name = "Helpers"
	add_child_autoqfree(_helpers)

func _make_character(traits: Dictionary = {}) -> CharacterRecord:
	var c := CharacterRecord.new()
	c.id = &"test_char"
	c.ambition = traits.get("ambition", 50)
	c.paranoia = traits.get("paranoia", 50)
	c.loyalty = traits.get("loyalty", 50)
	c.piety = traits.get("piety", 50)
	c.intellect = traits.get("intellect", 50)
	c.greed = traits.get("greed", 50)
	c.ruthlessness = traits.get("ruthlessness", 50)
	c.curiosity = traits.get("curiosity", 50)
	c.resilience = traits.get("resilience", 50)
	c.charisma = traits.get("charisma", 50)
	c.public_position_tier = traits.get("public_position_tier", PublicPositionValues.MINOR)
	return c

func test_dangerous_ruler_pattern():
	var c := _make_character({"ambition": 80, "paranoia": 75})
	assert_true(_helpers.has_compound_trait_pattern(c, &"dangerous_ruler"))
	# Below threshold
	var c2 := _make_character({"ambition": 80, "paranoia": 60})
	assert_false(_helpers.has_compound_trait_pattern(c2, &"dangerous_ruler"))

func test_hunter_pattern():
	var c := _make_character({"intellect": 85, "curiosity": 90})
	assert_true(_helpers.has_compound_trait_pattern(c, &"hunter"))
	var c2 := _make_character({"intellect": 85, "curiosity": 50})
	assert_false(_helpers.has_compound_trait_pattern(c2, &"hunter"))

func test_lieutenant_ideal_pattern():
	var c := _make_character({"loyalty": 80, "resilience": 75})
	assert_true(_helpers.has_compound_trait_pattern(c, &"lieutenant_ideal"))

func test_corruption_profile_pattern():
	var c := _make_character({"greed": 80, "loyalty": 20})
	assert_true(_helpers.has_compound_trait_pattern(c, &"corruption_profile"))
	# High greed but also high loyalty — not corruption profile
	var c2 := _make_character({"greed": 80, "loyalty": 60})
	assert_false(_helpers.has_compound_trait_pattern(c2, &"corruption_profile"))

func test_religious_catalyst_pattern():
	var c := _make_character({"piety": 85, "charisma": 80})
	assert_true(_helpers.has_compound_trait_pattern(c, &"religious_catalyst"))

func test_apex_predator_pattern():
	var c := _make_character({"paranoia": 80, "ruthlessness": 90, "public_position_tier": PublicPositionValues.MAXIMAL})
	assert_true(_helpers.has_compound_trait_pattern(c, &"apex_predator"))
	# Same traits but not maximal position — false
	var c2 := _make_character({"paranoia": 80, "ruthlessness": 90, "public_position_tier": PublicPositionValues.HIGH})
	assert_false(_helpers.has_compound_trait_pattern(c2, &"apex_predator"))

func test_null_character_returns_false():
	assert_false(_helpers.has_compound_trait_pattern(null, &"hunter"))
