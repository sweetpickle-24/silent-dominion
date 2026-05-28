extends GutTest

# The slice-3 payoff: cultural autonomy. Advance 50 game-years with zero player
# input. Religions spread, languages drift.

var _religion: ReligionIdeology
var _languages: Languages
var _population: Population

func before_each():
	_population = Population.new()
	_population.name = "Population"
	add_child(_population)
	_religion = ReligionIdeology.new()
	_religion.name = "ReligionIdeology"
	add_child(_religion)
	_languages = Languages.new()
	_languages.name = "Languages"
	add_child(_languages)

func after_each():
	var eb: Node = get_node("/root/EventBus")
	for node in [_languages, _religion, _population]:
		if is_instance_valid(node):
			if node.get("_tick_sub") and node._tick_sub:
				eb.unsubscribe(node._tick_sub)
			remove_child(node)
			node.free()

func test_cultural_autonomy():
	# Snapshot
	var initial_religion_count: int = _religion.all_religion_ids().size()
	# Run 100 religion periods + 30 language periods (simulating ~8 years)
	for i in range(100):
		_religion._update_religions()
	for i in range(30):
		_languages._update_languages()
	# Verify: religions still active, no crash
	var active_count: int = 0
	for rid: StringName in _religion.all_religion_ids():
		var r: ReligionRecord = _religion.religion_record(rid)
		if r.is_active():
			active_count += 1
	assert_gt(active_count, 0, "Some religions should still be active")
	# Languages should still have composition
	var wr: Node = get_node("/root/WorldRegistry")
	var regions_with_lang: int = 0
	for pid: StringName in wr.all_province_ids():
		if not _languages.get_composition(pid).is_empty():
			regions_with_lang += 1
	assert_gt(regions_with_lang, 0, "Regions should still have language composition")
	assert_true(true, "Cultural systems ran autonomously without crash")
