extends GutTest

var _kingdom: Kingdom
var _religion: ReligionIdeology

func before_each():
	_kingdom = Kingdom.new()
	_kingdom.name = "Kingdom"
	add_child(_kingdom)
	_religion = ReligionIdeology.new()
	_religion.name = "ReligionIdeology"
	add_child(_religion)

func after_each():
	var eb: Node = get_node("/root/EventBus")
	for node in [_religion, _kingdom]:
		if is_instance_valid(node):
			if node.get("_tick_sub") and node._tick_sub:
				eb.unsubscribe(node._tick_sub)
			remove_child(node)
			node.free()

func test_dominant_religion_of_kingdom():
	# Athens kingdom's capital is Athens → dominant religion should be greek_olympian
	var dom: StringName = _kingdom.dominant_religion_of(&"athens")
	assert_eq(dom, &"greek_olympian", "Athens kingdom should have Greek Olympian as dominant religion")

func test_dominant_religion_tracks_capital():
	# Persia → capital persepolis → zoroastrianism
	var dom: StringName = _kingdom.dominant_religion_of(&"achaemenid_persia")
	assert_eq(dom, &"zoroastrianism", "Persia should have Zoroastrianism")
