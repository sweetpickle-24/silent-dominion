class_name Cultivation
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _immortal_registry: Node
var _action: Node
var _last_promotion_day: Dictionary = {}

const MIN_DAYS_BETWEEN_PROMOTIONS: int = 730

const TRANSITIONS: Dictionary = {
	&"cultivate_to_host": [&"none", &"host"],
	&"recruit_to_witting": [&"host", &"witting_operative"],
	&"promote_to_coordinator": [&"witting_operative", &"coordinator"],
	&"promote_to_lieutenant": [&"coordinator", &"lieutenant"],
}

func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_immortal_registry = get_node("/root/ImmortalRegistry")
	_action = get_node("../Action")
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(&"cultivation_state", Callable(self, "snapshot_state"), Callable(self, "apply_state"))
	_event_bus.subscribe(preload("res://scripts/data/events/scheme_resolved_event.gd"), Callable(self, "_on_scheme_resolved"), 130, &"", EndOfTickPhases.PER_IMMORTAL)
	_logger.info(LogChannels.CULTIVATION, "Cultivation mechanic ready")

func _on_scheme_resolved(event: SchemeResolvedEvent) -> void:
	var scheme: SchemeRecord = _action.get_scheme(event.scheme_id, event.immortal_id)
	if scheme == null:
		return
	if not TRANSITIONS.has(scheme.action_type):
		return
	var target: CharacterRecord = _immortal_registry.get_character_record_any(scheme.target_ref)
	if target == null:
		return
	var transition: Array = TRANSITIONS[scheme.action_type]
	var from_status: StringName = transition[0]
	var to_status: StringName = transition[1]
	# Grandfathered chain members: skip from_status check if target already above expected
	# (existing chain members from data files didn't go through the cultivation ladder)
	if target.chain_status != from_status:
		return
	if event.outcome != &"success":
		return
	target.chain_status = to_status
	# Set or swap society_id
	var immortal: ImmortalRecord = _immortal_registry.get_immortal(scheme.immortal_id)
	if immortal != null:
		if target.society_id == &"" or target.society_id != immortal.society_id:
			# Recruit (steal): successful cultivation of another society's member swaps society_id
			target.society_id = immortal.society_id
	_last_promotion_day[scheme.target_ref] = _time_keeper.current_day
	_logger.info(LogChannels.CULTIVATION, "Cultivation success", {
		"target": scheme.target_ref, "from": from_status, "to": to_status,
	})
	var cult_event := CultivationAdvancedEvent.new()
	cult_event.target_character_id = scheme.target_ref
	cult_event.immortal_id = scheme.immortal_id
	cult_event.old_chain_status = from_status
	cult_event.new_chain_status = to_status
	cult_event.day = _time_keeper.current_day
	_event_bus.dispatch(cult_event)

func validate_cultivation_dispatch(action_type: StringName, target_ref: StringName) -> Dictionary:
	if not TRANSITIONS.has(action_type):
		return {"valid": true, "reason": ""}
	var target: CharacterRecord = _immortal_registry.get_character_record_any(target_ref)
	if target == null:
		return {"valid": false, "reason": "target is not a character"}
	var transition: Array = TRANSITIONS[action_type]
	if target.chain_status != transition[0]:
		return {"valid": false, "reason": "target chain_status is %s, expected %s" % [target.chain_status, transition[0]]}
	var last: int = _last_promotion_day.get(target_ref, -MIN_DAYS_BETWEEN_PROMOTIONS)
	if (_time_keeper.current_day - last) < MIN_DAYS_BETWEEN_PROMOTIONS:
		return {"valid": false, "reason": "promoted too recently"}
	return {"valid": true, "reason": ""}

func snapshot_state() -> Dictionary:
	return {"last_promotion_day": _last_promotion_day.duplicate(true)}

func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_last_promotion_day = state.get("last_promotion_day", {}).duplicate(true)
