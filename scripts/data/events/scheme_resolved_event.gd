class_name SchemeResolvedEvent
extends EventBase

@export var scheme_id: StringName = &""
@export var immortal_id: StringName = &""
@export var action_type: StringName = &""
@export var target_ref: StringName = &""
@export var target_place_ref: StringName = &""
@export var outcome: StringName = &""
@export var resolved_at_day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
