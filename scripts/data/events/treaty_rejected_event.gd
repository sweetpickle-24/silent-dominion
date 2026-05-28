class_name TreatyRejectedEvent
extends EventBase

@export var proposal_id: StringName = &""
@export var rejector_immortal_id: StringName = &""
@export var proposer_immortal_id: StringName = &""
@export var reason: String = ""
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
