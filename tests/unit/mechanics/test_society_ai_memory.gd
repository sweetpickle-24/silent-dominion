extends GutTest

var _ai: SocietyAI
var _action: Action


func before_each():
	_action = Action.new()
	_action.name = "Action"
	add_child(_action)
	_ai = SocietyAI.new()
	_ai.name = "SocietyAI"
	add_child(_ai)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_ai):
		if _ai._tick_sub:
			eb.unsubscribe(_ai._tick_sub)
		for sub in _ai._reactive_subs:
			eb.unsubscribe(sub)
	if is_instance_valid(_action):
		if _action._phase_advanced_sub:
			eb.unsubscribe(_action._phase_advanced_sub)
		if _action._cancelled_sub:
			eb.unsubscribe(_action._cancelled_sub)
	for node in [_ai, _action]:
		if is_instance_valid(node):
			remove_child(node)
			node.free()


func test_rule_writes_memory():
	_ai.set_rule_memory(&"test_rule", &"last_target", &"athens")
	var value: Variant = _ai.read_rule_memory(&"test_rule", &"last_target")
	assert_eq(value, &"athens")


func test_subsequent_fire_reads_memory():
	_ai.set_rule_memory(&"rotation_rule", &"last_target_province", &"egypt_lower")
	var next: Variant = _ai.read_rule_memory(&"rotation_rule", &"last_target_province")
	assert_eq(next, &"egypt_lower")
	# Update memory
	_ai.set_rule_memory(&"rotation_rule", &"last_target_province", &"egypt_upper")
	var updated: Variant = _ai.read_rule_memory(&"rotation_rule", &"last_target_province")
	assert_eq(updated, &"egypt_upper")


func test_memory_survives_save_load():
	_ai.set_rule_memory(&"persist_rule", &"fire_count", 5)
	var snapshot: Dictionary = _ai.snapshot_state()
	assert_true(snapshot.has("rule_memory"))
	# Clear and restore
	_ai._rule_memory.clear()
	assert_eq(_ai.read_rule_memory(&"persist_rule", &"fire_count", 0), 0)
	_ai.apply_state(snapshot)
	assert_eq(_ai.read_rule_memory(&"persist_rule", &"fire_count", 0), 5)
