class_name TreatyTerminatedEvent
extends EventBase

@export var treaty_id: StringName = &""
@export var terminator_immortal_id: StringName = &""
@export var reason: String = ""
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
