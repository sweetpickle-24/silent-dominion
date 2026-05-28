class_name FalseFingerprintPlantedEvent
extends EventBase

@export var planting_immortal_id: StringName = &""
@export var framed_society_id: StringName = &""
@export var target_place_id: StringName = &""
@export var quality: StringName = &"moderate"  # fixed at "moderate" for 11.10; full quality tiers at 11.13.5
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
