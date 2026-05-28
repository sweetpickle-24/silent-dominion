class_name LanguageRecord
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var origin_region_id: StringName = &""
@export var era_of_emergence: StringName = &"ancient"
@export var parent_language_id: StringName = &""

@export var prestige: int = 40         # 0-100
@export var lingua_franca_scope: int = 0  # 0-100
@export var liturgical_use: int = 0    # 0-100
@export var writing_system_id: StringName = &""

@export var vitality: StringName = &"stable"  # emerging/growing/stable/declining/dead


func is_alive() -> bool:
	return vitality != &"dead"
