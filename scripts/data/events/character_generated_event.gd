class_name CharacterGeneratedEvent
extends EventBase

@export var character_id: StringName = &""
@export var place_id: StringName = &""
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
