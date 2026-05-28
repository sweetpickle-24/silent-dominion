class_name Languages
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _world_registry: Node

var _languages: Dictionary = {}         # StringName language_id -> LanguageRecord
var _composition: Dictionary = {}       # StringName region_id -> Dictionary[language_id -> float share_pct]
var _diffusion: DiffusionEngine
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _tick_sub
var _day_accumulator: int = 0
var _next_lang_seq: int = 1

const UPDATE_PERIOD_DAYS: int = 90   # languages drift slowly — quarterly
const SHARE_DEATH_THRESHOLD: float = 1.0   # below 1% → removed from region
const SHARE_DEATH_SUSTAINED_PERIODS: int = 4  # must be below for this many periods
const VERNACULAR_ISOLATION_THRESHOLD: int = 3650  # ~10 years of linguistic isolation (placeholder)
const VERNACULAR_POP_THRESHOLD: int = 30000
const DRIFT_RATE: float = 0.02  # base share transfer rate

# Track how long a language has been below threshold per region
var _low_share_counters: Dictionary = {}  # "region:lang" -> int period count


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_world_registry = get_node("/root/WorldRegistry")
	_rng.seed = hash("language_seed") + Time.get_ticks_msec()
	_diffusion = DiffusionEngine.new(_rng)
	_load_languages()
	_tick_sub = _event_bus.subscribe(
		preload("res://scripts/data/events/game_day_ticked_event.gd"),
		Callable(self, "_on_game_day_ticked"),
		185, &"", EndOfTickPhases.WORLD_SHARED,
	)
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"languages_state",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)
	if _composition.is_empty() and not _languages.is_empty():
		_initialize_starting_composition()
	_logger.info(LogChannels.LANGUAGES, "Languages mechanic ready", {
		"languages": _languages.size(),
		"regions_with_composition": _composition.size(),
	})


func _initialize_starting_composition() -> void:
	# Map cultural spheres to their dominant language at 500 BCE
	var sphere_languages: Dictionary = {
		&"greek": {&"greek": 85.0, &"aramaic": 10.0},
		&"north_african_greek": {&"greek": 75.0, &"punic": 20.0},
		&"persian": {&"old_persian": 60.0, &"aramaic": 35.0},
		&"egyptian": {&"egyptian": 70.0, &"aramaic": 15.0, &"greek": 10.0},
		&"latin": {&"latin": 70.0, &"etruscan": 20.0, &"greek": 5.0},
		&"punic": {&"punic": 75.0, &"greek": 15.0},
		&"phoenician": {&"aramaic": 60.0, &"hebrew": 20.0, &"greek": 15.0},
	}
	for prov_id: StringName in _world_registry.all_province_ids():
		var prov: ProvinceRecord = _world_registry.get_province(prov_id)
		if prov == null:
			continue
		var sphere: StringName = prov.cultural_sphere
		var langs: Dictionary = sphere_languages.get(sphere, {&"greek": 80.0})
		if not _composition.has(prov_id):
			_composition[prov_id] = {}
		for lang_id: StringName in langs.keys():
			if _languages.has(lang_id):
				_composition[prov_id][lang_id] = langs[lang_id]
		# Fill remainder to ~100
		var total: float = 0.0
		for v: float in _composition[prov_id].values():
			total += v
		if total < 95.0:
			# Add a small "other" share to the dominant
			var dom: StringName = dominant_language(prov_id)
			if dom != &"":
				_composition[prov_id][dom] += (100.0 - total)


func _load_languages() -> void:
	var dir := DirAccess.open("res://data/languages/")
	if dir == null:
		_logger.info(LogChannels.LANGUAGES, "No data/languages/ — no languages loaded")
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res = ResourceLoader.load("res://data/languages/" + fname)
			if res is LanguageRecord:
				_languages[res.id] = res
		fname = dir.get_next()
	dir.list_dir_end()


func _on_game_day_ticked(_event: GameDayTickedEvent) -> void:
	_day_accumulator += 1
	if _day_accumulator >= UPDATE_PERIOD_DAYS:
		_day_accumulator = 0
		_update_languages()


func _update_languages() -> void:
	var day: int = _time_keeper.current_day
	# 1. Drift: neighboring regions' prestige languages leak in
	var edges: Array = _build_region_edges()
	_diffusion.apply_deltas(_composition, _diffusion.diffuse_step(
		_composition, edges,
		Callable(self, "_language_transfer_rate"),
	))
	# 2. Religious institutional language boost
	_apply_liturgical_pressure()
	# 3. Normalize shares per region
	_normalize_shares()
	# 4. Check language death per region
	_check_language_death(day)
	# 5. Check vernacular emergence
	_check_vernacular_emergence(day)
	# 6. Update vitality
	_update_vitality()


func _language_transfer_rate(from_region: StringName, _to_region: StringName, lang_id: StringName, edge_weight: float, from_share: float) -> float:
	var lang: LanguageRecord = _languages.get(lang_id, null)
	if lang == null:
		return 0.0
	# Prestige drives spread
	var rate: float = from_share * DRIFT_RATE * edge_weight
	rate *= (0.5 + lang.prestige / 100.0)
	# Lingua franca scope boosts along trade routes
	rate *= (1.0 + lang.lingua_franca_scope / 100.0 * 0.5)
	return maxf(rate, 0.0)


func _build_region_edges() -> Array:
	var edges: Array = []
	for prov_id: StringName in _world_registry.all_province_ids():
		var prov: ProvinceRecord = _world_registry.get_province(prov_id)
		if prov == null:
			continue
		for neighbor_id: StringName in prov.neighbors:
			edges.append({"from": prov_id, "to": neighbor_id, "weight": 1.0})
	# Routes add extra weight
	for route_id: StringName in _world_registry.all_route_ids():
		var route: RouteRecord = _world_registry.get_route(route_id)
		if route == null:
			continue
		for i in range(route.waypoints.size() - 1):
			edges.append({"from": route.waypoints[i], "to": route.waypoints[i + 1], "weight": 1.5})
	return edges


func _apply_liturgical_pressure() -> void:
	var rel_node: Node = get_node_or_null("../ReligionIdeology")
	if rel_node == null:
		return
	for region_id: StringName in _composition.keys():
		var places: Array = _world_registry.places_in_province(region_id)
		for place: PlaceRecord in places:
			var dom_rel_id: StringName = rel_node.dominant_religion(place.id)
			if dom_rel_id == &"":
				continue
			var rel: ReligionRecord = rel_node.religion_record(dom_rel_id)
			if rel == null or rel.liturgical_language_id == &"":
				continue
			var lit_lang_id: StringName = rel.liturgical_language_id
			if _languages.has(lit_lang_id) and _composition[region_id].has(lit_lang_id):
				# Small boost to liturgical language's share
				_composition[region_id][lit_lang_id] += 0.1


func _normalize_shares() -> void:
	for region_id: StringName in _composition.keys():
		var langs: Dictionary = _composition[region_id]
		var total: float = 0.0
		for share: float in langs.values():
			total += share
		if total > 0.0 and absf(total - 100.0) > 0.1:
			var scale: float = 100.0 / total
			for lang_id: StringName in langs.keys():
				langs[lang_id] *= scale


func _check_language_death(day: int) -> void:
	for region_id: StringName in _composition.keys():
		var langs: Dictionary = _composition[region_id]
		var to_remove: Array = []
		for lang_id: StringName in langs.keys():
			if langs[lang_id] < SHARE_DEATH_THRESHOLD:
				var key: String = "%s:%s" % [region_id, lang_id]
				var count: int = _low_share_counters.get(key, 0) + 1
				_low_share_counters[key] = count
				if count >= SHARE_DEATH_SUSTAINED_PERIODS:
					to_remove.append(lang_id)
					var event := LanguageDeathInRegionEvent.new()
					event.language_id = lang_id
					event.region_id = region_id
					event.day = day
					_event_bus.dispatch(event)
			else:
				var key: String = "%s:%s" % [region_id, lang_id]
				_low_share_counters.erase(key)
		for lang_id: StringName in to_remove:
			langs.erase(lang_id)


func _check_vernacular_emergence(day: int) -> void:
	# Only check if enough time has passed (placeholder: game year > 100)
	if _time_keeper.current_day < VERNACULAR_ISOLATION_THRESHOLD:
		return
	var pop_node: Node = get_node_or_null("../Population")
	for region_id: StringName in _composition.keys():
		var langs: Dictionary = _composition[region_id]
		if langs.size() <= 1:
			# Only one language — isolation condition met
			var dom_lang_id: StringName = dominant_language(region_id)
			if dom_lang_id == &"":
				continue
			# Check population threshold
			var region_pop: int = 0
			if pop_node != null:
				for place: PlaceRecord in _world_registry.places_in_province(region_id):
					region_pop += pop_node.population_of(place.id)
			if region_pop < VERNACULAR_POP_THRESHOLD:
				continue
			# Check parent language isn't already a vernacular of itself
			var parent: LanguageRecord = _languages.get(dom_lang_id, null)
			if parent == null:
				continue
			# Don't spawn if a child already exists for this region
			var already_spawned: bool = false
			for lid: StringName in _languages.keys():
				var l: LanguageRecord = _languages[lid]
				if l.parent_language_id == dom_lang_id and l.origin_region_id == region_id:
					already_spawned = true
					break
			if already_spawned:
				continue
			# Spawn vernacular
			var vernacular := LanguageRecord.new()
			vernacular.id = StringName("vernacular_%s_%d" % [region_id, _next_lang_seq])
			_next_lang_seq += 1
			vernacular.display_name = "%s vernacular (%s)" % [parent.display_name, region_id]
			vernacular.origin_region_id = region_id
			vernacular.parent_language_id = dom_lang_id
			vernacular.prestige = maxi(parent.prestige - 20, 5)
			vernacular.vitality = &"emerging"
			_languages[vernacular.id] = vernacular
			# Give it initial share taken from parent
			var parent_share: float = langs.get(dom_lang_id, 0.0)
			var vernacular_share: float = parent_share * 0.1  # starts at 10% of parent
			langs[vernacular.id] = vernacular_share
			langs[dom_lang_id] = parent_share - vernacular_share
			var event := LanguageEmergedEvent.new()
			event.language_id = vernacular.id
			event.parent_language_id = dom_lang_id
			event.region_id = region_id
			event.day = day
			_event_bus.dispatch(event)
			_logger.info(LogChannels.LANGUAGES, "Vernacular emerged", {
				"id": vernacular.id, "parent": dom_lang_id, "region": region_id,
			})


func _update_vitality() -> void:
	for lang_id: StringName in _languages.keys():
		var lang: LanguageRecord = _languages[lang_id]
		var total_share: float = 0.0
		var region_count: int = 0
		for region_id: StringName in _composition.keys():
			var share: float = _composition[region_id].get(lang_id, 0.0)
			if share > 0.0:
				total_share += share
				region_count += 1
		if region_count == 0 and lang.liturgical_use <= 0:
			lang.vitality = &"dead"
		elif total_share < 50.0 and lang.vitality in [&"stable", &"growing"]:
			lang.vitality = &"declining"
		elif total_share > 200.0 and lang.vitality in [&"emerging", &"stable"]:
			lang.vitality = &"growing"


# --- Public API ---

func languages_in_region(region_id: StringName) -> Array:
	var result: Array = []
	var comp: Dictionary = _composition.get(region_id, {})
	for lang_id: StringName in comp.keys():
		result.append({"language_id": lang_id, "share": comp[lang_id]})
	result.sort_custom(func(a, b): return a["share"] > b["share"])
	return result


func dominant_language(region_id: StringName) -> StringName:
	var langs: Array = languages_in_region(region_id)
	if langs.is_empty():
		return &""
	return langs[0]["language_id"]


func lingua_franca_for_route(route_id: StringName) -> StringName:
	var route: RouteRecord = _world_registry.get_route(route_id)
	if route == null or route.waypoints.size() < 2:
		return &""
	# Find the language with highest lingua_franca_scope present in both endpoint regions
	var region_a: StringName = route.waypoints[0]
	var region_b: StringName = route.waypoints[route.waypoints.size() - 1]
	var best_id: StringName = &""
	var best_scope: int = 0
	var langs_a: Dictionary = _composition.get(region_a, {})
	var langs_b: Dictionary = _composition.get(region_b, {})
	for lang_id: StringName in langs_a.keys():
		if langs_b.has(lang_id):
			var lang: LanguageRecord = _languages.get(lang_id, null)
			if lang != null and lang.lingua_franca_scope > best_scope:
				best_scope = lang.lingua_franca_scope
				best_id = lang_id
	return best_id


func language_record(lang_id: StringName) -> LanguageRecord:
	return _languages.get(lang_id, null)


func all_language_ids() -> Array:
	return _languages.keys()


func set_composition(region_id: StringName, lang_id: StringName, share: float) -> void:
	if not _composition.has(region_id):
		_composition[region_id] = {}
	_composition[region_id][lang_id] = share


func get_composition(region_id: StringName) -> Dictionary:
	return _composition.get(region_id, {})


# --- Save/load ---

func snapshot_state() -> Dictionary:
	return {
		"languages": _languages.duplicate(true),
		"composition": _composition.duplicate(true),
		"day_accumulator": _day_accumulator,
		"next_lang_seq": _next_lang_seq,
		"low_share_counters": _low_share_counters.duplicate(true),
		"rng_state": _rng.state,
	}


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_languages = state.get("languages", {}).duplicate(true)
	_composition = state.get("composition", {}).duplicate(true)
	_day_accumulator = state.get("day_accumulator", 0)
	_next_lang_seq = state.get("next_lang_seq", 1)
	_low_share_counters = state.get("low_share_counters", {}).duplicate(true)
	_rng.state = state.get("rng_state", _rng.state)
	_logger.info(LogChannels.LANGUAGES, "Languages state applied from load")
