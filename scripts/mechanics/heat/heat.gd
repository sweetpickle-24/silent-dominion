class_name HeatMechanic
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _immortal_registry: Node
var _action: Node
var _chain: Node
var _last_active_day: Dictionary = {}

const HEAT_GAIN_BASELINE: float = 5.0
const HEAT_DECAY_PER_YEAR: int = 10

func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_immortal_registry = get_node("/root/ImmortalRegistry")
	_action = get_node("../Action")
	_chain = get_node("../Chain")
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(&"heat_state", Callable(self, "snapshot_state"), Callable(self, "apply_state"))
	_event_bus.subscribe(preload("res://scripts/data/events/scheme_resolved_event.gd"), Callable(self, "_on_scheme_resolved"), 115, &"", EndOfTickPhases.PER_IMMORTAL)
	_event_bus.subscribe(preload("res://scripts/data/events/game_day_ticked_event.gd"), Callable(self, "_on_game_day_ticked"), 270, &"", EndOfTickPhases.PER_IMMORTAL)
	_logger.info(LogChannels.HEAT, "Heat mechanic ready")

func _on_scheme_resolved(event: SchemeResolvedEvent) -> void:
	var scheme: SchemeRecord = _action.get_scheme(event.scheme_id, event.immortal_id)
	if scheme == null:
		return
	if scheme.assigned_operative_id == &"":
		return
	var operative: CharacterRecord = _immortal_registry.get_character_record_any(scheme.assigned_operative_id)
	if operative == null:
		return
	var action_def: ActionDefinition = _chain.get_action_definition(scheme.action_type)
	if action_def == null:
		return
	var multiplier: float = PublicPositionValues.EXPOSURE_MULTIPLIER.get(operative.public_position_tier, 1.0)
	var heat_gain: int = int(HEAT_GAIN_BASELINE * action_def.tier * multiplier)
	operative.heat = clampi(operative.heat + heat_gain, 0, 100)
	_last_active_day[scheme.assigned_operative_id] = _time_keeper.current_day

func _on_game_day_ticked(event: GameDayTickedEvent) -> void:
	if event.day % 365 != 0:
		return
	for char_id: StringName in _immortal_registry.all_character_ids():
		var ch: CharacterRecord = _immortal_registry.get_character(char_id)
		if ch.heat == 0:
			continue
		var last: int = _last_active_day.get(char_id, event.day)
		if (event.day - last) >= 365:
			ch.heat = clampi(ch.heat - HEAT_DECAY_PER_YEAR, 0, 100)

func snapshot_state() -> Dictionary:
	return {"last_active_day": _last_active_day.duplicate(true)}

func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_last_active_day = state.get("last_active_day", {}).duplicate(true)
