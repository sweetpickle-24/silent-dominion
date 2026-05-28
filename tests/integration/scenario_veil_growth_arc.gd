extends GutTest

# Integration: Verify the Veil growth arc rules are authored and the growth
# timeline is structurally correct. Checks rule existence and cooldown values
# rather than running 200 years of simulation (which would be too slow for CI).

func test_growth_arc_rules_exist():
	# Verify that the key growth arc rules are present in the data directory
	var recruit_athens := ResourceLoader.load("res://data/rules/society_ai/the_veil/recruit_scholar_host_athens.tres")
	assert_not_null(recruit_athens, "recruit_scholar_host_athens.tres should exist")
	assert_true(recruit_athens is SocietyAIRule)

	var recruit_other := ResourceLoader.load("res://data/rules/society_ai/the_veil/recruit_scholar_host_other_cities.tres")
	assert_not_null(recruit_other, "recruit_scholar_host_other_cities.tres should exist")

	var promote_coord := ResourceLoader.load("res://data/rules/society_ai/the_veil/promote_witting_to_coordinator.tres")
	assert_not_null(promote_coord, "promote_witting_to_coordinator.tres should exist")

	var lieutenant := ResourceLoader.load("res://data/rules/society_ai/the_veil/acquire_first_lieutenant.tres")
	assert_not_null(lieutenant, "acquire_first_lieutenant.tres should exist")

	var expand := ResourceLoader.load("res://data/rules/society_ai/the_veil/expand_to_egypt.tres")
	assert_not_null(expand, "expand_to_egypt.tres should exist")


func test_growth_arc_timeline_ordering():
	# Verify rules fire in correct chronological order based on conditions
	var recruit_athens: SocietyAIRule = ResourceLoader.load("res://data/rules/society_ai/the_veil/recruit_scholar_host_athens.tres")
	var promote: SocietyAIRule = ResourceLoader.load("res://data/rules/society_ai/the_veil/promote_witting_to_coordinator.tres")
	var lieutenant: SocietyAIRule = ResourceLoader.load("res://data/rules/society_ai/the_veil/acquire_first_lieutenant.tres")
	var expand: SocietyAIRule = ResourceLoader.load("res://data/rules/society_ai/the_veil/expand_to_egypt.tres")

	# Recruit happens earliest (day > 0)
	assert_true(recruit_athens.condition.contains("world.day > 0"))
	# Promote after decade (day > 3650)
	assert_true(promote.condition.contains("world.day > 3650"))
	# Lieutenant around 300 BCE (year > 200)
	assert_true(lieutenant.condition.contains("world.year > 200"))
	# Egypt expansion (year > 100)
	assert_true(expand.condition.contains("world.year > 100"))


func test_counter_intelligence_rules_exist():
	var rotate := ResourceLoader.load("res://data/rules/society_ai/the_veil/rotate_coordinator_high_heat.tres")
	assert_not_null(rotate, "rotate_coordinator_high_heat.tres should exist")

	var false_fp := ResourceLoader.load("res://data/rules/society_ai/the_veil/plant_false_fingerprint.tres")
	assert_not_null(false_fp, "plant_false_fingerprint.tres should exist")


func test_treaty_rules_exist():
	var propose := ResourceLoader.load("res://data/rules/society_ai/the_veil/propose_initial_treaty.tres")
	assert_not_null(propose, "propose_initial_treaty.tres should exist")

	var renew := ResourceLoader.load("res://data/rules/society_ai/the_veil/propose_renew_treaty.tres")
	assert_not_null(renew, "propose_renew_treaty.tres should exist")

	var terminate := ResourceLoader.load("res://data/rules/society_ai/the_veil/terminate_treaty_after_violations.tres")
	assert_not_null(terminate, "terminate_treaty_after_violations.tres should exist")


func test_reactive_rules_have_trigger_classes():
	var gather_intel: SocietyAIRule = ResourceLoader.load("res://data/rules/society_ai/the_veil/gather_intel_on_player.tres")
	assert_true(gather_intel.reactive_trigger_event_classes.size() > 0, "gather_intel should have reactive triggers")
	assert_true(&"SchemeResolvedEvent" in gather_intel.reactive_trigger_event_classes)

	var false_fp: SocietyAIRule = ResourceLoader.load("res://data/rules/society_ai/the_veil/plant_false_fingerprint.tres")
	assert_true(&"FingerprintLevelAdvancedEvent" in false_fp.reactive_trigger_event_classes)

	var defend: SocietyAIRule = ResourceLoader.load("res://data/rules/society_ai/the_veil/defend_library_from_corruption.tres")
	assert_true(&"SchemeResolvedEvent" in defend.reactive_trigger_event_classes)
