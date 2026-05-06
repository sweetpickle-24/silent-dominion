class_name DispositionRuleFiredEvent
extends EventBase

@export var rule_id: StringName = &""
@export var source_society_id: StringName = &""
@export var target_immortal_id: StringName = &""
@export var base_delta: int = 0
@export var scaled_delta: int = 0
@export var attribution_tag: StringName = &""
@export var triggering_event_id: StringName = &""

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
