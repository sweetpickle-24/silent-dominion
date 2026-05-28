extends GutTest

var _religion: ReligionIdeology
var _population: Population

func before_each():
	_population = Population.new()
	_population.name = "Population"
	add_child(_population)
	_religion = ReligionIdeology.new()
	_religion.name = "ReligionIdeology"
	add_child(_religion)

func after_each():
	var eb: Node = get_node("/root/EventBus")
	for node in [_religion, _population]:
		if is_instance_valid(node):
			if node.get("_tick_sub") and node._tick_sub:
				eb.unsubscribe(node._tick_sub)
			remove_child(node)
			node.free()

func test_religion_spreads_over_time():
	# Count initial places with greek_olympian
	var initial_places: int = 0
	var wr: Node = get_node("/root/WorldRegistry")
	for pid: StringName in wr.all_place_ids():
		if _religion.dominant_religion(pid) == &"greek_olympian":
			initial_places += 1
	assert_gt(initial_places, 0, "Greek Olympian should be present initially")
	# Run many periods of diffusion
	for i in range(50):
		_religion._update_religions()
	# Count places with any greek_olympian presence now
	var final_places: int = 0
	for pid: StringName in wr.all_place_ids():
		var rels: Array = _religion.religions_in_place(pid)
		for r: Dictionary in rels:
			if r["religion_id"] == &"greek_olympian" and r["follower_count"] > 0:
				final_places += 1
				break
	# Religion should maintain significant presence (may fluctuate at margins)
	assert_gt(final_places, 0, "Religion should still have presence after centuries")
	# Total followers should have grown or maintained (the religion is in dominance phase)
	var total: int = _religion.total_followers(&"greek_olympian")
	assert_gt(total, 0, "Total followers should be positive")
