class_name CharGeneration
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _world_registry: Node
var _immortal_registry: Node

var _tick_sub
var _day_accumulator: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _rng_seed: int = 0
var _next_gen_id: int = 1

# Generated character tracking for GC
var _generated_ids: Array[StringName] = []
var _gc_day_accumulator: int = 0

# Generation cadence: generate characters every N days (~1 year)
const GENERATION_PERIOD_DAYS: int = 365
# GC sweep cadence
const GC_PERIOD_DAYS: int = 1825  # ~5 years
# GC staleness: dead characters older than this (days since death) are eligible
const GC_DEAD_RETENTION_DAYS: int = 3650  # keep dead chars for ~10 years
# GC alive staleness: alive but irrelevant chars older than this since birth
const GC_ALIVE_STALENESS_DAYS: int = 36500  # ~100 years

# Base trait distributions per cultural sphere: {trait_id: {mean, spread}}
const BASE_DISTRIBUTIONS: Dictionary = {
	&"greek": {&"intellect": 55, &"curiosity": 55, &"ambition": 50, &"piety": 45, &"charisma": 52},
	&"persian": {&"ambition": 55, &"loyalty": 55, &"piety": 50, &"ruthlessness": 50},
	&"phoenician": {&"greed": 55, &"intellect": 52, &"charisma": 55, &"resilience": 50},
	&"egyptian": {&"piety": 58, &"loyalty": 52, &"resilience": 55, &"intellect": 52},
	&"latin": {&"ambition": 52, &"loyalty": 55, &"resilience": 55, &"ruthlessness": 48},
	&"punic": {&"greed": 55, &"ambition": 52, &"ruthlessness": 50, &"charisma": 50},
	&"north_african_greek": {&"intellect": 53, &"curiosity": 53, &"piety": 48},
}

# Name fragment tables per cultural sphere (mechanical placeholder names)
const NAME_FRAGMENTS: Dictionary = {
	&"greek": {
		"prefix": ["Ari", "Demo", "Epi", "Hera", "Kleo", "Lysi", "Niko", "Peri", "Poly", "Theo", "Xeno", "Anti", "Dio", "Eury", "Hippo", "Mega", "Philo", "Pyrrho", "Sopho", "Timo"],
		"suffix": ["kles", "doros", "genes", "krates", "machos", "medes", "nikos", "phanes", "stratos", "thenes"],
	},
	&"persian": {
		"prefix": ["Arta", "Baga", "Dari", "Farna", "Gau", "Haxu", "Maza", "Mith", "Tiri", "Vahu", "Xsha", "Ari", "Bard", "Kuru", "Vind"],
		"suffix": ["dates", "bazu", "manes", "pata", "xshas", "arta", "daya", "varna"],
	},
	&"phoenician": {
		"prefix": ["Abd", "Ado", "Baal", "Bod", "Ger", "Han", "Mil", "Saf", "Yat", "Esh", "Mag", "Pil"],
		"suffix": ["nibal", "ashtart", "melqart", "eshmun", "at", "on", "os"],
	},
	&"egyptian": {
		"prefix": ["Amen", "Ankh", "Hori", "Imho", "Khae", "Meri", "Nefer", "Padi", "Ptah", "Sene", "Tuth", "Wah"],
		"suffix": ["hotep", "mose", "nakht", "nefer", "seni", "tep", "em"],
	},
	&"latin": {
		"prefix": ["Aul", "Gai", "Luci", "Marc", "Publi", "Quint", "Sext", "Tit", "Appiu", "Mani", "Servi", "Spuri"],
		"suffix": ["us", "ius", "anus", "inus", "ulus", "entus"],
	},
	&"punic": {
		"prefix": ["Han", "Has", "Him", "Mag", "Saf", "Bod", "Ger", "Ado"],
		"suffix": ["nibal", "drubal", "ilco", "agon", "ashtart", "baal"],
	},
	&"north_african_greek": {
		"prefix": ["Ari", "Batt", "Eury", "Kalli", "Poly", "Theo"],
		"suffix": ["stos", "kles", "genes", "machos"],
	},
}


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_world_registry = get_node("/root/WorldRegistry")
	_immortal_registry = get_node("/root/ImmortalRegistry")
	_rng_seed = hash("chargen_seed") + Time.get_ticks_msec()
	_rng.seed = _rng_seed
	_tick_sub = _event_bus.subscribe(
		preload("res://scripts/data/events/game_day_ticked_event.gd"),
		Callable(self, "_on_game_day_ticked"),
		180, &"", EndOfTickPhases.WORLD_SHARED,
	)
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"char_generation_state",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)
	_logger.info(LogChannels.CHAR_GENERATION, "CharGeneration mechanic ready")


func _on_game_day_ticked(_event: GameDayTickedEvent) -> void:
	_day_accumulator += 1
	_gc_day_accumulator += 1
	if _day_accumulator >= GENERATION_PERIOD_DAYS:
		_day_accumulator = 0
		_generate_for_all_places()
	if _gc_day_accumulator >= GC_PERIOD_DAYS:
		_gc_day_accumulator = 0
		_run_gc()


# --- Generation ---

func _generate_for_all_places() -> void:
	var day: int = _time_keeper.current_day
	var pop_node: Node = get_node_or_null("../Population")
	for place_id: StringName in _world_registry.all_place_ids():
		var rate: float = 0.0
		if pop_node != null:
			rate = pop_node.generation_rate(place_id)
		else:
			var place: PlaceRecord = _world_registry.get_place(place_id)
			if place != null and place.population > 1000:
				rate = maxf(place.population / 20000.0, 0.1)
		var count: int = int(rate)
		# Fractional part as probability
		if _rng.randf() < (rate - count):
			count += 1
		for i in range(count):
			_generate_character(place_id, day)


func _generate_character(place_id: StringName, day: int) -> CharacterRecord:
	var place: PlaceRecord = _world_registry.get_place(place_id)
	if place == null:
		return null
	var province: ProvinceRecord = _world_registry.get_province(place.province)
	var cultural_sphere: StringName = province.cultural_sphere if province != null else &"greek"
	var character := CharacterRecord.new()
	character.id = StringName("gen_%d" % _next_gen_id)
	_next_gen_id += 1
	character.name = _generate_name(cultural_sphere)
	character.birth_day = day - (_rng.randi_range(18, 45) * 365)  # born 18-45 years ago
	character.profession = _pick_profession(place)
	character.province = place.province
	character.current_place = place_id
	character.public_position_tier = PublicPositionValues.MINOR
	# Sample traits from regional distribution + condition weights
	var weights: Dictionary = {}
	var pop_node: Node = get_node_or_null("../Population")
	if pop_node != null:
		weights = pop_node.get_weight_accumulators(place_id)
	_sample_traits(character, cultural_sphere, weights)
	# Register
	_immortal_registry.register_character(character)
	_generated_ids.append(character.id)
	# Fire event
	var event := CharacterGeneratedEvent.new()
	event.character_id = character.id
	event.place_id = place_id
	event.day = day
	_event_bus.dispatch(event)
	return character


func _sample_traits(character: CharacterRecord, cultural_sphere: StringName, weights: Dictionary) -> void:
	var base: Dictionary = BASE_DISTRIBUTIONS.get(cultural_sphere, {})
	var traits: Array[StringName] = [
		&"ambition", &"paranoia", &"loyalty", &"piety", &"intellect",
		&"greed", &"ruthlessness", &"curiosity", &"resilience", &"charisma",
	]
	for trait_id: StringName in traits:
		var mean: float = base.get(trait_id, 50.0)
		var weight_shift: float = weights.get(trait_id, 0.0)
		mean += weight_shift
		mean = clampf(mean, 10.0, 90.0)
		var spread: float = 15.0
		var value: int = clampi(int(_rng.randfn(mean, spread)), 5, 95)
		match trait_id:
			&"ambition": character.ambition = value
			&"paranoia": character.paranoia = value
			&"loyalty": character.loyalty = value
			&"piety": character.piety = value
			&"intellect": character.intellect = value
			&"greed": character.greed = value
			&"ruthlessness": character.ruthlessness = value
			&"curiosity": character.curiosity = value
			&"resilience": character.resilience = value
			&"charisma": character.charisma = value


func _generate_name(cultural_sphere: StringName) -> String:
	var fragments: Dictionary = NAME_FRAGMENTS.get(cultural_sphere, NAME_FRAGMENTS[&"greek"])
	var prefixes: Array = fragments.get("prefix", ["Unknown"])
	var suffixes: Array = fragments.get("suffix", [""])
	var prefix: String = prefixes[_rng.randi() % prefixes.size()]
	var suffix: String = suffixes[_rng.randi() % suffixes.size()]
	return prefix + suffix


func _pick_profession(place: PlaceRecord) -> StringName:
	var scholarly: float = place.factional_balance.get(&"scholarly", 0.0)
	var mercantile: float = place.factional_balance.get(&"mercantile", 0.0)
	var military: float = place.factional_balance.get(&"military", 0.0)
	var religious: float = place.factional_balance.get(&"religious", 0.0)
	var roll: float = _rng.randf()
	if roll < scholarly:
		return [&"scholar", &"philosopher", &"librarian"][_rng.randi() % 3]
	elif roll < scholarly + mercantile:
		return [&"merchant", &"trader"][_rng.randi() % 2]
	elif roll < scholarly + mercantile + military:
		return [&"soldier", &"guard"][_rng.randi() % 2]
	elif roll < scholarly + mercantile + military + religious:
		return [&"priest", &"oracle"][_rng.randi() % 2]
	return [&"artisan", &"farmer", &"laborer"][_rng.randi() % 3]


# --- GC (§35.10 tiered persistence) ---

func _run_gc() -> void:
	var day: int = _time_keeper.current_day
	var collected: int = 0
	var to_remove: Array[StringName] = []
	for gen_id: StringName in _generated_ids:
		var character: CharacterRecord = _immortal_registry.get_character(gen_id)
		if character == null:
			to_remove.append(gen_id)
			continue
		if _is_relevant(character, gen_id):
			continue
		if not character.is_alive(day):
			# Dead and past retention window
			if (day - character.death_day) > GC_DEAD_RETENTION_DAYS:
				_immortal_registry.unregister_character(gen_id)
				to_remove.append(gen_id)
				collected += 1
		else:
			# Alive but irrelevant and very old
			if character.age_in_days(day) > GC_ALIVE_STALENESS_DAYS:
				_immortal_registry.unregister_character(gen_id)
				to_remove.append(gen_id)
				collected += 1
	for rid: StringName in to_remove:
		_generated_ids.erase(rid)
	if collected > 0:
		_logger.info(LogChannels.CHAR_GENERATION, "GC collected characters", {"count": collected})


func _is_relevant(character: CharacterRecord, _character_id: StringName) -> bool:
	# Tier 1: in any chain → always keep
	if character.chain_status != ChainStatusValues.NONE:
		return true
	# Tier 2: society member → always keep
	if character.society_id != &"":
		return true
	# Tier 3: a ruler → always keep
	var kingdom_node: Node = get_node_or_null("../Kingdom")
	if kingdom_node != null:
		for kid: StringName in kingdom_node.all_kingdom_ids():
			var k: KingdomRecord = kingdom_node.get_kingdom(kid)
			if k != null and k.ruler_character_id == character.id:
				return true
	# Tier 4: has heat > 0 (was investigated) → keep
	if character.heat > 0:
		return true
	# Tier 5: has trust_score != 50 (was interacted with) → keep
	if character.trust_score != 50:
		return true
	return false


# --- Public API ---

func generate_character_at(place_id: StringName, day: int = -1) -> CharacterRecord:
	if day < 0:
		day = _time_keeper.current_day
	return _generate_character(place_id, day)


func get_generated_count() -> int:
	return _generated_ids.size()


func is_generated(character_id: StringName) -> bool:
	return character_id in _generated_ids


# --- Save/load ---

func snapshot_state() -> Dictionary:
	return {
		"day_accumulator": _day_accumulator,
		"gc_day_accumulator": _gc_day_accumulator,
		"rng_seed": _rng_seed,
		"rng_state": _rng.state,
		"next_gen_id": _next_gen_id,
		"generated_ids": _generated_ids.duplicate(),
	}


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_day_accumulator = state.get("day_accumulator", 0)
	_gc_day_accumulator = state.get("gc_day_accumulator", 0)
	_rng_seed = state.get("rng_seed", _rng_seed)
	_rng.seed = _rng_seed
	_rng.state = state.get("rng_state", _rng.state)
	_next_gen_id = state.get("next_gen_id", 1)
	var ids: Array = state.get("generated_ids", [])
	_generated_ids.clear()
	for id in ids:
		_generated_ids.append(id)
	_logger.info(LogChannels.CHAR_GENERATION, "CharGeneration state applied from load")
