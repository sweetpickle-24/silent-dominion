class_name FirstContactEvent
extends EventBase

@export var detecting_immortal_id: StringName = &""
@export var detected_society_id: StringName = &""
@export var detected_immortal_id: StringName = &""
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
