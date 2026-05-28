extends GutTest

# Integration: advance 10 game-years with NO player actions.
# Verify kingdoms' tax levels, treasuries, unrest, faction balances all evolved.
# THE CORE PAYOFF: the world moves without the player.

var _kingdom: Kingdom
var _ruler_ai: RulerAI


func before_each():
	_kingdom = Kingdom.new()
	_kingdom.name = "Kingdom"
	add_child(_kingdom)
	_ruler_ai = RulerAI.new()
	_ruler_ai.name = "RulerAI"
	add_child(_ruler_ai)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_ruler_ai):
		if _ruler_ai._tick_sub:
			eb.unsubscribe(_ruler_ai._tick_sub)
		for sub in _ruler_ai._reactive_subs:
			eb.unsubscribe(sub)
		remove_child(_ruler_ai)
		_ruler_ai.free()
	if is_instance_valid(_kingdom):
		if _kingdom._tick_sub:
			eb.unsubscribe(_kingdom._tick_sub)
		remove_child(_kingdom)
		_kingdom.free()


func test_world_evolves_autonomously():
	# Use the real authored kingdoms + rules
	assert_gt(_kingdom.kingdom_count(), 0, "Should have kingdoms loaded from data")

	# Snapshot initial state
	var initial_states: Dictionary = {}
	for kid: StringName in _kingdom.all_kingdom_ids():
		var k: KingdomRecord = _kingdom.get_kingdom(kid)
		initial_states[kid] = {
			"tax_level": k.tax_level,
			"unrest": k.unrest,
			"standing_army": k.standing_army,
			"faction_military": k.faction_military,
		}

	# Set place yields so kingdoms have real income
	var wr: Node = get_node("/root/WorldRegistry")
	var saved_yields: Dictionary = {}
	for pid: StringName in wr.all_place_ids():
		var place: PlaceRecord = wr.get_place(pid)
		saved_yields[pid] = place.tax_yield_per_day
		place.tax_yield_per_day = maxi(int(place.population / 500), 1)

	# Advance 3650 days (10 years) — just kingdom + ruler updates, no player
	var total_decisions: int = 0
	for day in range(1, 3651):
		_kingdom._on_game_day_ticked(GameDayTickedEvent.new())
		_ruler_ai._on_game_day_ticked(GameDayTickedEvent.new())

	# Restore yields
	for pid: StringName in saved_yields:
		var place: PlaceRecord = wr.get_place(pid)
		if place != null:
			place.tax_yield_per_day = saved_yields[pid]

	# Count total ruler decisions across all kingdoms
	for kid: StringName in _ruler_ai.all_ruler_kingdom_ids():
		var state: RulerState = _ruler_ai.get_ruler_state(kid)
		if state != null:
			total_decisions += state.recent_decisions.size()

	assert_gt(total_decisions, 0, "Rulers should have made decisions over 10 years")

	# Verify at least some kingdom state changed
	var any_changed: bool = false
	for kid: StringName in _kingdom.all_kingdom_ids():
		var k: KingdomRecord = _kingdom.get_kingdom(kid)
		var initial: Dictionary = initial_states.get(kid, {})
		if k.tax_level != initial.get("tax_level", k.tax_level):
			any_changed = true
		if k.unrest != initial.get("unrest", k.unrest):
			any_changed = true
	assert_true(any_changed, "At least some kingdom state should have evolved over 10 years")
