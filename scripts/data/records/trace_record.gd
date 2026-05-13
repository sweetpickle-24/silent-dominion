class_name TraceRecord
extends Resource

@export var id: StringName = &""
@export var emitting_immortal_id: StringName = &""
@export var emitting_society_id: StringName = &""
@export var emitting_operative_id: StringName = &""
@export var target_place_id: StringName = &""
@export var target_province_id: StringName = &""
@export var emission_strength: float = 1.0
@export var action_type: StringName = &""
@export var action_tier: int = 1
@export var emitted_at_day: int = 0
@export var expires_at_day: int = 0


func current_strength_at(query_day: int) -> float:
	var age: int = query_day - emitted_at_day
	if age < 0:
		return 0.0
	if age < 365:
		return emission_strength
	if age < 730:
		return emission_strength * 0.5
	return 0.0
