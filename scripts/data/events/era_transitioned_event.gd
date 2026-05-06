class_name EraTransitionedEvent
extends EventBase

@export var old_era: StringName = &""
@export var new_era: StringName = &""
@export var transition_day: int = 0
@export var description: String = ""

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
