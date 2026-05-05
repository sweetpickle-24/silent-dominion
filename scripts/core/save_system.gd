extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")

var _logger: Node


func _ready() -> void:
	_logger = get_node("/root/Logger")
	_logger.info(LogChannels.SAVE_SYSTEM, "SaveSystem ready")


func _create_empty_save() -> SaveGame:
	return SaveGame.new()

# TODO: save(path) — threaded save dispatch (Step 5)
# TODO: load_save(path) — load + migration (Step 5)
