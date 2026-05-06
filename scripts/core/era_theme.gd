extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")

var _logger: Node
var _event_bus: Node
var _subscription

var current_era: StringName = EraValues.ANCIENT


func _ready() -> void:
	_logger = get_node("/root/Logger")
	_event_bus = get_node("/root/EventBus")
	var time_keeper: Node = get_node("/root/TimeKeeper")
	current_era = time_keeper.current_era
	_subscription = _event_bus.subscribe(
		preload("res://scripts/data/events/era_transitioned_event.gd"),
		Callable(self, "_on_era_transitioned"),
		50,
		&"",
		EndOfTickPhases.WORLD_SHARED,
	)
	_logger.info(LogChannels.ERA_THEME, "EraTheme ready", {"current_era": current_era})


func _on_era_transitioned(event: EraTransitionedEvent) -> void:
	current_era = event.new_era
	_logger.info(LogChannels.ERA_THEME, "Era theme updated", {
		"old_era": event.old_era,
		"new_era": event.new_era,
	})
