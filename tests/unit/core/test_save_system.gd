extends GutTest

const TEST_SAVE_PATH: String = "user://saves/test_save.tres"

var _save_system: Node
var _time_keeper: Node


func before_each():
	_save_system = get_node("/root/SaveSystem")
	_time_keeper = get_node("/root/TimeKeeper")
	# Ensure saves directory exists
	DirAccess.make_dir_recursive_absolute("user://saves/")


func after_each():
	# Clean up test save files
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)
	# Reset TimeKeeper to defaults
	_time_keeper.apply_state({"current_day": 0, "current_year": 0, "current_era": &"ancient", "current_season": &"winter"})


func test_sync_roundtrip():
	# Set TimeKeeper to a specific state
	_time_keeper.apply_state({"current_day": 42, "current_year": 10, "current_era": &"classical_collapse", "current_season": &"summer"})
	assert_eq(_time_keeper.current_day, 42)

	# Save
	var saved: bool = _save_system.save_to_file_sync(TEST_SAVE_PATH)
	assert_true(saved, "save_to_file_sync should succeed")

	# Reset TimeKeeper to defaults
	_time_keeper.apply_state({"current_day": 0, "current_year": 0, "current_era": &"ancient", "current_season": &"winter"})
	assert_eq(_time_keeper.current_day, 0)

	# Load and apply
	var save_game: SaveGame = _save_system.load_from_file_sync(TEST_SAVE_PATH)
	assert_not_null(save_game, "load_from_file_sync should return a SaveGame")
	_save_system.apply_to_runtime(save_game)

	# Verify restored state
	assert_eq(_time_keeper.current_day, 42)
	assert_eq(_time_keeper.current_year, 10)
	assert_eq(_time_keeper.current_era, &"classical_collapse")
	assert_eq(_time_keeper.current_season, &"summer")


func test_future_version_rejected():
	# Construct a SaveGame with a future version
	var future_save := SaveGame.new()
	future_save.save_version = 999
	future_save.game_day = 100
	ResourceSaver.save(future_save, TEST_SAVE_PATH)

	var loaded: SaveGame = _save_system.load_from_file_sync(TEST_SAVE_PATH)
	assert_null(loaded, "Future save version should be rejected")


func test_older_version_loads_with_warning():
	# Construct a SaveGame with an older version
	var old_save := SaveGame.new()
	old_save.save_version = 0
	old_save.game_day = 50
	ResourceSaver.save(old_save, TEST_SAVE_PATH)

	var loaded: SaveGame = _save_system.load_from_file_sync(TEST_SAVE_PATH)
	assert_not_null(loaded, "Older save version should load successfully")
	assert_eq(loaded.game_day, 50)


func test_missing_file_returns_null():
	var loaded: SaveGame = _save_system.load_from_file_sync("user://saves/nonexistent_save.tres")
	assert_null(loaded, "Missing file should return null")


func test_wrong_type_returns_null():
	# Save a PlaceRecord (not a SaveGame) to the path
	var place := PlaceRecord.new()
	place.id = &"fake"
	ResourceSaver.save(place, TEST_SAVE_PATH)

	var loaded: SaveGame = _save_system.load_from_file_sync(TEST_SAVE_PATH)
	assert_null(loaded, "Non-SaveGame resource should return null")


func test_world_registry_isolation():
	var wr: Node = get_node("/root/WorldRegistry")

	# Confirm WorldRegistry has places before save
	assert_eq(wr.place_count(), 22)
	var athens: PlaceRecord = wr.get_place(&"athens")
	assert_not_null(athens)
	assert_eq(athens.name, "Athens")

	# Set TimeKeeper to day 5 and save
	_time_keeper.apply_state({"current_day": 5, "current_year": 0, "current_era": &"ancient", "current_season": &"winter"})
	_save_system.save_to_file_sync(TEST_SAVE_PATH)

	# Verify WorldRegistry is unchanged after save
	assert_eq(wr.place_count(), 22)
	assert_eq(wr.get_place(&"athens").name, "Athens")

	# Load the save and apply
	var save_game: SaveGame = _save_system.load_from_file_sync(TEST_SAVE_PATH)
	_save_system.apply_to_runtime(save_game)

	# WorldRegistry still intact after load
	assert_eq(wr.place_count(), 22)
	assert_eq(wr.get_place(&"athens").name, "Athens")
	assert_eq(wr.get_place(&"laurion").place_type, &"mine")
	assert_eq(wr.get_place(&"delphi").province, &"phocis")
