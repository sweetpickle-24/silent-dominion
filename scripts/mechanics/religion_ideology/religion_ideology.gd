class_name ReligionIdeology
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _world_registry: Node

var _religions: Dictionary = {}         # StringName religion_id -> ReligionRecord
var _presence: Dictionary = {}          # StringName place_id -> Dictionary[religion_id -> Dictionary{follower_count, depth, institutional_presence, accumulated_grievance}]
var _diffusion: DiffusionEngine
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _tick_sub
var _day_accumulator: int = 0
var _next_religion_seq: int = 1

const UPDATE_PERIOD_DAYS: int = 30
const SPREAD_THRESHOLD: float = 5.0      # minimum follower_count to count as "present"
const CONSOLIDATION_FOLLOWER_THRESHOLD: int = 5000
const CONSOLIDATION_PLACE_THRESHOLD: int = 3
const DOMINANCE_PLACE_THRESHOLD: int = 5
const FRACTURE_REFORM_THRESHOLD: int = 80
const DECLINE_FOLLOWER_THRESHOLD: int = 500
const EXTINCTION_FOLLOWER_THRESHOLD: int = 10
const REFORM_ACCUMULATION_RATE: float = 0.1  # per period per rigidity point above 50
const GRIEVANCE_ACCUMULATION_RATE: float = 0.05


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_world_registry = get_node("/root/WorldRegistry")
	_rng.seed = hash("religion_seed") + Time.get_ticks_msec()
	_diffusion = DiffusionEngine.new(_rng)
	_load_religions()
	_tick_sub = _event_bus.subscribe(
		preload("res://scripts/data/events/game_day_ticked_event.gd"),
		Callable(self, "_on_game_day_ticked"),
		175, &"", EndOfTickPhases.WORLD_SHARED,
	)
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"religion_state",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)
	if _presence.is_empty() and not _religions.is_empty():
		_initialize_starting_presence()
	_logger.info(LogChannels.RELIGION, "ReligionIdeology mechanic ready", {
		"religions": _religions.size(),
		"places_with_presence": _presence.size(),
	})


func _load_religions() -> void:
	var dir := DirAccess.open("res://data/religions/")
	if dir == null:
		_logger.info(LogChannels.RELIGION, "No data/religions/ — no religions loaded")
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res = ResourceLoader.load("res://data/religions/" + fname)
			if res is ReligionRecord:
				_religions[res.id] = res
		fname = dir.get_next()
	dir.list_dir_end()


func _initialize_starting_presence() -> void:
	# Map cultural spheres to their dominant religion at 500 BCE
	var sphere_religions: Dictionary = {
		&"greek": &"greek_olympian",
		&"north_african_greek": &"greek_olympian",
		&"persian": &"zoroastrianism",
		&"egyptian": &"egyptian_polytheism",
		&"latin": &"roman_religio",
		&"punic": &"greek_olympian",  # Carthage had syncretic religion; placeholder
		&"phoenician": &"judaism",    # Phoenicia had Judaism among other faiths
	}
	var pop_node: Node = get_node_or_null("../Population")
	for place_id: StringName in _world_registry.all_place_ids():
		var place: PlaceRecord = _world_registry.get_place(place_id)
		if place == null:
			continue
		var province: ProvinceRecord = _world_registry.get_province(place.province)
		if province == null:
			continue
		var sphere: StringName = province.cultural_sphere
		var religion_id: StringName = sphere_religions.get(sphere, &"")
		if religion_id == &"" or not _religions.has(religion_id):
			continue
		var pop: int = place.population
		if pop_node != null:
			pop = pop_node.population_of(place_id)
		if pop <= 0:
			pop = place.population
		var follower_count: int = int(pop * 0.8)  # 80% of population follows dominant
		var depth: int = 60
		var institutional: bool = place.place_type in [&"city", &"town"]
		_set_presence(place_id, religion_id, follower_count, depth, institutional, 0.0)
	# Special cases
	if _religions.has(&"judaism"):
		_set_presence(&"sidon", &"judaism", 5000, 40, false, 0.0)
		_set_presence(&"tyre", &"judaism", 4000, 35, false, 0.0)
	if _religions.has(&"stoicism"):
		_set_presence(&"athens", &"stoicism", 500, 15, false, 0.0)


func _on_game_day_ticked(_event: GameDayTickedEvent) -> void:
	_day_accumulator += 1
	if _day_accumulator >= UPDATE_PERIOD_DAYS:
		_day_accumulator = 0
		_update_religions()


func _update_religions() -> void:
	var day: int = _time_keeper.current_day
	# 1. Run diffusion for each active religion
	var edges: Array = _build_place_edges()
	var prev_presence: Dictionary = _snapshot_presence()
	_diffusion.apply_deltas(_presence, _diffusion.diffuse_step(
		_presence, edges,
		Callable(self, "_religion_transfer_rate"),
	))
	# 2. Check for new spread (threshold crossings)
	var crossings: Array = _diffusion.find_threshold_crossings(_presence, SPREAD_THRESHOLD, prev_presence)
	for crossing: Dictionary in crossings:
		var event := ReligionSpreadIntoPlaceEvent.new()
		event.religion_id = crossing["entity_id"]
		event.place_id = crossing["node_id"]
		event.follower_count = int(crossing["value"])
		event.day = day
		_event_bus.dispatch(event)
	# 3. Update aggregate stats + reform potential
	for rid: StringName in _religions.keys():
		var r: ReligionRecord = _religions[rid]
		if not r.is_active():
			continue
		_update_reform_potential(r)
		_check_lifecycle_transitions(r, day)
	# 4. Scale follower counts with population
	_scale_followers_with_population()


func _religion_transfer_rate(from_id: StringName, to_id: StringName, entity_id: StringName, edge_weight: float, from_mag: float) -> float:
	var religion: ReligionRecord = _religions.get(entity_id, null)
	if religion == null or not religion.is_active():
		return 0.0
	# Base spread rate
	var rate: float = from_mag * 0.01 * edge_weight
	# Institutional presence at source boosts spread
	var from_pres: Dictionary = _presence.get(from_id, {}).get(entity_id, {})
	if from_pres.get("institutional_presence", false):
		rate *= 1.5
	# Ecumenical openness helps spread
	rate *= (0.5 + religion.ecumenical_openness / 100.0)
	# Target population scales opportunity
	var pop_node: Node = get_node_or_null("../Population")
	if pop_node != null:
		var target_pop: int = pop_node.population_of(to_id)
		rate *= clampf(target_pop / 50000.0, 0.1, 3.0)
	# Incumbent resistance at target
	var target_entities: Dictionary = _presence.get(to_id, {})
	for other_rid: StringName in target_entities.keys():
		if other_rid != entity_id:
			var other_mag: float = target_entities[other_rid].get("depth", 0.0) if target_entities[other_rid] is Dictionary else float(target_entities[other_rid])
			if other_mag > 50.0:
				rate *= 0.5  # strong incumbent resists
	return maxf(rate, 0.0)


func _build_place_edges() -> Array:
	var edges: Array = []
	# Province adjacency → place adjacency
	for prov_id: StringName in _world_registry.all_province_ids():
		var prov: ProvinceRecord = _world_registry.get_province(prov_id)
		if prov == null:
			continue
		var places_in: Array = _world_registry.places_in_province(prov_id)
		for neighbor_prov_id: StringName in prov.neighbors:
			var neighbor_places: Array = _world_registry.places_in_province(neighbor_prov_id)
			for p_a: PlaceRecord in places_in:
				for p_b: PlaceRecord in neighbor_places:
					edges.append({"from": p_a.id, "to": p_b.id, "weight": 1.0})
	# Route connections get extra weight
	for route_id: StringName in _world_registry.all_route_ids():
		var route: RouteRecord = _world_registry.get_route(route_id)
		if route == null:
			continue
		for i in range(route.waypoints.size() - 1):
			var from_prov: StringName = route.waypoints[i]
			var to_prov: StringName = route.waypoints[i + 1]
			var from_places: Array = _world_registry.places_in_province(from_prov)
			var to_places: Array = _world_registry.places_in_province(to_prov)
			for p_a: PlaceRecord in from_places:
				for p_b: PlaceRecord in to_places:
					edges.append({"from": p_a.id, "to": p_b.id, "weight": 2.0})
	return edges


func _update_reform_potential(r: ReligionRecord) -> void:
	if r.lifecycle_phase in [&"emergence", &"extinct"]:
		return
	var delta: float = 0.0
	# Rigidity drives reform
	if r.doctrinal_rigidity > 50:
		delta += (r.doctrinal_rigidity - 50) * REFORM_ACCUMULATION_RATE
	# Low ecumenical openness
	if r.ecumenical_openness < 40:
		delta += (40 - r.ecumenical_openness) * 0.05
	# Accumulated grievance from places
	for place_id: StringName in _presence.keys():
		var pres: Dictionary = _presence[place_id].get(r.id, {})
		if pres is Dictionary:
			var grievance: float = pres.get("accumulated_grievance", 0.0)
			delta += grievance * GRIEVANCE_ACCUMULATION_RATE
	# Read condition-weight accumulators from Population
	var pop_node: Node = get_node_or_null("../Population")
	if pop_node != null:
		for place_id: StringName in _presence.keys():
			if _presence[place_id].has(r.id):
				var weights: Dictionary = pop_node.get_weight_accumulators(place_id)
				var piety_weight: float = weights.get(&"piety", 0.0)
				if piety_weight > 1.0:
					delta += piety_weight * 0.1  # faith breeds critics
	r.reform_potential = clampi(r.reform_potential + int(delta), 0, 100)


func _check_lifecycle_transitions(r: ReligionRecord, day: int) -> void:
	var total: int = total_followers(r.id)
	var place_count: int = _count_places_with_presence(r.id)
	var old_phase: StringName = r.lifecycle_phase
	match r.lifecycle_phase:
		&"emergence":
			if total >= CONSOLIDATION_FOLLOWER_THRESHOLD and place_count >= CONSOLIDATION_PLACE_THRESHOLD:
				r.lifecycle_phase = &"consolidation"
		&"consolidation":
			if place_count >= DOMINANCE_PLACE_THRESHOLD and r.institutional_strength > 60:
				r.lifecycle_phase = &"dominance"
		&"dominance":
			if r.reform_potential >= FRACTURE_REFORM_THRESHOLD:
				r.lifecycle_phase = &"fracture"
				_fire_schism(r, day)
		&"fracture":
			r.lifecycle_phase = &"decline"  # fracture is transient → decline
	# Any phase can decline on low followers
	if r.lifecycle_phase not in [&"emergence", &"extinct"] and total < DECLINE_FOLLOWER_THRESHOLD:
		r.lifecycle_phase = &"decline"
	if r.lifecycle_phase == &"decline" and total < EXTINCTION_FOLLOWER_THRESHOLD:
		r.lifecycle_phase = &"extinct"
		var ext_event := ReligionWentExtinctEvent.new()
		ext_event.religion_id = r.id
		ext_event.day = day
		_event_bus.dispatch(ext_event)
	if r.lifecycle_phase != old_phase:
		var lc_event := ReligionLifecyclePhaseChangedEvent.new()
		lc_event.religion_id = r.id
		lc_event.old_phase = old_phase
		lc_event.new_phase = r.lifecycle_phase
		lc_event.day = day
		_event_bus.dispatch(lc_event)


func _fire_schism(parent: ReligionRecord, day: int) -> void:
	var child := ReligionRecord.new()
	child.id = StringName("schism_%s_%d" % [parent.id, _next_religion_seq])
	_next_religion_seq += 1
	child.display_name = "%s (Reform)" % parent.display_name
	child.kind = parent.kind
	child.founded_day = day
	child.parent_religion_id = parent.id
	child.doctrinal_rigidity = maxi(parent.doctrinal_rigidity - 20, 10)
	child.institutional_strength = maxi(parent.institutional_strength - 30, 10)
	child.popular_depth = parent.popular_depth
	child.ecumenical_openness = mini(parent.ecumenical_openness + 15, 90)
	child.reform_potential = 5
	child.lifecycle_phase = &"emergence"
	child.liturgical_language_id = parent.liturgical_language_id
	_religions[child.id] = child
	parent.schism_child_ids.append(child.id)
	parent.reform_potential = maxi(parent.reform_potential - 50, 0)
	# Transfer ~30% of followers to child
	for place_id: StringName in _presence.keys():
		if _presence[place_id].has(parent.id):
			var parent_pres: Dictionary = _presence[place_id][parent.id]
			if parent_pres is Dictionary:
				var transfer: int = int(parent_pres.get("follower_count", 0) * 0.3)
				if transfer > 0:
					parent_pres["follower_count"] = parent_pres.get("follower_count", 0) - transfer
					_set_presence(place_id, child.id, transfer, int(parent_pres.get("depth", 0) * 0.5), false, 0.0)
	var event := ReligionSchismOccurredEvent.new()
	event.parent_religion_id = parent.id
	event.child_religion_id = child.id
	event.day = day
	_event_bus.dispatch(event)
	_logger.info(LogChannels.RELIGION, "Schism occurred", {
		"parent": parent.id, "child": child.id,
	})


func _scale_followers_with_population() -> void:
	var pop_node: Node = get_node_or_null("../Population")
	if pop_node == null:
		return
	for place_id: StringName in _presence.keys():
		var total_pop: int = pop_node.population_of(place_id)
		if total_pop <= 0:
			continue
		var religions_here: Dictionary = _presence[place_id]
		# Normalize follower counts so total doesn't exceed population
		var total_followers_here: int = 0
		for rid: StringName in religions_here.keys():
			var pres = religions_here[rid]
			if pres is Dictionary:
				total_followers_here += pres.get("follower_count", 0)
		if total_followers_here > total_pop:
			var scale: float = float(total_pop) / float(total_followers_here)
			for rid: StringName in religions_here.keys():
				var pres = religions_here[rid]
				if pres is Dictionary:
					pres["follower_count"] = int(pres.get("follower_count", 0) * scale)


func _count_places_with_presence(religion_id: StringName) -> int:
	var count: int = 0
	for place_id: StringName in _presence.keys():
		if _presence[place_id].has(religion_id):
			var pres = _presence[place_id][religion_id]
			var fc: int = pres.get("follower_count", 0) if pres is Dictionary else int(pres)
			if fc > int(SPREAD_THRESHOLD):
				count += 1
	return count


func _snapshot_presence() -> Dictionary:
	var snapshot: Dictionary = {}
	for place_id: StringName in _presence.keys():
		snapshot[place_id] = {}
		for rid: StringName in _presence[place_id].keys():
			var pres = _presence[place_id][rid]
			if pres is Dictionary:
				snapshot[place_id][rid] = pres.get("depth", float(pres.get("follower_count", 0)))
			else:
				snapshot[place_id][rid] = float(pres)
	return snapshot


# --- Public API ---

func religions_in_place(place_id: StringName) -> Array:
	var result: Array = []
	var place_pres: Dictionary = _presence.get(place_id, {})
	for rid: StringName in place_pres.keys():
		var pres = place_pres[rid]
		var fc: int = pres.get("follower_count", 0) if pres is Dictionary else int(pres)
		result.append({"religion_id": rid, "follower_count": fc})
	result.sort_custom(func(a, b): return a["follower_count"] > b["follower_count"])
	return result


func dominant_religion(place_id: StringName) -> StringName:
	var religions: Array = religions_in_place(place_id)
	if religions.is_empty():
		return &""
	return religions[0]["religion_id"]


func total_followers(religion_id: StringName) -> int:
	var total: int = 0
	for place_id: StringName in _presence.keys():
		if _presence[place_id].has(religion_id):
			var pres = _presence[place_id][religion_id]
			total += pres.get("follower_count", 0) if pres is Dictionary else int(pres)
	return total


func religion_record(religion_id: StringName) -> ReligionRecord:
	return _religions.get(religion_id, null)


func all_religion_ids() -> Array:
	return _religions.keys()


func set_presence(place_id: StringName, religion_id: StringName, follower_count: int, depth: int = 50, institutional: bool = false, grievance: float = 0.0) -> void:
	_set_presence(place_id, religion_id, follower_count, depth, institutional, grievance)


func _set_presence(place_id: StringName, religion_id: StringName, follower_count: int, depth: int, institutional: bool, grievance: float) -> void:
	if not _presence.has(place_id):
		_presence[place_id] = {}
	_presence[place_id][religion_id] = {
		"follower_count": follower_count,
		"depth": depth,
		"institutional_presence": institutional,
		"accumulated_grievance": grievance,
	}


# --- Save/load ---

func snapshot_state() -> Dictionary:
	return {
		"religions": _religions.duplicate(true),
		"presence": _presence.duplicate(true),
		"day_accumulator": _day_accumulator,
		"next_religion_seq": _next_religion_seq,
		"rng_state": _rng.state,
	}


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_religions = state.get("religions", {}).duplicate(true)
	_presence = state.get("presence", {}).duplicate(true)
	_day_accumulator = state.get("day_accumulator", 0)
	_next_religion_seq = state.get("next_religion_seq", 1)
	_rng.state = state.get("rng_state", _rng.state)
	_logger.info(LogChannels.RELIGION, "ReligionIdeology state applied from load")
