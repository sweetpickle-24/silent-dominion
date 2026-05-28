extends GutTest

var _languages: Languages


func before_each():
	_languages = Languages.new()
	_languages.name = "Languages"
	add_child(_languages)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_languages):
		if _languages._tick_sub:
			eb.unsubscribe(_languages._tick_sub)
		remove_child(_languages)
		_languages.free()


func _make_language(id: StringName, prestige: int = 50, lf_scope: int = 0) -> LanguageRecord:
	var l := LanguageRecord.new()
	l.id = id
	l.display_name = "Test Language"
	l.prestige = prestige
	l.lingua_franca_scope = lf_scope
	l.vitality = &"stable"
	return l


func test_drift_per_period():
	var lang_a := _make_language(&"lang_a", 70)
	var lang_b := _make_language(&"lang_b", 30)
	_languages._languages.clear()
	_languages._composition.clear()
	_languages._languages[&"lang_a"] = lang_a
	_languages._languages[&"lang_b"] = lang_b
	_languages.set_composition(&"attica", &"lang_a", 80.0)
	_languages.set_composition(&"attica", &"lang_b", 20.0)
	_languages.set_composition(&"corinthia", &"lang_b", 90.0)
	_languages.set_composition(&"corinthia", &"lang_a", 10.0)
	# After drift, attica's lang_b should have grown slightly (pressure from corinthia)
	_languages._update_languages()
	var comp: Dictionary = _languages.get_composition(&"attica")
	# Lang_a should still dominate attica
	assert_gt(comp.get(&"lang_a", 0.0), 50.0, "Lang_a should still dominate in attica")


func test_prestige_neighbors_pull_share():
	var high_prestige := _make_language(&"high_p", 90)
	var low_prestige := _make_language(&"low_p", 20)
	_languages._languages[&"high_p"] = high_prestige
	_languages._languages[&"low_p"] = low_prestige
	var rate_high: float = _languages._language_transfer_rate(&"attica", &"corinthia", &"high_p", 1.0, 50.0)
	var rate_low: float = _languages._language_transfer_rate(&"attica", &"corinthia", &"low_p", 1.0, 50.0)
	assert_gt(rate_high, rate_low, "Higher prestige language should transfer faster")


func test_lingua_franca_spreads_along_routes():
	var lf_lang := _make_language(&"lf_lang", 50, 80)
	var normal := _make_language(&"normal", 50, 0)
	_languages._languages[&"lf_lang"] = lf_lang
	_languages._languages[&"normal"] = normal
	var rate_lf: float = _languages._language_transfer_rate(&"attica", &"corinthia", &"lf_lang", 1.5, 50.0)
	var rate_normal: float = _languages._language_transfer_rate(&"attica", &"corinthia", &"normal", 1.5, 50.0)
	assert_gt(rate_lf, rate_normal, "Lingua franca should spread faster along routes")


func test_language_death_in_region():
	var dying := _make_language(&"dying_lang")
	_languages._languages[&"dying_lang"] = dying
	_languages.set_composition(&"attica", &"dying_lang", 0.5)  # below death threshold
	var events: Array = []
	var eb: Node = get_node("/root/EventBus")
	var sub = eb.subscribe(
		preload("res://scripts/data/events/language_death_in_region_event.gd"),
		func(e): events.append(e), 50,
	)
	# Need sustained periods below threshold
	for i in range(Languages.SHARE_DEATH_SUSTAINED_PERIODS + 1):
		_languages._check_language_death(100 + i * 90)
	assert_gt(events.size(), 0, "Language death event should fire")
	var comp: Dictionary = _languages.get_composition(&"attica")
	assert_false(comp.has(&"dying_lang"), "Dead language should be removed from region")
	eb.unsubscribe(sub)


func test_dead_language_retains_liturgical_use():
	var dead := _make_language(&"dead_liturgical")
	dead.vitality = &"dead"
	dead.liturgical_use = 80
	_languages._languages[&"dead_liturgical"] = dead
	assert_false(dead.is_alive())
	assert_eq(dead.liturgical_use, 80, "Dead language can retain liturgical use")


func test_dominant_language():
	_languages._composition[&"test_region"] = {}
	_languages.set_composition(&"test_region", &"lang_x", 70.0)
	_languages.set_composition(&"test_region", &"lang_y", 30.0)
	assert_eq(_languages.dominant_language(&"test_region"), &"lang_x")


func test_lingua_franca_for_route():
	var lang := _make_language(&"trade_lang", 50, 80)
	_languages._languages[&"trade_lang"] = lang
	# Routes use place names as waypoints — set composition for the
	# endpoint waypoint values as if they were region ids
	var wr: Node = get_node("/root/WorldRegistry")
	var route: RouteRecord = wr.get_route(&"aegean_athens_corinth")
	if route == null or route.waypoints.size() < 2:
		pending("aegean_athens_corinth route not found")
		return
	var region_a: StringName = route.waypoints[0]
	var region_b: StringName = route.waypoints[route.waypoints.size() - 1]
	_languages.set_composition(region_a, &"trade_lang", 50.0)
	_languages.set_composition(region_b, &"trade_lang", 30.0)
	var lf: StringName = _languages.lingua_franca_for_route(&"aegean_athens_corinth")
	assert_eq(lf, &"trade_lang")


func test_normalize_shares():
	_languages.set_composition(&"test_region", &"a", 60.0)
	_languages.set_composition(&"test_region", &"b", 60.0)
	_languages._normalize_shares()
	var comp: Dictionary = _languages.get_composition(&"test_region")
	var total: float = comp.get(&"a", 0.0) + comp.get(&"b", 0.0)
	assert_almost_eq(total, 100.0, 1.0, "Shares should normalize to ~100")


func test_save_load_roundtrip():
	var lang := _make_language(&"save_lang")
	_languages._languages[&"save_lang"] = lang
	_languages.set_composition(&"attica", &"save_lang", 70.0)
	_languages._day_accumulator = 45
	var snapshot: Dictionary = _languages.snapshot_state()
	_languages._languages.clear()
	_languages._composition.clear()
	_languages._day_accumulator = 0
	_languages.apply_state(snapshot)
	assert_true(_languages._languages.has(&"save_lang"))
	assert_eq(_languages._day_accumulator, 45)
