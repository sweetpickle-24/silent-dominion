extends GutTest

# Test the §35.10 tiered GC and condition-weighting.

var _chargen: CharGeneration


func before_each():
	_chargen = CharGeneration.new()
	_chargen.name = "CharGeneration"
	add_child(_chargen)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_chargen):
		if _chargen._tick_sub:
			eb.unsubscribe(_chargen._tick_sub)
		remove_child(_chargen)
		_chargen.free()


func test_gc_collects_irrelevant_dead_characters():
	var ir: Node = get_node("/root/ImmortalRegistry")
	# Generate a character
	var c: CharacterRecord = _chargen.generate_character_at(&"athens", 100)
	assert_not_null(c)
	var gen_id: StringName = c.id
	# Kill it
	ir.set_character_death_day(gen_id, 100)
	# Set time far enough for GC to collect (> GC_DEAD_RETENTION_DAYS)
	var tk: Node = get_node("/root/TimeKeeper")
	var saved_day: int = tk.current_day
	tk.current_day = 100 + CharGeneration.GC_DEAD_RETENTION_DAYS + 1
	_chargen._run_gc()
	tk.current_day = saved_day
	# Character should be collected
	assert_false(_chargen.is_generated(gen_id), "Dead irrelevant character should be GC'd")
	var found: CharacterRecord = ir.get_character(gen_id)
	assert_null(found, "Character should be unregistered from ImmortalRegistry")


func test_gc_keeps_chain_members():
	var ir: Node = get_node("/root/ImmortalRegistry")
	var c: CharacterRecord = _chargen.generate_character_at(&"athens", 200)
	assert_not_null(c)
	var gen_id: StringName = c.id
	# Make it a chain member
	c.chain_status = ChainStatusValues.HOST
	# Kill it
	ir.set_character_death_day(gen_id, 200)
	var tk: Node = get_node("/root/TimeKeeper")
	var saved_day: int = tk.current_day
	tk.current_day = 200 + CharGeneration.GC_DEAD_RETENTION_DAYS + 1
	_chargen._run_gc()
	tk.current_day = saved_day
	# Should NOT be collected — chain member is relevant
	assert_true(_chargen.is_generated(gen_id), "Chain member should survive GC")
	# Clean up
	c.chain_status = ChainStatusValues.NONE
	ir.set_character_death_day(gen_id, -1)


func test_gc_keeps_society_members():
	var ir: Node = get_node("/root/ImmortalRegistry")
	var c: CharacterRecord = _chargen.generate_character_at(&"athens", 300)
	assert_not_null(c)
	c.society_id = &"the_veil"
	ir.set_character_death_day(c.id, 300)
	var tk: Node = get_node("/root/TimeKeeper")
	var saved_day: int = tk.current_day
	tk.current_day = 300 + CharGeneration.GC_DEAD_RETENTION_DAYS + 1
	_chargen._run_gc()
	tk.current_day = saved_day
	assert_true(_chargen.is_generated(c.id), "Society member should survive GC")
	c.society_id = &""
	ir.set_character_death_day(c.id, -1)


func test_gc_keeps_investigated_characters():
	var ir: Node = get_node("/root/ImmortalRegistry")
	var c: CharacterRecord = _chargen.generate_character_at(&"athens", 400)
	assert_not_null(c)
	c.heat = 20  # was investigated
	ir.set_character_death_day(c.id, 400)
	var tk: Node = get_node("/root/TimeKeeper")
	var saved_day: int = tk.current_day
	tk.current_day = 400 + CharGeneration.GC_DEAD_RETENTION_DAYS + 1
	_chargen._run_gc()
	tk.current_day = saved_day
	assert_true(_chargen.is_generated(c.id), "Investigated character should survive GC")
	c.heat = 0
	ir.set_character_death_day(c.id, -1)


func test_gc_does_not_collect_within_retention():
	var ir: Node = get_node("/root/ImmortalRegistry")
	var c: CharacterRecord = _chargen.generate_character_at(&"athens", 500)
	assert_not_null(c)
	ir.set_character_death_day(c.id, 500)
	var tk: Node = get_node("/root/TimeKeeper")
	var saved_day: int = tk.current_day
	tk.current_day = 500 + 100  # well within retention window
	_chargen._run_gc()
	tk.current_day = saved_day
	assert_true(_chargen.is_generated(c.id), "Recently dead should not be GC'd")
	ir.set_character_death_day(c.id, -1)
