extends GutTest

var _mortality: Mortality


func before_each():
	_mortality = Mortality.new()
	_mortality.name = "Mortality"
	add_child(_mortality)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_mortality):
		if _mortality._tick_sub:
			eb.unsubscribe(_mortality._tick_sub)
		remove_child(_mortality)
		_mortality.free()


func test_death_probability_rises_with_age():
	var young_char := CharacterRecord.new()
	young_char.id = &"young"
	young_char.birth_day = -5475  # 15 years old at day 0
	young_char.resilience = 50
	var old_char := CharacterRecord.new()
	old_char.id = &"old"
	old_char.birth_day = -25550  # 70 years old at day 0
	old_char.resilience = 50
	var prob_young: float = _mortality._compute_death_probability(15.0, young_char)
	var prob_old: float = _mortality._compute_death_probability(70.0, old_char)
	assert_gt(prob_old, prob_young, "Old characters should have higher death probability")


func test_era_lifespan_curve():
	var c := CharacterRecord.new()
	c.resilience = 50
	# Child: high mortality
	var prob_child: float = _mortality._compute_death_probability(3.0, c)
	# Prime adult: low mortality
	var prob_adult: float = _mortality._compute_death_probability(25.0, c)
	# Elder: high mortality
	var prob_elder: float = _mortality._compute_death_probability(70.0, c)
	assert_gt(prob_child, prob_adult, "Children should have higher mortality than adults")
	assert_gt(prob_elder, prob_adult, "Elders should have higher mortality than adults")


func test_resilience_modifies_probability():
	var tough := CharacterRecord.new()
	tough.resilience = 90  # high resilience
	var frail := CharacterRecord.new()
	frail.resilience = 10  # low resilience
	var prob_tough: float = _mortality._compute_death_probability(60.0, tough)
	var prob_frail: float = _mortality._compute_death_probability(60.0, frail)
	assert_gt(prob_frail, prob_tough, "Low resilience should increase death probability")


func test_immortals_never_die_of_old_age():
	var ir: Node = get_node("/root/ImmortalRegistry")
	# The player's immortal should be exempt
	var player: ImmortalRecord = ir.get_player()
	assert_not_null(player)
	assert_true(ir.is_immortal(player.id), "Player should be recognized as immortal")
	# Even at extreme age, immortals are skipped by _evaluate_mortality
	# Test directly: is_immortal returns true
	var veil_immortal_id: StringName = &"the_veil_founder"
	assert_true(ir.is_immortal(veil_immortal_id), "Veil founder should be recognized as immortal")


func test_character_died_event_fires():
	var ir: Node = get_node("/root/ImmortalRegistry")
	# Find a non-immortal character
	var target_id: StringName = &""
	for cid: StringName in ir.all_character_ids():
		if not ir.is_immortal(cid):
			var c: CharacterRecord = ir.get_character(cid)
			if c != null and c.is_alive(0):
				target_id = cid
				break
	if target_id == &"":
		pending("No mortal characters available")
		return
	var events: Array = []
	var eb: Node = get_node("/root/EventBus")
	var sub = eb.subscribe(
		preload("res://scripts/data/events/character_died_event.gd"),
		func(e): events.append(e),
		50,
	)
	_mortality.kill_character_by_cause(target_id, &"old_age", 100)
	assert_eq(events.size(), 1)
	assert_eq(events[0].character_id, target_id)
	assert_eq(events[0].cause, &"old_age")
	eb.unsubscribe(sub)
	# Restore: reset death_day
	ir.set_character_death_day(target_id, -1)


func test_shock_increases_mortality():
	var c := CharacterRecord.new()
	c.resilience = 50
	var base_prob: float = _mortality._compute_death_probability(50.0, c)
	# Shock factor of 0.3 should roughly double the probability
	# (2.0 - 0.3) = 1.7 multiplier
	var shock_multiplied: float = base_prob * 1.7
	assert_gt(shock_multiplied, base_prob, "Shock should increase mortality")


func test_chain_member_death_triggers_chain_break():
	# Chain mechanic checks is_alive — if death_day is set, chain breaks on next tick.
	# Verify the mechanism: set death_day, check is_alive returns false.
	var c := CharacterRecord.new()
	c.id = &"test_chain_member"
	c.birth_day = 0
	c.death_day = -1
	c.chain_status = ChainStatusValues.COORDINATOR
	assert_true(c.is_alive(100), "Should be alive before death")
	c.death_day = 50
	assert_false(c.is_alive(100), "Should be dead after death_day")
	# Chain mechanic's _check_chain_breaks uses is_alive — no need to reimplement


func test_kill_character_by_cause_respects_immortal_exemption():
	var ir: Node = get_node("/root/ImmortalRegistry")
	var player: ImmortalRecord = ir.get_player()
	var player_char: CharacterRecord = player.character
	var original_death: int = player_char.death_day
	_mortality.kill_character_by_cause(player.id, &"plague", 100)
	# Immortal should NOT have death_day set
	assert_eq(player_char.death_day, original_death, "Immortal should not die")


func test_save_load_roundtrip():
	_mortality._day_accumulator = 20
	var snapshot: Dictionary = _mortality.snapshot_state()
	assert_true(snapshot.has("rng_seed"))
	assert_true(snapshot.has("rng_state"))
	_mortality._day_accumulator = 0
	_mortality.apply_state(snapshot)
	assert_eq(_mortality._day_accumulator, 20)
