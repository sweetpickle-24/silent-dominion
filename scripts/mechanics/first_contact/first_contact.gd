class_name FirstContact
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _immortal_registry: Node

var _contact_states: Dictionary = {}  # "a_id:b_id" (alphabetical) -> FirstContactState


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_immortal_registry = get_node("/root/ImmortalRegistry")
	_event_bus.subscribe(
		preload("res://scripts/data/events/first_contact_event.gd"),
		Callable(self, "_on_first_contact_event"),
		150, &"", EndOfTickPhases.DIPLOMATIC,
	)
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"first_contact_state",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)
	_logger.info(LogChannels.FIRST_CONTACT, "FirstContact mechanic ready")


# --- Event handlers ---

func _on_first_contact_event(event: FirstContactEvent) -> void:
	var state: FirstContactState = _get_or_create_state(event.detecting_immortal_id, event.detected_immortal_id)
	var detector_is_a: bool = (event.detecting_immortal_id == state.immortal_a_id)
	match state.stage:
		&"unaware":
			state.stage = &"a_aware" if detector_is_a else &"b_aware"
			state.first_aware_day = event.day
		&"a_aware":
			if not detector_is_a:
				state.stage = &"mutual_aware"
		&"b_aware":
			if detector_is_a:
				state.stage = &"mutual_aware"
	_logger.info(LogChannels.FIRST_CONTACT, "First contact state updated", {
		"detector": event.detecting_immortal_id, "detected": event.detected_immortal_id,
		"new_stage": state.stage,
	})


# --- Public API ---

func initiate_contact(initiator_id: StringName, target_id: StringName, opening_gesture_kind: StringName, day: int = -1) -> FirstContactState:
	if day < 0:
		day = _time_keeper.current_day
	var state: FirstContactState = _get_or_create_state(initiator_id, target_id)
	if state.stage == &"channel_open" or state.stage == &"contact_responded":
		_logger.warn(LogChannels.FIRST_CONTACT, "Contact already established", {"initiator": initiator_id})
		return state
	state.stage = &"contact_initiated"
	state.contact_initiated_day = day
	state.contact_initiator_id = initiator_id
	state.opening_gesture_kind = opening_gesture_kind
	_logger.info(LogChannels.FIRST_CONTACT, "Contact initiated", {
		"initiator": initiator_id, "target": target_id, "gesture": opening_gesture_kind,
	})
	return state


func respond_to_contact(initiator_id: StringName, target_id: StringName, response_kind: StringName, day: int = -1) -> FirstContactState:
	if day < 0:
		day = _time_keeper.current_day
	var state: FirstContactState = _get_or_create_state(initiator_id, target_id)
	if state.stage != &"contact_initiated":
		_logger.warn(LogChannels.FIRST_CONTACT, "Cannot respond — no contact initiated", {
			"stage": state.stage,
		})
		return state
	state.opening_gesture_response = response_kind
	match response_kind:
		&"reciprocated":
			state.stage = &"channel_open"
		&"ignored":
			state.stage = &"contact_responded"
		&"hostile":
			state.stage = &"contact_responded"
	_logger.info(LogChannels.FIRST_CONTACT, "Contact response", {
		"response": response_kind, "new_stage": state.stage,
	})
	return state


func get_contact_state(immortal_a_id: StringName, immortal_b_id: StringName) -> FirstContactState:
	var key: String = _make_key(immortal_a_id, immortal_b_id)
	return _contact_states.get(key, null)


func get_all_contact_states() -> Dictionary:
	return _contact_states


# --- Internal ---

func _get_or_create_state(id_a: StringName, id_b: StringName) -> FirstContactState:
	var key: String = _make_key(id_a, id_b)
	if not _contact_states.has(key):
		var state := FirstContactState.new()
		# Alphabetical ordering
		if String(id_a) < String(id_b):
			state.immortal_a_id = id_a
			state.immortal_b_id = id_b
		else:
			state.immortal_a_id = id_b
			state.immortal_b_id = id_a
		_contact_states[key] = state
	return _contact_states[key]


func _make_key(id_a: StringName, id_b: StringName) -> String:
	if String(id_a) < String(id_b):
		return "%s:%s" % [id_a, id_b]
	return "%s:%s" % [id_b, id_a]


# --- Save/load ---

func snapshot_state() -> Dictionary:
	return {"contact_states": _contact_states.duplicate(true)}


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_contact_states = state.get("contact_states", {}).duplicate(true)
	_logger.info(LogChannels.FIRST_CONTACT, "FirstContact state applied from load")
