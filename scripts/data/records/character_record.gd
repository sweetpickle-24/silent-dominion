class_name CharacterRecord
extends Resource

# Identity
@export var id: StringName
@export var name: String

# Demographics
@export var birth_day: int = 0
@export var death_day: int = -1
@export var profession: StringName = &""
@export var region: StringName = &""
@export var current_place: StringName = &""

# Public position
@export var public_position: String = ""
@export var public_position_tier: StringName = PublicPositionValues.MINOR
@export var max_concurrent_assignments: int = 3

# Chain status
@export var chain_status: StringName = ChainStatusValues.NONE

# Languages (placeholder; full Languages mechanic at 11.14)
@export var languages: Array[StringName] = []

# Trait scores (0-100 per §24; 50 is neutral)
@export var ambition: int = 50
@export var paranoia: int = 50
@export var loyalty: int = 50
@export var piety: int = 50
@export var intellect: int = 50
@export var greed: int = 50
@export var ruthlessness: int = 50
@export var curiosity: int = 50
@export var resilience: int = 50
@export var charisma: int = 50

# Operational state
@export var heat: int = 0
@export var trust_score: int = 50


func is_alive(current_day: int) -> bool:
	return death_day < 0 or current_day < death_day


func age_in_days(current_day: int) -> int:
	return current_day - birth_day


func get_trait(trait_id: StringName) -> int:
	match trait_id:
		TraitValues.AMBITION: return ambition
		TraitValues.PARANOIA: return paranoia
		TraitValues.LOYALTY: return loyalty
		TraitValues.PIETY: return piety
		TraitValues.INTELLECT: return intellect
		TraitValues.GREED: return greed
		TraitValues.RUTHLESSNESS: return ruthlessness
		TraitValues.CURIOSITY: return curiosity
		TraitValues.RESILIENCE: return resilience
		TraitValues.CHARISMA: return charisma
		_:
			push_error("Unknown trait_id: %s" % trait_id)
			return 50
