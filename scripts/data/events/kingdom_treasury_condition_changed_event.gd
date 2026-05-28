class_name KingdomTreasuryConditionChangedEvent
extends EventBase

@export var kingdom_id: StringName = &""
@export var old_condition: StringName = &""
@export var new_condition: StringName = &""
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
