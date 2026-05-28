extends GutTest

# Verify Kingdom reads real population from Population mechanic for levy + unrest.

var _kingdom: Kingdom
var _population: Population


func before_each():
	_kingdom = Kingdom.new()
	_kingdom.name = "Kingdom"
	add_child(_kingdom)
	_population = Population.new()
	_population.name = "Population"
	add_child(_population)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_population):
		if _population._tick_sub:
			eb.unsubscribe(_population._tick_sub)
		remove_child(_population)
		_population.free()
	if is_instance_valid(_kingdom):
		if _kingdom._tick_sub:
			eb.unsubscribe(_kingdom._tick_sub)
		remove_child(_kingdom)
		_kingdom.free()


func test_levy_uses_population_mechanic():
	# Kingdom with Athens — levy should come from Population.levy_capacity
	var k := KingdomRecord.new()
	k.id = &"test_levy"
	k.display_name = "Test"
	k.ruler_character_id = &"ruler_athens"
	k.capital_place_id = &"athens"
	k.member_place_ids = [&"athens"]
	k.standing_army = 0
	_kingdom._kingdoms[&"test_levy"] = k
	var expected_levy: int = _population.levy_capacity(&"athens")
	var strength: int = _kingdom.derived_military_strength(&"test_levy")
	assert_eq(strength, expected_levy, "Levy should come from Population mechanic")


func test_unrest_includes_demographic_pressure():
	var k := KingdomRecord.new()
	k.id = &"test_unrest"
	k.display_name = "Test"
	k.ruler_character_id = &"ruler_athens"
	k.capital_place_id = &"athens"
	k.member_place_ids = [&"athens"]
	k.tax_level = 40  # below 50, so no tax-based unrest
	k.legitimacy = 60  # above 50, so no legitimacy-based unrest
	k.unrest = 20
	_kingdom._kingdoms[&"test_unrest"] = k
	# Set instability in population → creates migration pressure
	var state: PopulationState = _population.get_state(&"athens")
	if state == null:
		pending("No Athens population state")
		return
	state.stability_factor = 0.3  # very unstable → migration_pressure = 0.7
	var old_unrest: int = k.unrest
	_kingdom._update_unrest(k)
	# Unrest should increase from demographic pressure even though tax and legitimacy are fine
	assert_gt(k.unrest, old_unrest, "Demographic pressure should raise unrest")


func test_place_population_no_longer_drifts_from_place_mechanic():
	# Verify Place mechanic no longer changes population
	var wr: Node = get_node("/root/WorldRegistry")
	var athens: PlaceRecord = wr.get_place(&"athens")
	if athens == null:
		pending("Athens not available")
		return
	var start_pop: int = athens.population
	# Create a Place mechanic and tick it
	var place: Place = Place.new()
	place.name = "Place"
	add_child(place)
	for day in range(365):
		place.update_per_day(day)
	assert_eq(athens.population, start_pop, "Place should not drift population anymore")
	remove_child(place)
	place.free()
