class_name FamineOnsetEvent
extends EventBase

@export var place_id: StringName = &""
@export var severity: float = 1.0  # 0.0-1.0, higher = worse
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
