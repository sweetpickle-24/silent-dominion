class_name KingdomTaxLevelChangedEvent
extends EventBase

@export var kingdom_id: StringName = &""
@export var old_level: int = 0
@export var new_level: int = 0
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
