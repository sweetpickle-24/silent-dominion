class_name SocietyAI
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _action: Node
var _immortal_registry: Node
var _world_registry: Node
var _rule_evaluator: Node

var _rules_by_society: Dictionary = {}   # StringName society_id -> Array[SocietyAIRule]
var _runner: RuleListRunner = RuleListRunner.new()

const MAX_CONCURRENT_SCHEMES_PER_SOCIETY: int = 2
var _tick_sub
var _reactive_subs: Array = []


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_action = get_node("../Action")
	_immortal_registry = get_node("/root/ImmortalRegistry")
	_world_registry = get_node("/root/WorldRegistry")
	_rule_evaluator = get_node("/root/RuleEvaluator")
	_load_rules()
	_tick_sub = _event_bus.subscribe(
		preload("res://scripts/data/events/game_day_ticked_event.gd"),
		Callable(self, "_on_game_day_ticked"),
		200, &"", EndOfTickPhases.PER_IMMORTAL,
	)
	_wire_reactive_subscriptions()
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"society_ai_state",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)
	var total: int = 0
	for key: StringName in _rules_by_society:
		total += _rules_by_society[key].size()
	_logger.info(LogChannels.SOCIETY_AI, "SocietyAI ready", {
		"societies_with_rules": _rules_by_society.keys(),
		"total_rules": total,
	})


func _load_rules() -> void:
	var base_dir := DirAccess.open("res://data/rules/society_ai/")
	if base_dir == null:
		_logger.warn(LogChannels.SOCIETY_AI, "data/rules/society_ai/ does not exist")
		return
	base_dir.list_dir_begin()
	var subdir_name: String = base_dir.get_next()
	while subdir_name != "":
		if base_dir.current_is_dir() and not subdir_name.begins_with("."):
			var subdir_path: String = "res://data/rules/society_ai/%s/" % subdir_name
			var subdir := DirAccess.open(subdir_path)
			if subdir:
				subdir.list_dir_begin()
				var fname: String = subdir.get_next()
				while fname != "":
					if fname.ends_with(".tres"):
						var resource = ResourceLoader.load(subdir_path + fname)
						if resource is SocietyAIRule:
							if not _rules_by_society.has(resource.society_id):
								_rules_by_society[resource.society_id] = []
							_rules_by_society[resource.society_id].append(resource)
							_runner.ensure_rule_state(resource.id)
					fname = subdir.get_next()
				subdir.list_dir_end()
		subdir_name = base_dir.get_next()
	base_dir.list_dir_end()
	for sid: StringName in _rules_by_society:
		_rules_by_society[sid].sort_custom(func(a: SocietyAIRule, b: SocietyAIRule) -> bool: return a.priority < b.priority)


func _wire_reactive_subscriptions() -> void:
	var reactive_events: Array = [
		preload("res://scripts/data/events/scheme_resolved_event.gd"),
		preload("res://scripts/data/events/fingerprint_level_advanced_event.gd"),
		preload("res://scripts/data/events/first_contact_event.gd"),
		preload("res://scripts/data/events/treaty_proposed_event.gd"),
		preload("res://scripts/data/events/treaty_violation_detected_event.gd"),
	]
	for event_class in reactive_events:
		var sub = _event_bus.subscribe(
			event_class,
			Callable(self, "_on_reactive_event"),
			250, &"", EndOfTickPhases.PER_IMMORTAL,
		)
		_reactive_subs.append(sub)


func _on_reactive_event(event: EventBase) -> void:
	var day: int = _time_keeper.current_day
	for society_id: StringName in _rules_by_society.keys():
		var rules: Array = _rules_by_society[society_id]
		var immortal_id: StringName = _get_society_immortal_id(society_id)
		if immortal_id == &"":
			continue
		var context: RuleContext = RuleContext.world_only(day, _time_keeper.current_era)
		context.event = event
		_runner.evaluate_reactive(
			rules, event, day, context, _rule_evaluator,
			func(rule: SocietyAIRule) -> bool: return _fire_rule(rule, immortal_id, day),
		)


func _on_game_day_ticked(event: GameDayTickedEvent) -> void:
	for society_id: StringName in _rules_by_society.keys():
		_evaluate_society_rules(society_id, event.day)


func _evaluate_society_rules(society_id: StringName, day: int) -> void:
	var immortal_id: StringName = _get_society_immortal_id(society_id)
	if immortal_id == &"":
		return
	var active: Array = _action.get_active_schemes(immortal_id)
	if active.size() >= MAX_CONCURRENT_SCHEMES_PER_SOCIETY:
		return
	if not _rules_by_society.has(society_id):
		return
	var rules: Array = _rules_by_society[society_id]
	var context: RuleContext = RuleContext.world_only(day, _time_keeper.current_era)
	_runner.evaluate_rules(
		rules, day, context, _rule_evaluator,
		func(rule: SocietyAIRule) -> bool: return _fire_rule(rule, immortal_id, day),
		true,
	)


func _fire_rule(rule: SocietyAIRule, immortal_id: StringName, _day: int) -> bool:
	if rule.action_kind != &"dispatch_scheme":
		return false
	var params: Dictionary = rule.action_params
	var action_type: StringName = params.get("action_type", &"")
	if action_type == &"":
		return false
	var target_ref: StringName = _select_target(params.get("target_selector", &""), params.get("target_constraints", {}))
	if target_ref == &"":
		return false
	var target_place_ref: StringName = _resolve_target_place(target_ref)
	var scheme: SchemeRecord = _action.dispatch(action_type, target_ref, target_place_ref, immortal_id)
	if scheme != null:
		if _logger.enabled_for(LogChannels.SOCIETY_AI, _LOG_DEBUG):
			_logger.debug(LogChannels.SOCIETY_AI, "Society dispatched scheme", {
				"rule_id": rule.id, "action_type": action_type, "target": target_ref,
			})
		return true
	return false


func _select_target(selector: StringName, constraints: Dictionary) -> StringName:
	match selector:
		TargetSelectorValues.SPECIFIC_PLACE:
			return constraints.get("place_id", &"")
		TargetSelectorValues.RANDOM_SCHOLARLY_CITY:
			return _select_random_scholarly_city(constraints)
		TargetSelectorValues.RANDOM_PLACE:
			return _select_random_place(constraints)
		_:
			return &""


func _select_random_scholarly_city(constraints: Dictionary) -> StringName:
	var candidates: Array = []
	for place_id: StringName in _world_registry.all_place_ids():
		var place: PlaceRecord = _world_registry.get_place(place_id)
		if place.place_type != &"city":
			continue
		var scholarly: float = place.factional_balance.get(&"scholarly", 0.0)
		if scholarly < 0.1:
			continue
		if constraints.has("min_population") and place.population < int(constraints["min_population"]):
			continue
		if constraints.has("cultural_sphere"):
			var prov: ProvinceRecord = _world_registry.get_province(place.province)
			if prov == null or prov.cultural_sphere != constraints["cultural_sphere"]:
				continue
		candidates.append(place_id)
	if candidates.is_empty():
		return &""
	return candidates[randi() % candidates.size()]


func _select_random_place(constraints: Dictionary) -> StringName:
	var candidates: Array = []
	for place_id: StringName in _world_registry.all_place_ids():
		var place: PlaceRecord = _world_registry.get_place(place_id)
		if constraints.has("min_population") and place.population < int(constraints["min_population"]):
			continue
		if constraints.has("cultural_sphere"):
			var prov: ProvinceRecord = _world_registry.get_province(place.province)
			if prov == null or prov.cultural_sphere != constraints["cultural_sphere"]:
				continue
		candidates.append(place_id)
	if candidates.is_empty():
		return &""
	return candidates[randi() % candidates.size()]


func _resolve_target_place(target_ref: StringName) -> StringName:
	var place: PlaceRecord = _world_registry.get_place(target_ref)
	if place != null:
		return target_ref
	var character: CharacterRecord = _immortal_registry.get_character_record_any(target_ref)
	if character != null:
		return character.current_place
	return target_ref


func _get_society_immortal_id(society_id: StringName) -> StringName:
	for immortal_id: StringName in _immortal_registry.all_immortal_ids():
		var immortal: ImmortalRecord = _immortal_registry.get_immortal(immortal_id)
		if immortal.society_id == society_id:
			return immortal.id
	return &""


# --- Memory access (delegates to runner) ---

func get_rule_memory(rule_id: StringName) -> Dictionary:
	return _runner.get_rule_memory(rule_id)


func set_rule_memory(rule_id: StringName, key: StringName, value: Variant) -> void:
	_runner.set_rule_memory(rule_id, key, value)


func read_rule_memory(rule_id: StringName, key: StringName, default_value: Variant = null) -> Variant:
	return _runner.read_rule_memory(rule_id, key, default_value)


# Backward compat: _rule_state / _rule_memory access for tests
var _rule_state: Dictionary:
	get: return _runner._rule_state
	set(v): _runner._rule_state = v

var _rule_memory: Dictionary:
	get: return _runner._rule_memory
	set(v): _runner._rule_memory = v


func snapshot_state() -> Dictionary:
	return _runner.snapshot()


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_runner.apply_snapshot(state)
	_logger.info(LogChannels.SOCIETY_AI, "SocietyAI state applied from load")
