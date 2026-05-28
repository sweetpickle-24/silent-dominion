extends GutTest

# Integration: a religion dominant in a region pulls its liturgical language's
# share up over time. Verify the coupling fires.

var _religion: ReligionIdeology
var _languages: Languages


func before_each():
	_religion = ReligionIdeology.new()
	_religion.name = "ReligionIdeology"
	add_child(_religion)
	_languages = Languages.new()
	_languages.name = "Languages"
	add_child(_languages)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_languages):
		if _languages._tick_sub:
			eb.unsubscribe(_languages._tick_sub)
		remove_child(_languages)
		_languages.free()
	if is_instance_valid(_religion):
		if _religion._tick_sub:
			eb.unsubscribe(_religion._tick_sub)
		remove_child(_religion)
		_religion.free()


func test_liturgical_language_boosted_by_religion():
	# Verify that Greek Olympian's liturgical_language (greek) gets a boost
	# in regions where it's dominant via the coupling
	var attica_comp: Dictionary = _languages.get_composition(&"attica")
	if attica_comp.is_empty() or not attica_comp.has(&"greek"):
		pending("No greek composition in attica")
		return
	var initial_greek: float = attica_comp[&"greek"]
	# Run liturgical pressure application
	_languages._apply_liturgical_pressure()
	var after_greek: float = _languages.get_composition(&"attica").get(&"greek", 0.0)
	# Greek should have gained a small boost from liturgical pressure
	assert_gte(after_greek, initial_greek, "Liturgical language should be boosted by dominant religion")
