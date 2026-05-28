class_name LinguaFrancaShiftedEvent
extends EventBase

@export var old_language_id: StringName = &""
@export var new_language_id: StringName = &""
@export var route_id: StringName = &""
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
