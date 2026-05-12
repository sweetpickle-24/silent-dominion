class_name ProvinceRecord
extends Resource

@export var id: StringName
@export var name: String
@export var cultural_sphere: StringName = &""

@export var terrain: StringName = &"plains"
@export var climate: StringName = &"mediterranean"

@export var owning_kingdom: StringName = &""

@export var center_lat: float = 0.0
@export var center_lon: float = 0.0
@export var render_radius_km: float = 200.0

@export var neighbors: Array[StringName] = []


func is_adjacent_to(other_province_id: StringName) -> bool:
	return other_province_id in neighbors


func shares_cultural_sphere_with(other_province: ProvinceRecord) -> bool:
	if other_province == null:
		return false
	return cultural_sphere == other_province.cultural_sphere
