class_name SchemeCancelledEvent
extends EventBase

@export var scheme_id: StringName = &""
@export var immortal_id: StringName = &""
@export var reason: StringName = &""
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
