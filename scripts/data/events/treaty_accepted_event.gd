class_name TreatyAcceptedEvent
extends EventBase

@export var proposal_id: StringName = &""
@export var treaty_id: StringName = &""
@export var acceptor_immortal_id: StringName = &""
@export var proposer_immortal_id: StringName = &""
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
