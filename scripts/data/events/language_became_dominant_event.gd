class_name LanguageBecameDominantEvent
extends EventBase

@export var language_id: StringName = &""
@export var region_id: StringName = &""
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
