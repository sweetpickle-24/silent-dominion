class_name Place
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG
const _GameDayTickedEventScript := preload("res://scripts/data/events/game_day_ticked_event.gd")

var _event_bus: Node
var _logger: Node
var _world_registry: Node


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_world_registry = get_node("/root/WorldRegistry")
	_event_bus.subscribe(
		_GameDayTickedEventScript,
		Callable(self, "_on_game_day_ticked"),
		10,
		&"",
		EndOfTickPhases.WORLD_SHARED,
	)
	_logger.info(LogChannels.PLACE, "Place mechanic ready", {
		"loaded_place_count": _world_registry.place_count(),
	})


func _on_game_day_ticked(event: GameDayTickedEvent) -> void:
	update_per_day(event.day)


func update_per_day(day: int) -> void:
	# T1-6 (per-place-type update logic) is a Tier 1 design gap.
	# This is a stub. Walks loaded places to verify the subscription fires
	# with the registry populated, but does no per-place work.
	if _logger.enabled_for(LogChannels.PLACE, _LOG_DEBUG):
		_logger.debug(LogChannels.PLACE, "Place tick", {
			"day": day,
			"place_count": _world_registry.place_count(),
		})
