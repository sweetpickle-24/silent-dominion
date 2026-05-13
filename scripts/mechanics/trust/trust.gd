class_name Trust
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _immortal_registry: Node
var _action: Node
var _last_contact_day: Dictionary = {}

const TRUST_GAIN_PER_SUCCESS: int = 3
const TRUST_LOSS_PER_FAILURE: int = 8
const TRUST_DECAY_PER_YEAR: int = 5
const TRUST_DECAY_THRESHOLD_DAYS: int = 365

func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_immortal_registry = get_node("/root/ImmortalRegistry")
	_action = get_node("../Action")
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(&"trust_state", Callable(self, "snapshot_state"), Callable(self, "apply_state"))
	_event_bus.subscribe(preload("res://scripts/data/events/scheme_resolved_event.gd"), Callable(self, "_on_scheme_resolved"), 110, &"", EndOfTickPhases.PER_IMMORTAL)
	_event_bus.subscribe(preload("res://scripts/data/events/game_day_ticked_event.gd"), Callable(self, "_on_game_day_ticked"), 260, &"", EndOfTickPhases.PER_IMMORTAL)
	_logger.info(LogChannels.TRUST, "Trust mechanic ready")

func _on_scheme_resolved(event: SchemeResolvedEvent) -> void:
	for member_id in [event.get("scheme_id")]:
		pass  # Need to get scheme from Action
	var scheme: SchemeRecord = _action.get_scheme(event.scheme_id, event.immortal_id)
	if scheme == null:
		return
	for field in ["assigned_lieutenant_id", "assigned_coordinator_id", "assigned_operative_id"]:
		var member_id: StringName = scheme.get(field)
		if member_id == null or member_id == &"":
			continue
		var character: CharacterRecord = _immortal_registry.get_character_record_any(member_id)
		if character == null:
			continue
		if event.outcome == &"success":
			character.trust_score = clampi(character.trust_score + TRUST_GAIN_PER_SUCCESS, 0, 100)
		elif event.outcome == &"failure":
			character.trust_score = clampi(character.trust_score - TRUST_LOSS_PER_FAILURE, 0, 100)
		_last_contact_day[member_id] = _time_keeper.current_day

func _on_game_day_ticked(event: GameDayTickedEvent) -> void:
	if event.day % 365 != 0:
		return
	for char_id: StringName in _immortal_registry.all_character_ids():
		var ch: CharacterRecord = _immortal_registry.get_character(char_id)
		if ch.chain_status == ChainStatusValues.NONE:
			continue
		var last: int = _last_contact_day.get(char_id, 0)
		if (event.day - last) >= TRUST_DECAY_THRESHOLD_DAYS:
			ch.trust_score = clampi(ch.trust_score - TRUST_DECAY_PER_YEAR, 0, 100)

func snapshot_state() -> Dictionary:
	return {"last_contact_day": _last_contact_day.duplicate(true)}

func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_last_contact_day = state.get("last_contact_day", {}).duplicate(true)
