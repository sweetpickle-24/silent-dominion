class_name TreatyCounterProposedEvent
extends EventBase

@export var proposal_id: StringName = &""
@export var counter_proposer_immortal_id: StringName = &""
@export var original_proposer_immortal_id: StringName = &""
@export var round_number: int = 0
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
