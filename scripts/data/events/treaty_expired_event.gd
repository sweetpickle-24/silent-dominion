class_name TreatyExpiredEvent
extends EventBase

@export var treaty_id: StringName = &""
@export var signatory_a_immortal_id: StringName = &""
@export var signatory_b_immortal_id: StringName = &""
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
