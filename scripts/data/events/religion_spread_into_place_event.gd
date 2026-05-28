class_name ReligionSpreadIntoPlaceEvent
extends EventBase

@export var religion_id: StringName = &""
@export var place_id: StringName = &""
@export var follower_count: int = 0
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
