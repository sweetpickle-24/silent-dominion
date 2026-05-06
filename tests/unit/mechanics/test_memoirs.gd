extends GutTest

var _memoirs: Memoirs
var _save_system: Node
var _time_keeper: Node

const TEST_SAVE_PATH: String = "user://saves/test_memoirs_save.tres"


func _make_pattern(id: StringName, category: StringName = PatternCategories.BRIBE, last_validated_day: int = 0) -> Pattern:
	var p := Pattern.new()
	p.id = id
	p.name = "Pattern %s" % id
	p.category = category
	p.era = &"ancient"
	p.last_validated_day = last_validated_day
	return p


func before_each():
	_save_system = get_node("/root/SaveSystem")
	_time_keeper = get_node("/root/TimeKeeper")
	# Create a local Memoirs node for testing (main scene isn't loaded in GUT).
	_memoirs = Memoirs.new()
	_memoirs.name = "Memoirs"
	add_child(_memoirs)
	DirAccess.make_dir_recursive_absolute("user://saves/")


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_memoirs):
		if _memoirs._tick_sub:
			eb.unsubscribe(_memoirs._tick_sub)
		if _memoirs._scheme_resolved_sub:
			eb.unsubscribe(_memoirs._scheme_resolved_sub)
		remove_child(_memoirs)
		_memoirs.free()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)
	_time_keeper.apply_state({"current_day": 0, "current_year": 0, "current_era": &"ancient", "current_season": &"winter"})


func test_add_pattern():
	var p := _make_pattern(&"test_add")
	_memoirs.add_pattern(p)
	var lib: MemoirsLibrary = _memoirs.get_library(&"player")
	assert_not_null(lib)
	assert_eq(lib.get_pattern(&"test_add"), p)


func test_find_top_matches_empty():
	var ctx := RuleContext.new()
	ctx.world = WorldView.snapshot()
	ctx.helpers = get_node("/root/Helpers")
	var matches: Array = _memoirs.find_top_matches(PatternCategories.BRIBE, ctx)
	assert_eq(matches.size(), 0)


func test_find_top_matches_filters_by_category():
	_memoirs.add_pattern(_make_pattern(&"b1", PatternCategories.BRIBE))
	_memoirs.add_pattern(_make_pattern(&"b2", PatternCategories.BRIBE))
	_memoirs.add_pattern(_make_pattern(&"b3", PatternCategories.BRIBE))
	_memoirs.add_pattern(_make_pattern(&"c1", PatternCategories.CULTIVATE))
	_memoirs.add_pattern(_make_pattern(&"c2", PatternCategories.CULTIVATE))

	var ctx := RuleContext.new()
	ctx.world = WorldView.snapshot()
	ctx.helpers = get_node("/root/Helpers")

	var bribe_matches: Array = _memoirs.find_top_matches(PatternCategories.BRIBE, ctx)
	assert_eq(bribe_matches.size(), 3)

	var cultivate_matches: Array = _memoirs.find_top_matches(PatternCategories.CULTIVATE, ctx)
	assert_eq(cultivate_matches.size(), 2)


func test_find_top_matches_capped():
	for i in range(15):
		_memoirs.add_pattern(_make_pattern(StringName("p%d" % i), PatternCategories.BRIBE))
	var ctx := RuleContext.new()
	ctx.world = WorldView.snapshot()
	ctx.helpers = get_node("/root/Helpers")
	var matches: Array = _memoirs.find_top_matches(PatternCategories.BRIBE, ctx, 10)
	assert_eq(matches.size(), 10)


func test_staleness_fresh_at_threshold():
	var p := _make_pattern(&"s1", PatternCategories.BRIBE, 0)
	_memoirs.add_pattern(p)
	_memoirs._check_staleness_transitions(StalenessValues.FRESH_THRESHOLD_DAYS)
	assert_eq(p.staleness_state, StalenessValues.FRESH)


func test_staleness_aging_past_threshold():
	var p := _make_pattern(&"s2", PatternCategories.BRIBE, 0)
	_memoirs.add_pattern(p)
	_memoirs._check_staleness_transitions(StalenessValues.FRESH_THRESHOLD_DAYS + 1)
	assert_eq(p.staleness_state, StalenessValues.AGING)


func test_staleness_stale_past_threshold():
	var p := _make_pattern(&"s3", PatternCategories.BRIBE, 0)
	_memoirs.add_pattern(p)
	_memoirs._check_staleness_transitions(StalenessValues.STALE_THRESHOLD_DAYS + 1)
	assert_eq(p.staleness_state, StalenessValues.STALE)


func test_validate_pattern_resets_staleness():
	var p := _make_pattern(&"v1", PatternCategories.BRIBE, 0)
	p.staleness_state = StalenessValues.AGING
	_memoirs.add_pattern(p)
	_memoirs.validate_pattern(&"v1", 5000)
	assert_eq(p.staleness_state, StalenessValues.FRESH)
	assert_eq(p.last_validated_day, 5000)
	assert_eq(p.success_count, 1)


func test_save_load_roundtrip():
	_memoirs.add_pattern(_make_pattern(&"player_p1", PatternCategories.BRIBE), &"player")
	_memoirs.add_pattern(_make_pattern(&"player_p2", PatternCategories.CULTIVATE), &"player")
	_memoirs.add_pattern(_make_pattern(&"rival_p1", PatternCategories.REMOVE), &"test_rival")
	_memoirs.add_pattern(_make_pattern(&"rival_p2", PatternCategories.FALSE_FLAG), &"test_rival")

	# Snapshot and save manually (SaveSystem can't reach our local Memoirs node)
	var save_game := SaveGame.new()
	save_game.save_version = 1
	save_game.game_day = 100
	save_game.current_era = &"ancient"
	save_game.current_season = &"winter"
	save_game.memoirs_libraries = _memoirs.snapshot_state()
	ResourceSaver.save(save_game, TEST_SAVE_PATH)

	# Reset Memoirs
	_memoirs.apply_state({})
	assert_eq(_memoirs.get_library(&"player").patterns.size(), 0)
	assert_null(_memoirs.get_library(&"test_rival"))

	# Load and apply
	var loaded: SaveGame = ResourceLoader.load(TEST_SAVE_PATH) as SaveGame
	assert_not_null(loaded)
	_memoirs.apply_state(loaded.memoirs_libraries)

	var player_lib: MemoirsLibrary = _memoirs.get_library(&"player")
	assert_not_null(player_lib)
	assert_eq(player_lib.patterns.size(), 2)
	assert_not_null(player_lib.get_pattern(&"player_p1"))

	var rival_lib: MemoirsLibrary = _memoirs.get_library(&"test_rival")
	assert_not_null(rival_lib)
	assert_eq(rival_lib.patterns.size(), 2)
	assert_eq(rival_lib.get_pattern(&"rival_p2").category, PatternCategories.FALSE_FLAG)
