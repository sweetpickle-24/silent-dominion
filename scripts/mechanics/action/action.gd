class_name Action
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node

var _schemes_by_immortal: Dictionary = {}   # StringName -> ImmortalSchemes
var _next_scheme_seq: int = 1
var _phase_advanced_sub  # SubscriptionHandle


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_phase_advanced_sub = _event_bus.subscribe(
		preload("res://scripts/data/events/scheme_phase_advanced_event.gd"),
		Callable(self, "_on_scheme_phase_advanced"),
		100,
		&"",
		EndOfTickPhases.PER_IMMORTAL,
	)
	var immortal_registry: Node = get_node("/root/ImmortalRegistry")
	var player_immortal: ImmortalRecord = immortal_registry.get_player()
	if player_immortal != null and not _schemes_by_immortal.has(player_immortal.id):
		var bucket := ImmortalSchemes.new()
		bucket.immortal_id = player_immortal.id
		_schemes_by_immortal[player_immortal.id] = bucket
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"action_state",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)
	_logger.info(LogChannels.ACTION, "Action mechanic ready")


# --- Public API ---

func dispatch(action_type: StringName, target_ref: StringName, target_place_ref: StringName, immortal_id: StringName = &"player") -> SchemeRecord:
	assert(_is_valid_action_type(action_type), "Unknown action_type: %s" % action_type)
	var scheme := SchemeRecord.new()
	scheme.id = _generate_scheme_id(immortal_id)
	scheme.immortal_id = immortal_id
	scheme.action_type = action_type
	scheme.target_ref = target_ref
	scheme.target_place_ref = target_place_ref
	scheme.current_phase = SchemePhases.DISPATCHED
	scheme.dispatched_at_day = _time_keeper.current_day
	scheme.current_phase_entered_at_day = _time_keeper.current_day
	scheme.phase_history = [{"phase": SchemePhases.DISPATCHED, "entered_at_day": _time_keeper.current_day}]

	var bucket: ImmortalSchemes = _schemes_by_immortal.get(immortal_id)
	if bucket == null:
		bucket = ImmortalSchemes.new()
		bucket.immortal_id = immortal_id
		_schemes_by_immortal[immortal_id] = bucket
	bucket.active_schemes.append(scheme)

	var event := SchemeDispatchedEvent.new()
	event.scheme_id = scheme.id
	event.immortal_id = immortal_id
	event.action_type = action_type
	event.target_ref = target_ref
	event.target_place_ref = target_place_ref
	_event_bus.dispatch(event)

	_logger.info(LogChannels.ACTION, "Scheme dispatched", {
		"scheme_id": scheme.id,
		"action_type": action_type,
		"target_ref": target_ref,
	})
	return scheme


func get_active_schemes(immortal_id: StringName = &"player") -> Array:
	var bucket: ImmortalSchemes = _schemes_by_immortal.get(immortal_id)
	if bucket == null:
		return []
	return bucket.active_schemes.duplicate()


func get_scheme(scheme_id: StringName, immortal_id: StringName = &"player") -> SchemeRecord:
	var bucket: ImmortalSchemes = _schemes_by_immortal.get(immortal_id)
	if bucket == null:
		return null
	for scheme: SchemeRecord in bucket.active_schemes:
		if scheme.id == scheme_id:
			return scheme
	return null


# --- Internal ---

func _on_scheme_phase_advanced(event: SchemePhaseAdvancedEvent) -> void:
	var scheme := get_scheme(event.scheme_id, event.immortal_id)
	if scheme == null:
		push_error("SchemePhaseAdvancedEvent for unknown scheme_id %s" % event.scheme_id)
		return
	scheme.current_phase = event.new_phase
	scheme.current_phase_entered_at_day = _time_keeper.current_day
	scheme.phase_history.append({"phase": event.new_phase, "entered_at_day": _time_keeper.current_day})

	if _logger.enabled_for(LogChannels.ACTION, _LOG_DEBUG):
		_logger.debug(LogChannels.ACTION, "Scheme phase updated", {
			"scheme_id": scheme.id,
			"old_phase": event.old_phase,
			"new_phase": event.new_phase,
		})

	if event.new_phase == SchemePhases.RESOLVED:
		scheme.outcome = SchemeOutcomes.SUCCESS  # Step 7: deterministic success
		scheme.resolved_at_day = _time_keeper.current_day
		var resolved_event := SchemeResolvedEvent.new()
		resolved_event.scheme_id = scheme.id
		resolved_event.immortal_id = scheme.immortal_id
		resolved_event.action_type = scheme.action_type
		resolved_event.target_ref = scheme.target_ref
		resolved_event.target_place_ref = scheme.target_place_ref
		resolved_event.outcome = scheme.outcome
		resolved_event.resolved_at_day = scheme.resolved_at_day
		_event_bus.dispatch(resolved_event)
		var bucket: ImmortalSchemes = _schemes_by_immortal.get(scheme.immortal_id)
		if bucket != null:
			bucket.active_schemes.erase(scheme)
		_logger.info(LogChannels.ACTION, "Scheme resolved", {
			"scheme_id": scheme.id,
			"outcome": scheme.outcome,
		})


func _is_valid_action_type(action_type: StringName) -> bool:
	return action_type in [
		ActionTypeValues.OBSERVE,
		ActionTypeValues.PLANT_IDEA,
		ActionTypeValues.SEED_RUMOR,
		ActionTypeValues.CULTIVATE,
		ActionTypeValues.CORRUPT_INSTITUTION,
	]


func _generate_scheme_id(immortal_id: StringName) -> StringName:
	var seq := _next_scheme_seq
	_next_scheme_seq += 1
	return StringName("%s_scheme_%d" % [immortal_id, seq])


# --- Save/load ---

func snapshot_state() -> Dictionary:
	return {
		"schemes_by_immortal": _schemes_by_immortal.duplicate(true),
		"next_scheme_seq": _next_scheme_seq,
	}


func apply_state(state: Dictionary) -> void:
	if state == null or state.is_empty():
		_schemes_by_immortal = {}
		_next_scheme_seq = 1
	else:
		_schemes_by_immortal = state.get("schemes_by_immortal", {}).duplicate(true)
		_next_scheme_seq = state.get("next_scheme_seq", 1)
	if not _schemes_by_immortal.has(&"player"):
		var bucket := ImmortalSchemes.new()
		bucket.immortal_id = &"player"
		_schemes_by_immortal[&"player"] = bucket
	_logger.info(LogChannels.ACTION, "Action state applied from load", {
		"next_scheme_seq": _next_scheme_seq,
	})
