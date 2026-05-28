class_name ReligionSchismOccurredEvent
extends EventBase

@export var parent_religion_id: StringName = &""
@export var child_religion_id: StringName = &""
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
