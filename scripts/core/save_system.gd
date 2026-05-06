extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _logger: Node
var _event_bus: Node

# Threaded save state
var _save_thread: Thread = null
var _save_in_progress: bool = false

const SAVE_VERSION_CURRENT: int = 3

# Registration-based save handlers. Mechanics register at _ready.
var _snapshot_handlers: Dictionary = {}   # StringName state_key -> Callable
var _apply_handlers: Dictionary = {}      # StringName state_key -> Callable


func _ready() -> void:
	_logger = get_node("/root/Logger")
	_event_bus = get_node("/root/EventBus")
	_logger.info(LogChannels.SAVE_SYSTEM, "SaveSystem ready")


# === Registration API ===

func register_state_handlers(state_key: StringName, snapshot_callable: Callable, apply_callable: Callable) -> void:
	assert(not _snapshot_handlers.has(state_key), "Duplicate save state_key: %s" % state_key)
	_snapshot_handlers[state_key] = snapshot_callable
	_apply_handlers[state_key] = apply_callable
	if _logger.enabled_for(LogChannels.SAVE_SYSTEM, _LOG_DEBUG):
		_logger.debug(LogChannels.SAVE_SYSTEM, "Save handler registered", {"state_key": state_key})


# === Sync API (used by tests and as the worker-thread payload) ===

func save_to_file_sync(path: String) -> bool:
	var save_game := _snapshot()
	var err := ResourceSaver.save(save_game, path)
	if err != OK:
		_logger.error(LogChannels.SAVE_SYSTEM, "Save failed", {"path": path, "error": err})
		return false
	_logger.info(LogChannels.SAVE_SYSTEM, "Saved", {"path": path})
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
		_logger.warn(LogChannels.SAVE_SYSTEM, "Loading older save, will migrate", {
			"save_version": save_game.save_version,
			"current_version": SAVE_VERSION_CURRENT,
		})
	_logger.info(LogChannels.SAVE_SYSTEM, "Loaded", {"path": path, "version": save_game.save_version})
	return save_game


func apply_to_runtime(save_game: SaveGame) -> void:
	assert(save_game != null, "apply_to_runtime called with null SaveGame")
	var migrated: SaveGame = save_game
	if save_game.save_version < SAVE_VERSION_CURRENT:
		migrated = _migrate(save_game)
	for state_key: StringName in _apply_handlers.keys():
		var state: Variant = migrated.mechanic_states.get(state_key)
		if state == null:
			continue
		_apply_handlers[state_key].call(state)
	_logger.info(LogChannels.SAVE_SYSTEM, "Runtime state applied from save")


# === Async API (production save path) ===

func save_to_file_async(path: String) -> bool:
	if _save_in_progress:
		_logger.warn(LogChannels.SAVE_SYSTEM, "Save already in progress; dropping", {"path": path})
		return false
	_save_in_progress = true
	_event_bus.dispatch(SaveStartedEvent.new())
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
	var states: Dictionary = {}
	for state_key: StringName in _snapshot_handlers.keys():
		states[state_key] = _snapshot_handlers[state_key].call()
	save_game.mechanic_states = states
	return save_game


func _migrate(save_game: SaveGame) -> SaveGame:
	var migrated: SaveGame = save_game
	if migrated.save_version < 2:
		migrated = _migrate_v1_to_v2(migrated)
	if migrated.save_version < 3:
		migrated = _migrate_v2_to_v3(migrated)
	return migrated


func _migrate_v1_to_v2(v1: SaveGame) -> SaveGame:
	var v2 := SaveGame.new()
	v2.save_version = 2
	v2.save_mode = v1.save_mode
	var states: Dictionary = {}
	states[&"time_state"] = {
		"current_day": v1.game_day,
		"current_year": v1.current_year,
		"current_era": v1.current_era,
		"current_season": v1.current_season,
	}
	states[&"memoirs_libraries"] = v1.memoirs_libraries
	states[&"action_state"] = v1.action_state
	states[&"society_character_state"] = v1.society_character_state
	v2.mechanic_states = states
	_logger.info(LogChannels.SAVE_SYSTEM, "Migrated save v1 -> v2")
	return v2


func _migrate_v2_to_v3(v2: SaveGame) -> SaveGame:
	# v3: era rename &"classical" -> &"classical_collapse", remove &"industrial".
	# Corrects code-vs-vault drift from Step 2.
	var v3 := SaveGame.new()
	v3.save_version = 3
	v3.save_mode = v2.save_mode
	v3.mechanic_states = v2.mechanic_states.duplicate(true)
	var time_state: Dictionary = v3.mechanic_states.get(&"time_state", {})
	if time_state.get("current_era") == &"classical":
		time_state["current_era"] = &"classical_collapse"
		v3.mechanic_states[&"time_state"] = time_state
	_logger.info(LogChannels.SAVE_SYSTEM, "Migrated save v2 -> v3 (era rename)")
	return v3


func _create_empty_save() -> SaveGame:
	return SaveGame.new()
