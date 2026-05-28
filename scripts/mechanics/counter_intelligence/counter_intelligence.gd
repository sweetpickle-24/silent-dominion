class_name CounterIntelligence
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _immortal_registry: Node
var _world_registry: Node


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_immortal_registry = get_node("/root/ImmortalRegistry")
	_world_registry = get_node("/root/WorldRegistry")
	_event_bus.subscribe(
		preload("res://scripts/data/events/scheme_resolved_event.gd"),
		Callable(self, "_on_scheme_resolved"),
		140, &"", EndOfTickPhases.PER_IMMORTAL,
	)
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"counter_intelligence_state",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)
	_logger.info(LogChannels.COUNTER_INTELLIGENCE, "CounterIntelligence mechanic ready")


func _on_scheme_resolved(event: SchemeResolvedEvent) -> void:
	if event.outcome != &"success":
		return
	match event.action_type:
		ActionTypeValues.COUNTER_INTELLIGENCE_ROTATE:
			_handle_rotate(event)
		ActionTypeValues.COUNTER_INTELLIGENCE_OBSCURE_TRACES:
			_handle_obscure_traces(event)
		ActionTypeValues.PLANT_FALSE_FINGERPRINT:
			_handle_plant_false_fingerprint(event)
		ActionTypeValues.COUNTER_INTELLIGENCE_ARCHIVE_QUERY:
			_handle_archive_query(event)


# --- Public API ---

func obscure_traces_at(place_id: StringName, emitting_immortal_id: StringName, quality_factor: float) -> void:
	var trace_node: Node = get_node_or_null("../Trace")
	var reduced: int = 0
	if trace_node != null and trace_node.has_method("reduce_traces_at"):
		reduced = trace_node.reduce_traces_at(place_id, emitting_immortal_id, quality_factor)
	else:
		_logger.warn(LogChannels.COUNTER_INTELLIGENCE, "Trace mechanic not found")
	_logger.info(LogChannels.COUNTER_INTELLIGENCE, "Traces obscured", {
		"place": place_id, "immortal": emitting_immortal_id, "factor": quality_factor,
		"traces_reduced": reduced,
	})
	var event := CounterIntelligenceFiredEvent.new()
	event.operation_kind = &"obscure_traces"
	event.acting_immortal_id = emitting_immortal_id
	event.target_place_id = place_id
	event.day = _time_keeper.current_day
	_event_bus.dispatch(event)


func plant_false_trace(place_id: StringName, framed_society_id: StringName, action_type: StringName, planting_immortal_id: StringName) -> void:
	var trace_node: Node = get_node_or_null("../Trace")
	if trace_node != null:
		# Create a trace with the framed society's id
		var false_trace := TraceRecord.new()
		false_trace.id = StringName("false_trace_%d" % _time_keeper.current_day)
		false_trace.emitting_immortal_id = planting_immortal_id
		false_trace.emitting_society_id = framed_society_id  # framed society
		false_trace.target_place_id = place_id
		false_trace.emission_strength = 3.0  # "Moderate" quality
		false_trace.action_type = action_type
		false_trace.action_tier = 1
		false_trace.emitted_at_day = _time_keeper.current_day
		false_trace.expires_at_day = _time_keeper.current_day + 730
		if trace_node.has_method("add_trace"):
			trace_node.add_trace(false_trace)
	else:
		_logger.warn(LogChannels.COUNTER_INTELLIGENCE, "Trace mechanic not found")
	_logger.info(LogChannels.COUNTER_INTELLIGENCE, "False fingerprint planted", {
		"place": place_id, "framed_society": framed_society_id,
	})
	var ci_event := CounterIntelligenceFiredEvent.new()
	ci_event.operation_kind = &"plant_false_fingerprint"
	ci_event.acting_immortal_id = planting_immortal_id
	ci_event.target_place_id = place_id
	ci_event.day = _time_keeper.current_day
	_event_bus.dispatch(ci_event)
	var fp_event := FalseFingerprintPlantedEvent.new()
	fp_event.planting_immortal_id = planting_immortal_id
	fp_event.framed_society_id = framed_society_id
	fp_event.target_place_id = place_id
	fp_event.quality = &"moderate"
	fp_event.day = _time_keeper.current_day
	_event_bus.dispatch(fp_event)


func rotate_chain_member(character_id: StringName) -> void:
	var character: CharacterRecord = _immortal_registry.get_character_record_any(character_id)
	if character == null:
		_logger.warn(LogChannels.COUNTER_INTELLIGENCE, "Character not found for rotation", {"id": character_id})
		return
	var old_heat: int = character.heat
	character.heat = 0
	_logger.info(LogChannels.COUNTER_INTELLIGENCE, "Chain member rotated", {
		"character": character_id, "old_heat": old_heat,
	})
	var event := CounterIntelligenceFiredEvent.new()
	event.operation_kind = &"rotate"
	event.acting_immortal_id = character.society_id
	event.target_character_id = character_id
	event.day = _time_keeper.current_day
	_event_bus.dispatch(event)


# --- Internal scheme handlers ---

func _handle_rotate(event: SchemeResolvedEvent) -> void:
	rotate_chain_member(event.target_ref)


func _handle_obscure_traces(event: SchemeResolvedEvent) -> void:
	obscure_traces_at(event.target_place_ref, event.immortal_id, 0.5)


func _handle_plant_false_fingerprint(event: SchemeResolvedEvent) -> void:
	# Target place is where false trace goes; target_ref encodes framed society
	plant_false_trace(event.target_place_ref, event.target_ref, &"observe", event.immortal_id)


func _handle_archive_query(_event: SchemeResolvedEvent) -> void:
	# Archive query: the Veil's archive remembering patterns.
	# Actual Memoirs query waits for 11.13.5 when Memoirs extends to all immortals.
	_logger.info(LogChannels.COUNTER_INTELLIGENCE, "Archive query executed (placeholder)")
	var ci_event := CounterIntelligenceFiredEvent.new()
	ci_event.operation_kind = &"archive_query"
	ci_event.acting_immortal_id = _event.immortal_id
	ci_event.day = _time_keeper.current_day
	_event_bus.dispatch(ci_event)


# --- Save/load ---

func snapshot_state() -> Dictionary:
	return {}


func apply_state(_state) -> void:
	_logger.info(LogChannels.COUNTER_INTELLIGENCE, "CounterIntelligence state applied from load")
