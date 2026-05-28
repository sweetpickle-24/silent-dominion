extends GutTest

# Integration: generate many characters, make one a host and investigate another,
# advance time → verify GC collects the irrelevant ones but keeps host + investigated.

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


func test_gc_keeps_relevant_collects_irrelevant():
	var ir: Node = get_node("/root/ImmortalRegistry")
	# Generate 10 characters
	var gen_ids: Array[StringName] = []
	for i in range(10):
		var c: CharacterRecord = _chargen.generate_character_at(&"athens", 100 + i)
		if c != null:
			gen_ids.append(c.id)
	assert_gte(gen_ids.size(), 5, "Should have generated several characters")
	# Make first one a host (relevant)
	var host_id: StringName = gen_ids[0]
	var host: CharacterRecord = ir.get_character(host_id)
	if host != null:
		host.chain_status = ChainStatusValues.HOST
	# Investigate second one (relevant — heat > 0)
	var investigated_id: StringName = gen_ids[1]
	var investigated: CharacterRecord = ir.get_character(investigated_id)
	if investigated != null:
		investigated.heat = 15
	# Kill all of them
	for gid: StringName in gen_ids:
		ir.set_character_death_day(gid, 200)
	# Advance past retention
	var tk: Node = get_node("/root/TimeKeeper")
	var saved_day: int = tk.current_day
	tk.current_day = 200 + CharGeneration.GC_DEAD_RETENTION_DAYS + 1
	_chargen._run_gc()
	tk.current_day = saved_day
	# Host and investigated should survive
	assert_true(_chargen.is_generated(host_id), "Host should survive GC")
	assert_true(_chargen.is_generated(investigated_id), "Investigated character should survive GC")
	# Irrelevant ones should be collected
	var survived_count: int = 0
	for gid: StringName in gen_ids:
		if _chargen.is_generated(gid):
			survived_count += 1
	assert_eq(survived_count, 2, "Only host + investigated should survive GC")
	# Clean up
	if host != null:
		host.chain_status = ChainStatusValues.NONE
	if investigated != null:
		investigated.heat = 0
	for gid: StringName in gen_ids:
		ir.set_character_death_day(gid, -1)
