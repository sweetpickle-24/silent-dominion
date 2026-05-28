# Shared rule-list evaluation engine used by SocietyAI and RulerAI.
# Owns rule state (cooldowns, fire counts) and per-rule memory.
# Callers provide rules, context, and a fire callback.
class_name RuleListRunner
extends RefCounted

var _rule_state: Dictionary = {}    # StringName rule_id -> {last_fired_at_day: int, times_fired: int}
var _rule_memory: Dictionary = {}   # StringName rule_id -> Dictionary


# --- Cooldown ---

func rule_off_cooldown(rule: SocietyAIRule, day: int) -> bool:
	if rule.cooldown_days <= 0:
		return true
	var state: Dictionary = _rule_state.get(rule.id, {"last_fired_at_day": -1})
	if state.last_fired_at_day < 0:
		return true
	return (day - state.last_fired_at_day) >= rule.cooldown_days


func ensure_rule_state(rule_id: StringName) -> void:
	if not _rule_state.has(rule_id):
		_rule_state[rule_id] = {"last_fired_at_day": -1, "times_fired": 0}


func mark_rule_fired(rule_id: StringName, day: int) -> void:
	ensure_rule_state(rule_id)
	_rule_state[rule_id].last_fired_at_day = day
	_rule_state[rule_id].times_fired += 1


# --- Memory ---

func get_rule_memory(rule_id: StringName) -> Dictionary:
	if not _rule_memory.has(rule_id):
		_rule_memory[rule_id] = {}
	return _rule_memory[rule_id]


func set_rule_memory(rule_id: StringName, key: StringName, value: Variant) -> void:
	if not _rule_memory.has(rule_id):
		_rule_memory[rule_id] = {}
	_rule_memory[rule_id][key] = value


func read_rule_memory(rule_id: StringName, key: StringName, default_value: Variant = null) -> Variant:
	if not _rule_memory.has(rule_id):
		return default_value
	return _rule_memory[rule_id].get(key, default_value)


# --- Evaluation ---

# Evaluate rules in priority order. Calls fire_callback(rule) for the first matching rule.
# Returns true if a rule fired. If one_per_tick is true, stops after first fire.
func evaluate_rules(
	rules: Array,
	day: int,
	context: RuleContext,
	rule_evaluator: Node,
	fire_callback: Callable,
	one_per_tick: bool = true,
) -> bool:
	for rule: SocietyAIRule in rules:
		if not rule_off_cooldown(rule, day):
			continue
		if rule.condition.is_empty() or rule_evaluator.evaluate_predicate(rule.condition, context):
			if fire_callback.call(rule):
				mark_rule_fired(rule.id, day)
				if one_per_tick:
					return true
	return false


# Evaluate reactive rules triggered by a specific event.
func evaluate_reactive(
	rules: Array,
	event: EventBase,
	day: int,
	context: RuleContext,
	rule_evaluator: Node,
	fire_callback: Callable,
) -> void:
	var event_class_name: String = event.get_script().get_global_name()
	for rule: SocietyAIRule in rules:
		if rule.reactive_trigger_event_classes.is_empty():
			continue
		var found: bool = false
		for trigger_class: StringName in rule.reactive_trigger_event_classes:
			if trigger_class == StringName(event_class_name):
				found = true
				break
		if not found:
			continue
		if not rule_off_cooldown(rule, day):
			continue
		if rule.condition.is_empty() or rule_evaluator.evaluate_predicate(rule.condition, context):
			if fire_callback.call(rule):
				mark_rule_fired(rule.id, day)


# --- Save/load ---

func snapshot() -> Dictionary:
	return {
		"rule_state": _rule_state.duplicate(true),
		"rule_memory": _rule_memory.duplicate(true),
	}


func apply_snapshot(state: Dictionary) -> void:
	_rule_state = state.get("rule_state", {}).duplicate(true)
	_rule_memory = state.get("rule_memory", {}).duplicate(true)
