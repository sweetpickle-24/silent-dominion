class_name Chain
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _action: Node
var _tick_subscription  # SubscriptionHandle

# Phase timings (placeholder per organisation.md §14.2 ranges, fixed values for Step 7).
const PHASE_TIMINGS: Dictionary = {
	&"dispatched": {"next": &"acknowledged", "days": 2},
	&"acknowledged": {"next": &"routing", "days": 3},
	&"routing": {"next": &"executing", "days": 5},
	&"executing": {"next": &"resolved", "days": 20},
}


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_action = get_node("../Action")
	_tick_subscription = _event_bus.subscribe(
		preload("res://scripts/data/events/game_day_ticked_event.gd"),
		Callable(self, "_on_game_day_ticked"),
		50,
		&"",
		EndOfTickPhases.PER_IMMORTAL,
	)
	_logger.info(LogChannels.CHAIN, "Chain mechanic ready")


func _on_game_day_ticked(_event: GameDayTickedEvent) -> void:
	_advance_schemes(_event.day)


func _advance_schemes(day: int) -> void:
	# Walk all immortals' active schemes. When a scheme has been in its current
	# phase for >= the placeholder day-count, fire SchemePhaseAdvanced.
	var all_immortal_ids: Array = [&"player"]
	for immortal_id: StringName in all_immortal_ids:
		var schemes: Array = _action.get_active_schemes(immortal_id)
		for scheme: SchemeRecord in schemes:
			var timing: Variant = PHASE_TIMINGS.get(scheme.current_phase)
			if timing == null:
				continue
			var days_in_phase: int = day - scheme.current_phase_entered_at_day
			if days_in_phase >= timing.days:
				var event := SchemePhaseAdvancedEvent.new()
				event.scheme_id = scheme.id
				event.immortal_id = scheme.immortal_id
				event.old_phase = scheme.current_phase
				event.new_phase = timing.next
				event.days_in_old_phase = days_in_phase
				_event_bus.dispatch(event)
