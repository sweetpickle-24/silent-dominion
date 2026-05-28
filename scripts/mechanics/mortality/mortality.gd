class_name Mortality
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _immortal_registry: Node

var _tick_sub
var _day_accumulator: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _rng_seed: int = 0

# Evaluation cadence: check mortality every N days
const EVAL_PERIOD_DAYS: int = 30

# Era lifespan curve: annual death probability by age bracket (placeholder, flagged for calibration)
# Ancient era: life expectancy ~35 overall, but those surviving childhood can reach 60-70
const AGE_BRACKETS: Array = [
	{"min_age_years": 0, "max_age_years": 5, "annual_death_prob": 0.15},
	{"min_age_years": 5, "max_age_years": 15, "annual_death_prob": 0.02},
	{"min_age_years": 15, "max_age_years": 40, "annual_death_prob": 0.01},
	{"min_age_years": 40, "max_age_years": 55, "annual_death_prob": 0.03},
	{"min_age_years": 55, "max_age_years": 65, "annual_death_prob": 0.06},
	{"min_age_years": 65, "max_age_years": 75, "annual_death_prob": 0.12},
	{"min_age_years": 75, "max_age_years": 999, "annual_death_prob": 0.25},
]


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_immortal_registry = get_node("/root/ImmortalRegistry")
	_rng_seed = hash("mortality_seed") + Time.get_ticks_msec()
	_rng.seed = _rng_seed
	_tick_sub = _event_bus.subscribe(
		preload("res://scripts/data/events/game_day_ticked_event.gd"),
		Callable(self, "_on_game_day_ticked"),
		170, &"", EndOfTickPhases.WORLD_SHARED,
	)
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"mortality_state",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)
	_logger.info(LogChannels.MORTALITY, "Mortality mechanic ready")


func _on_game_day_ticked(_event: GameDayTickedEvent) -> void:
	_day_accumulator += 1
	if _day_accumulator >= EVAL_PERIOD_DAYS:
		_day_accumulator = 0
		_evaluate_mortality()


func _evaluate_mortality() -> void:
	var day: int = _time_keeper.current_day
	var all_ids: Array = _immortal_registry.all_character_ids()
	for char_id: StringName in all_ids:
		var character: CharacterRecord = _immortal_registry.get_character(char_id)
		if character == null:
			continue
		if not character.is_alive(day):
			continue
		# Immortals never die of old age
		if _immortal_registry.is_immortal(char_id):
			continue
		var age_years: float = character.age_in_days(day) / 365.0
		var death_prob: float = _compute_death_probability(age_years, character)
		# Adjust for shock (plague/war/famine) at character's location
		var shock: float = _get_local_shock(character.current_place)
		if shock < 1.0:
			death_prob *= (2.0 - shock)
		# Scale probability for the evaluation period (30 days ≈ 1/12 year)
		var period_prob: float = death_prob * (float(EVAL_PERIOD_DAYS) / 365.0)
		var roll: float = _rng.randf()
		if roll < period_prob:
			_kill_character(character, day)


func _compute_death_probability(age_years: float, character: CharacterRecord) -> float:
	var base_prob: float = 0.01
	for bracket: Dictionary in AGE_BRACKETS:
		if age_years >= bracket["min_age_years"] and age_years < bracket["max_age_years"]:
			base_prob = bracket["annual_death_prob"]
			break
	# Trait modifiers: resilience reduces death probability
	var resilience_mod: float = 1.0 - (character.resilience - 50) * 0.005
	base_prob *= clampf(resilience_mod, 0.5, 1.5)
	return base_prob


func _get_local_shock(place_id: StringName) -> float:
	var pop_node: Node = get_node_or_null("../Population")
	if pop_node != null:
		var state: PopulationState = pop_node.get_state(place_id)
		if state != null:
			return state.shock_factor
	return 1.0


func _kill_character(character: CharacterRecord, day: int) -> void:
	_immortal_registry.set_character_death_day(character.id, day)
	var was_ruler: bool = false
	var kingdom_id: StringName = &""
	var kingdom_node: Node = get_node_or_null("../Kingdom")
	if kingdom_node != null:
		for kid: StringName in kingdom_node.all_kingdom_ids():
			var k: KingdomRecord = kingdom_node.get_kingdom(kid)
			if k != null and k.ruler_character_id == character.id:
				was_ruler = true
				kingdom_id = kid
				break
	var was_chain: bool = character.chain_status != ChainStatusValues.NONE
	var event := CharacterDiedEvent.new()
	event.character_id = character.id
	event.character_name = character.name
	event.place_id = character.current_place
	event.cause = &"old_age"
	event.was_ruler = was_ruler
	event.kingdom_id = kingdom_id
	event.was_chain_member = was_chain
	event.chain_status = character.chain_status
	event.society_id = character.society_id
	event.day = day
	_event_bus.dispatch(event)
	_logger.info(LogChannels.MORTALITY, "Character died", {
		"id": character.id, "age": character.age_in_days(day) / 365.0,
		"was_ruler": was_ruler, "was_chain": was_chain,
	})


# --- Public API ---

func compute_death_probability_for(character_id: StringName, day: int) -> float:
	var character: CharacterRecord = _immortal_registry.get_character_record_any(character_id)
	if character == null:
		return 0.0
	var age_years: float = character.age_in_days(day) / 365.0
	return _compute_death_probability(age_years, character)


func kill_character_by_cause(character_id: StringName, cause: StringName, day: int) -> void:
	var character: CharacterRecord = _immortal_registry.get_character_record_any(character_id)
	if character == null:
		return
	if _immortal_registry.is_immortal(character_id):
		return  # immortals exempt
	_immortal_registry.set_character_death_day(character_id, day)
	var was_chain: bool = character.chain_status != ChainStatusValues.NONE
	var was_ruler: bool = false
	var kingdom_id: StringName = &""
	var kingdom_node: Node = get_node_or_null("../Kingdom")
	if kingdom_node != null:
		for kid: StringName in kingdom_node.all_kingdom_ids():
			var k: KingdomRecord = kingdom_node.get_kingdom(kid)
			if k != null and k.ruler_character_id == character_id:
				was_ruler = true
				kingdom_id = kid
				break
	var event := CharacterDiedEvent.new()
	event.character_id = character_id
	event.character_name = character.name
	event.place_id = character.current_place
	event.cause = cause
	event.was_ruler = was_ruler
	event.kingdom_id = kingdom_id
	event.was_chain_member = was_chain
	event.chain_status = character.chain_status
	event.society_id = character.society_id
	event.day = day
	_event_bus.dispatch(event)


# --- Save/load ---

func snapshot_state() -> Dictionary:
	return {
		"day_accumulator": _day_accumulator,
		"rng_seed": _rng_seed,
		"rng_state": _rng.state,
	}


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_day_accumulator = state.get("day_accumulator", 0)
	_rng_seed = state.get("rng_seed", _rng_seed)
	_rng.seed = _rng_seed
	_rng.state = state.get("rng_state", _rng.state)
	_logger.info(LogChannels.MORTALITY, "Mortality state applied from load")
