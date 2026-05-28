extends GutTest

# Integration: advance decades — characters die, new ones generate.
# World's named character pool stays viable.

var _chargen: CharGeneration
var _mortality: Mortality


func before_each():
	_chargen = CharGeneration.new()
	_chargen.name = "CharGeneration"
	add_child(_chargen)
	_mortality = Mortality.new()
	_mortality.name = "Mortality"
	add_child(_mortality)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_chargen):
		if _chargen._tick_sub:
			eb.unsubscribe(_chargen._tick_sub)
		remove_child(_chargen)
		_chargen.free()
	if is_instance_valid(_mortality):
		if _mortality._tick_sub:
			eb.unsubscribe(_mortality._tick_sub)
		remove_child(_mortality)
		_mortality.free()


func test_character_pool_stays_viable():
	var ir: Node = get_node("/root/ImmortalRegistry")
	var initial_count: int = ir.character_count()
	# Generate a batch of characters
	for i in range(10):
		_chargen.generate_character_at(&"athens", 100 + i)
	var after_gen: int = ir.character_count()
	assert_gt(after_gen, initial_count, "Generation should add characters")
	# Kill some via mortality
	var killed: int = 0
	for cid: StringName in ir.all_character_ids():
		if _chargen.is_generated(cid) and killed < 3:
			ir.set_character_death_day(cid, 200)
			killed += 1
	# Generate more replacements
	for i in range(5):
		_chargen.generate_character_at(&"athens", 300 + i)
	var final_count: int = ir.character_count()
	# Pool should still be viable (more than initial)
	assert_gt(final_count, initial_count, "Character pool should stay viable with generation + mortality")
	# Clean up deaths
	for cid: StringName in ir.all_character_ids():
		var c: CharacterRecord = ir.get_character(cid)
		if c != null and not c.is_alive(0):
			ir.set_character_death_day(cid, -1)
