extends GutTest

var _languages: Languages

func before_each():
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

func test_language_compositions_drift():
	# Snapshot initial state
	var initial: Dictionary = {}
	var wr: Node = get_node("/root/WorldRegistry")
	for pid: StringName in wr.all_province_ids():
		initial[pid] = _languages.get_composition(pid).duplicate()
	# Run 20 drift periods (~5 years at quarterly cadence)
	for i in range(20):
		_languages._update_languages()
	# Verify at least some regions shifted
	var shifted: int = 0
	for pid: StringName in wr.all_province_ids():
		var current: Dictionary = _languages.get_composition(pid)
		var old: Dictionary = initial.get(pid, {})
		for lid: StringName in current.keys():
			if absf(current[lid] - old.get(lid, 0.0)) > 0.1:
				shifted += 1
				break
	assert_gt(shifted, 0, "Some regions should show language drift over time")
