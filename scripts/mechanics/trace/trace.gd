class_name TraceMechanic
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _action: Node
var _chain: Node
var _world_registry: Node
var _immortal_registry: Node

var _traces_by_place: Dictionary = {}   # StringName place_id -> Array[TraceRecord]
var _next_trace_seq: int = 1


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_action = get_node("../Action")
	_chain = get_node("../Chain")
	_world_registry = get_node("/root/WorldRegistry")
	_immortal_registry = get_node("/root/ImmortalRegistry")
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(&"trace_state", Callable(self, "snapshot_state"), Callable(self, "apply_state"))
	_event_bus.subscribe(preload("res://scripts/data/events/scheme_resolved_event.gd"), Callable(self, "_on_scheme_resolved"), 100, &"", EndOfTickPhases.WORLD_SHARED)
	_event_bus.subscribe(preload("res://scripts/data/events/game_day_ticked_event.gd"), Callable(self, "_on_game_day_ticked"), 300, &"", EndOfTickPhases.WORLD_SHARED)
	_logger.info(LogChannels.TRACE, "Trace mechanic ready")


func _on_scheme_resolved(event: SchemeResolvedEvent) -> void:
	# Scheme may already be removed from active by Action; use event fields directly
	var trace := TraceRecord.new()
	trace.id = StringName("trace_%d" % _next_trace_seq)
	_next_trace_seq += 1
	trace.emitting_immortal_id = event.immortal_id
	var immortal: ImmortalRecord = _immortal_registry.get_immortal(event.immortal_id)
	trace.emitting_society_id = immortal.society_id if immortal != null else &""
	trace.target_place_id = event.target_place_ref
	var place: PlaceRecord = _world_registry.get_place(event.target_place_ref)
	if place != null:
		trace.target_province_id = place.province
	trace.action_type = event.action_type
	var action_def: ActionDefinition = _chain.get_action_definition(event.action_type)
	if action_def != null:
		trace.action_tier = action_def.tier
		trace.emission_strength = action_def.baseline_exposure_cost
	trace.emitted_at_day = _time_keeper.current_day
	trace.expires_at_day = trace.emitted_at_day + 730
	if not _traces_by_place.has(trace.target_place_id):
		_traces_by_place[trace.target_place_id] = []
	_traces_by_place[trace.target_place_id].append(trace)
	if _logger.enabled_for(LogChannels.TRACE, _LOG_DEBUG):
		_logger.debug(LogChannels.TRACE, "Trace emitted", {"place": trace.target_place_id, "society": trace.emitting_society_id, "strength": trace.emission_strength})


func _on_game_day_ticked(event: GameDayTickedEvent) -> void:
	var day: int = event.day
	for place_id: StringName in _traces_by_place.keys():
		var traces: Array = _traces_by_place[place_id]
		var filtered: Array = []
		for trace: TraceRecord in traces:
			if trace.current_strength_at(day) > 0.0:
				filtered.append(trace)
		_traces_by_place[place_id] = filtered


func get_traces_at_place(place_id: StringName) -> Array:
	return _traces_by_place.get(place_id, [])


func get_all_traces_for_society(society_id: StringName, query_day: int) -> Array:
	var matches: Array = []
	for place_id: StringName in _traces_by_place.keys():
		for trace: TraceRecord in _traces_by_place[place_id]:
			if trace.emitting_society_id == society_id and trace.current_strength_at(query_day) > 0.0:
				matches.append(trace)
	return matches


func snapshot_state() -> Dictionary:
	return {"traces_by_place": _traces_by_place.duplicate(true), "next_trace_seq": _next_trace_seq}


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_traces_by_place = state.get("traces_by_place", {}).duplicate(true)
	_next_trace_seq = state.get("next_trace_seq", 1)
