extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _logger: Node
var _event_bus: Node
var _time_keeper: Node

# Threaded save state
var _save_thread: Thread = null
var _save_in_progress: bool = false

const SAVE_VERSION_CURRENT: int = 1


func _ready() -> void:
	_logger = get_node("/root/Logger")
	_event_bus = get_node("/root/EventBus")
	_time_keeper = get_node("/root/TimeKeeper")
	_logger.info(LogChannels.SAVE_SYSTEM, "SaveSystem ready")


# === Sync API (used by tests and as the worker-thread payload) ===

func save_to_file_sync(path: String) -> bool:
	var save_game := _snapshot()
	var err := ResourceSaver.save(save_game, path)
	if err != OK:
		_logger.error(LogChannels.SAVE_SYSTEM, "Save failed", {"path": path, "error": err})
		return false
	_logger.info(LogChannels.SAVE_SYSTEM, "Saved", {"path": path, "day": save_game.game_day})
	return true


func load_from_file_sync(path: String) -> SaveGame:
	if not ResourceLoader.exists(path):
		_logger.error(LogChannels.SAVE_SYSTEM, "Load failed: file does not exist", {"path": path})
		return null
	var resource := ResourceLoader.load(path)
	if resource == null or not (resource is SaveGame):
		_logger.error(LogChannels.SAVE_SYSTEM, "Load failed: not a SaveGame", {"path": path})
		return null
	var save_game := resource as SaveGame
	if save_game.save_version > SAVE_VERSION_CURRENT:
		_logger.error(LogChannels.SAVE_SYSTEM, "Load failed: save version from the future", {
			"save_version": save_game.save_version,
			"current_version": SAVE_VERSION_CURRENT,
		})
		return null
	if save_game.save_version < SAVE_VERSION_CURRENT:
		_logger.warn(LogChannels.SAVE_SYSTEM, "Loading older save", {
			"save_version": save_game.save_version,
			"current_version": SAVE_VERSION_CURRENT,
		})
	_logger.info(LogChannels.SAVE_SYSTEM, "Loaded", {"path": path, "day": save_game.game_day})
	return save_game


func apply_to_runtime(save_game: SaveGame) -> void:
	assert(save_game != null, "apply_to_runtime called with null SaveGame")
	_time_keeper.apply_loaded_state(
		save_game.game_day,
		save_game.current_year,
		save_game.current_era,
		save_game.current_season,
	)
	var memoirs: Node = get_node_or_null("/root/Main/Mechanics/Memoirs")
	if memoirs:
		memoirs.apply_state(save_game.memoirs_libraries)
	_logger.info(LogChannels.SAVE_SYSTEM, "Runtime state applied from save", {
		"day": save_game.game_day,
	})


# === Async API (production save path) ===

func save_to_file_async(path: String) -> bool:
	if _save_in_progress:
		_logger.warn(LogChannels.SAVE_SYSTEM, "Save already in progress; dropping", {"path": path})
		return false
	_save_in_progress = true
	_event_bus.dispatch(SaveStartedEvent.new())
	# Snapshot state on the main thread before spinning the worker,
	# per a2-save-format.md §5.5 — concurrent mutation must not corrupt
	# the in-flight save.
	var snapshot := _snapshot()
	_save_thread = Thread.new()
	_save_thread.start(_worker_save.bind(snapshot, path))
	return true


func _worker_save(save_game: SaveGame, path: String) -> void:
	var err := ResourceSaver.save(save_game, path)
	call_deferred("_finish_save", path, err)


func _finish_save(path: String, err: int) -> void:
	if _save_thread != null:
		_save_thread.wait_to_finish()
		_save_thread = null
	_save_in_progress = false
	if err == OK:
		_logger.info(LogChannels.SAVE_SYSTEM, "Async save completed", {"path": path})
		_event_bus.dispatch(SaveCompletedEvent.new())
	else:
		_logger.error(LogChannels.SAVE_SYSTEM, "Async save failed", {"path": path, "error": err})
		var failed_event := SaveFailedEvent.new()
		failed_event.error_code = err
		failed_event.path = path
		_event_bus.dispatch(failed_event)


# === Internal ===

func _snapshot() -> SaveGame:
	var save_game := SaveGame.new()
	save_game.save_version = SAVE_VERSION_CURRENT
	save_game.save_mode = &"standard"
	save_game.game_day = _time_keeper.current_day
	save_game.current_year = _time_keeper.current_year
	save_game.current_era = _time_keeper.current_era
	save_game.current_season = _time_keeper.current_season
	var memoirs: Node = get_node_or_null("/root/Main/Mechanics/Memoirs")
	if memoirs:
		save_game.memoirs_libraries = memoirs.snapshot_state()
	return save_game


func _create_empty_save() -> SaveGame:
	return SaveGame.new()
