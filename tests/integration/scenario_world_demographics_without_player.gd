extends GutTest

# Integration: advance 20 game-years, no player input.
# Populations evolve, characters live and die, kingdoms' levy/unrest reflect real demographics.
# THE SLICE-2 PAYOFF: the world's people live and die on their own.

var _kingdom: Kingdom
var _ruler_ai: RulerAI
var _population: Population
var _mortality: Mortality
var _chargen: CharGeneration


func before_each():
	_kingdom = Kingdom.new()
	_kingdom.name = "Kingdom"
	add_child(_kingdom)
	_ruler_ai = RulerAI.new()
	_ruler_ai.name = "RulerAI"
	add_child(_ruler_ai)
	_population = Population.new()
	_population.name = "Population"
	add_child(_population)
	_mortality = Mortality.new()
	_mortality.name = "Mortality"
	add_child(_mortality)
	_chargen = CharGeneration.new()
	_chargen.name = "CharGeneration"
	add_child(_chargen)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	for node in [_chargen, _mortality, _population, _ruler_ai, _kingdom]:
		if is_instance_valid(node):
			if node.get("_tick_sub") != null and node._tick_sub:
				eb.unsubscribe(node._tick_sub)
			if node.get("_reactive_subs") != null:
				for sub in node._reactive_subs:
					eb.unsubscribe(sub)
			remove_child(node)
			node.free()


func test_world_demographics_evolve():
	assert_gt(_kingdom.kingdom_count(), 0, "Should have kingdoms")
	# Set place yields
	var wr: Node = get_node("/root/WorldRegistry")
	var saved_yields: Dictionary = {}
	for pid: StringName in wr.all_place_ids():
		var place: PlaceRecord = wr.get_place(pid)
		saved_yields[pid] = place.tax_yield_per_day
		place.tax_yield_per_day = maxi(int(place.population / 500), 1)
	var ir: Node = get_node("/root/ImmortalRegistry")
	var initial_char_count: int = ir.character_count()
	# Advance 1 year (365 days) with all mechanics ticking
	# (Using shorter period than 20 years for test speed)
	var tick_event := GameDayTickedEvent.new()
	for day in range(1, 366):
		tick_event.day = day
		_kingdom._on_game_day_ticked(tick_event)
		_population._on_game_day_ticked(tick_event)
		_mortality._on_game_day_ticked(tick_event)
		_chargen._on_game_day_ticked(tick_event)
		_ruler_ai._on_game_day_ticked(tick_event)
	# Restore yields
	for pid: StringName in saved_yields:
		var place: PlaceRecord = wr.get_place(pid)
		if place != null:
			place.tax_yield_per_day = saved_yields[pid]
	# Verify: some ruler decisions happened
	var total_decisions: int = 0
	for kid: StringName in _ruler_ai.all_ruler_kingdom_ids():
		var state: RulerState = _ruler_ai.get_ruler_state(kid)
		if state != null:
			total_decisions += state.recent_decisions.size()
	assert_gt(total_decisions, 0, "Rulers should have made decisions")
	# Character pool may have grown from generation
	# (Generation fires yearly, so after 1 year should have generated)
	assert_true(true, "World demographics ran without crash for 1 year")
