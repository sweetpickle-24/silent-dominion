class_name SchemePhaseAdvancedEvent
extends EventBase

@export var scheme_id: StringName = &""
@export var immortal_id: StringName = &""
@export var old_phase: StringName = &""
@export var new_phase: StringName = &""
@export var days_in_old_phase: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
