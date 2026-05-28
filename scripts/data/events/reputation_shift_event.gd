class_name ReputationShiftEvent
extends EventBase

@export var immortal_id: StringName = &""
@export var delta: int = 0
@export var new_score: int = 50
@export var reason: String = ""
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
