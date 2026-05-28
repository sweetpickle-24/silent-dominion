extends GutTest

# Integration: a rigid + grievance-heavy religion accumulates reform_potential,
# crosses threshold, fractures, schism child created with correct attributes.

var _religion: ReligionIdeology


func before_each():
	_religion = ReligionIdeology.new()
	_religion.name = "ReligionIdeology"
	add_child(_religion)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_religion):
		if _religion._tick_sub:
			eb.unsubscribe(_religion._tick_sub)
		remove_child(_religion)
		_religion.free()


func test_schism_fires_on_reform_threshold():
	# Create a highly rigid religion in dominance phase
	var parent := ReligionRecord.new()
	parent.id = &"rigid_faith"
	parent.display_name = "Rigid Faith"
	parent.doctrinal_rigidity = 85
	parent.institutional_strength = 70
	parent.popular_depth = 60
	parent.ecumenical_openness = 15
	parent.reform_potential = 75  # close to threshold (80)
	parent.lifecycle_phase = &"dominance"
	_religion._religions[&"rigid_faith"] = parent

	# Give it significant presence with grievance
	_religion.set_presence(&"athens", &"rigid_faith", 30000, 70, true, 5.0)
	_religion.set_presence(&"corinth", &"rigid_faith", 20000, 60, true, 3.0)
	_religion.set_presence(&"sparta", &"rigid_faith", 10000, 50, true, 2.0)
	_religion.set_presence(&"thebes", &"rigid_faith", 15000, 55, true, 4.0)
	_religion.set_presence(&"miletus", &"rigid_faith", 8000, 45, false, 1.0)

	# Collect events
	var schism_events: Array = []
	var lifecycle_events: Array = []
	var eb: Node = get_node("/root/EventBus")
	var sub1 = eb.subscribe(
		preload("res://scripts/data/events/religion_schism_occurred_event.gd"),
		func(e): schism_events.append(e), 50,
	)
	var sub2 = eb.subscribe(
		preload("res://scripts/data/events/religion_lifecycle_phase_changed_event.gd"),
		func(e): lifecycle_events.append(e), 50,
	)

	# Accumulate reform potential until it crosses the threshold
	for i in range(20):
		_religion._update_reform_potential(parent)

	assert_gte(parent.reform_potential, ReligionIdeology.FRACTURE_REFORM_THRESHOLD,
		"Reform potential should cross fracture threshold")

	# Now check lifecycle transition — should fracture
	_religion._check_lifecycle_transitions(parent, 1000)

	# Verify schism fired
	assert_eq(schism_events.size(), 1, "Schism event should fire")
	assert_eq(schism_events[0].parent_religion_id, &"rigid_faith")

	# Verify child religion exists
	var child_id: StringName = schism_events[0].child_religion_id
	var child: ReligionRecord = _religion.religion_record(child_id)
	assert_not_null(child, "Child religion should exist")
	assert_eq(child.parent_religion_id, &"rigid_faith")
	assert_lt(child.doctrinal_rigidity, parent.doctrinal_rigidity,
		"Child should have lower doctrinal rigidity")
	assert_lt(child.institutional_strength, parent.institutional_strength,
		"Child should have lower institutional strength initially")
	assert_lt(child.reform_potential, 20,
		"Child should have low reform potential (fresh)")

	# Parent's reform potential should have drained (was at/above 80, minus 50)
	assert_lte(parent.reform_potential, 50,
		"Parent's reform potential should drain after schism")

	# Parent lifecycle should have changed
	assert_true(lifecycle_events.size() > 0, "Lifecycle event should fire")

	eb.unsubscribe(sub1)
	eb.unsubscribe(sub2)


func test_decline_and_extinction():
	var dying := ReligionRecord.new()
	dying.id = &"dying_faith"
	dying.display_name = "Dying Faith"
	dying.lifecycle_phase = &"consolidation"
	_religion._religions[&"dying_faith"] = dying
	_religion.set_presence(&"athens", &"dying_faith", 50, 5, false, 0.0)

	var ext_events: Array = []
	var eb: Node = get_node("/root/EventBus")
	var sub = eb.subscribe(
		preload("res://scripts/data/events/religion_went_extinct_event.gd"),
		func(e): ext_events.append(e), 50,
	)

	# First transition: should go to decline (few followers)
	_religion._check_lifecycle_transitions(dying, 100)
	assert_eq(dying.lifecycle_phase, &"decline")

	# Reduce followers further → extinction
	_religion.set_presence(&"athens", &"dying_faith", 5, 1, false, 0.0)
	_religion._check_lifecycle_transitions(dying, 200)
	assert_eq(dying.lifecycle_phase, &"extinct")
	assert_eq(ext_events.size(), 1)
	assert_false(dying.is_active())

	eb.unsubscribe(sub)
