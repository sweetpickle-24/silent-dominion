class_name PopulationState
extends Resource

@export var place_id: StringName = &""
@export var total: int = 0
@export var avg_age: float = 28.0
@export var birth_rate_per_1000: float = 38.0
@export var death_rate_per_1000: float = 34.0
@export var net_migration_last_period: int = 0

# Condition inputs (read from place/kingdom each period)
@export var food_surplus_factor: float = 1.0
@export var prosperity_factor: float = 1.0
@export var stability_factor: float = 1.0
@export var shock_factor: float = 1.0  # <1 during plague/famine/war

# Weight accumulators (condition history shaping next generation's traits)
@export var weight_accumulators: Dictionary = {}  # trait_id -> float delta

# City-slot readiness flag (consumed by 11.16 districts)
@export var city_slot_ready: bool = false
const CITY_SLOT_POPULATION_THRESHOLD: int = 50000


func period_delta() -> int:
	# Births scale with food surplus and prosperity
	var births: float = total * birth_rate_per_1000 / 1000.0 * food_surplus_factor * prosperity_factor
	# Deaths increase with scarcity (low food_surplus), instability, and shocks
	var death_modifier: float = (2.0 - food_surplus_factor) * (2.0 - stability_factor) / maxf(shock_factor, 0.05)
	var deaths: float = total * death_rate_per_1000 / 1000.0 * death_modifier
	var natural: float = births - deaths
	return int(natural) + net_migration_last_period
