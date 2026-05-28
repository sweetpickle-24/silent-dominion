class_name TreatyViolationDetectedEvent
extends EventBase

@export var treaty_id: StringName = &""
@export var violator_immortal_id: StringName = &""
@export var violated_primitive_id: StringName = &""
@export var action_type: StringName = &""
@export var target_ref: StringName = &""
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
