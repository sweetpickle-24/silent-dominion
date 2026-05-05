class_name SchemeDispatchedEvent
extends EventBase

@export var scheme_id: StringName = &""
@export var immortal_id: StringName = &""
@export var action_type: StringName = &""
@export var target_ref: StringName = &""
@export var target_place_ref: StringName = &""

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
