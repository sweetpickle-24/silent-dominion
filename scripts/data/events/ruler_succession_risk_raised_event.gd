class_name RulerSuccessionRiskRaisedEvent
extends EventBase

@export var kingdom_id: StringName = &""
@export var ruler_character_id: StringName = &""
@export var ruler_age_days: int = 0
@export var risk_level: StringName = &""  # &"low" | &"moderate" | &"high" | &"critical"
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
