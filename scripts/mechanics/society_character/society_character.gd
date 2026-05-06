class_name SocietyCharacter
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _world_registry: Node
var _rule_evaluator: Node
var _time_keeper: Node
var _scheme_resolved_sub

var _societies: Dictionary = {}      # StringName society_id -> SocietyCharacterRecord
var _dispositions: Dictionary = {}   # StringName source_society_id -> Dictionary[StringName target_immortal_id, int]


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_world_registry = get_node("/root/WorldRegistry")
	_rule_evaluator = get_node("/root/RuleEvaluator")
	_time_keeper = get_node("/root/TimeKeeper")
	_load_societies()
	_initialize_dispositions_to_baseline()
	_scheme_resolved_sub = _event_bus.subscribe(
		preload("res://scripts/data/events/scheme_resolved_event.gd"),
		Callable(self, "_on_scheme_resolved"),
		200,
		&"",
		EndOfTickPhases.DIPLOMATIC,
	)
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"society_character_state",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)
	_logger.info(LogChannels.SOCIETY_CHARACTER, "SocietyCharacter mechanic ready", {
		"societies": _societies.size(),
	})


func _load_societies() -> void:
	var dir := DirAccess.open("res://data/societies/")
	if dir == null:
		_logger.warn(LogChannels.SOCIETY_CHARACTER, "data/societies/ does not exist")
		return
	dir.list_dir_begin()
	var subdir: String = dir.get_next()
	while subdir != "":
		if dir.current_is_dir() and not subdir.begins_with("."):
			var character_path: String = "res://data/societies/%s/%s_character.tres" % [subdir, subdir]
			if ResourceLoader.exists(character_path):
				var record = ResourceLoader.load(character_path)
				if record is SocietyCharacterRecord:
					assert(not _societies.has(record.society_id), "Duplicate society_id %s" % record.society_id)
					_societies[record.society_id] = record
					_logger.info(LogChannels.SOCIETY_CHARACTER, "Loaded society", {"society_id": record.society_id})
		subdir = dir.get_next()
	dir.list_dir_end()


func _initialize_dispositions_to_baseline() -> void:
	var immortal_registry: Node = get_node("/root/ImmortalRegistry")
	var all_immortal_ids: Array = immortal_registry.all_immortal_ids()
	for society_id: StringName in _societies.keys():
		var society: SocietyCharacterRecord = _societies[society_id]
		if not _dispositions.has(society_id):
			_dispositions[society_id] = {}
		for immortal_id: StringName in all_immortal_ids:
			_dispositions[society_id][immortal_id] = society.disposition_baseline


func _on_scheme_resolved(event: SchemeResolvedEvent) -> void:
	var context: RuleContext = _build_rule_context(event)
	for society_id: StringName in _societies.keys():
		var society: SocietyCharacterRecord = _societies[society_id]
		for rule: Rule in society.disposition_modifier_rules:
			_evaluate_disposition_rule(rule, society_id, event, context)


func _evaluate_disposition_rule(rule: Rule, source_society_id: StringName, event: SchemeResolvedEvent, context: RuleContext) -> void:
	var fired: Variant = _rule_evaluator.evaluate(rule, context)
	if fired == null:
		return
	var target_immortal_id: StringName = event.immortal_id
	var prior_value: int = 0
	if _dispositions.has(source_society_id):
		prior_value = _dispositions[source_society_id].get(target_immortal_id, 0)
	var scaled_delta: int = rule.base_delta  # Step 8: no scaling. T4-13 fills this in.
	var new_value: int = prior_value + scaled_delta
	if not _dispositions.has(source_society_id):
		_dispositions[source_society_id] = {}
	_dispositions[source_society_id][target_immortal_id] = new_value

	var disposition_event := DispositionRuleFiredEvent.new()
	disposition_event.rule_id = rule.id
	disposition_event.source_society_id = source_society_id
	disposition_event.target_immortal_id = target_immortal_id
	disposition_event.base_delta = rule.base_delta
	disposition_event.scaled_delta = scaled_delta
	disposition_event.attribution_tag = rule.attribution_tag
	disposition_event.triggering_event_id = event.scheme_id
	_event_bus.dispatch(disposition_event)

	_logger.info(LogChannels.SOCIETY_CHARACTER, "Disposition rule fired", {
		"rule_id": rule.id,
		"source_society": source_society_id,
		"target_immortal": target_immortal_id,
		"delta": scaled_delta,
		"new_value": new_value,
	})


func _build_rule_context(event: SchemeResolvedEvent) -> RuleContext:
	var target_obj: Object = null
	if event.target_ref != &"":
		var place: PlaceRecord = _world_registry.get_place(event.target_ref)
		if place != null:
			target_obj = place
	return RuleContext.for_event(event, null, target_obj)


# --- Public API ---

func get_disposition(source_society_id: StringName, target_immortal_id: StringName) -> int:
	var pair_dict: Dictionary = _dispositions.get(source_society_id, {})
	return pair_dict.get(target_immortal_id, 0)


func get_society(society_id: StringName) -> SocietyCharacterRecord:
	return _societies.get(society_id, null)


# --- Save/load ---

func snapshot_state() -> Dictionary:
	return {"dispositions": _dispositions.duplicate(true)}


func apply_state(state: Dictionary) -> void:
	if state == null or state.is_empty():
		return
	_dispositions = state.get("dispositions", {}).duplicate(true)
	_logger.info(LogChannels.SOCIETY_CHARACTER, "SocietyCharacter state applied from load")
