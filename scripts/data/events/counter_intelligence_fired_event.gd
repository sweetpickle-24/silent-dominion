class_name CounterIntelligenceFiredEvent
extends EventBase

@export var operation_kind: StringName = &""  # &"rotate" | &"obscure_traces" | &"plant_false_fingerprint" | &"archive_query"
@export var acting_immortal_id: StringName = &""
@export var target_place_id: StringName = &""
@export var target_character_id: StringName = &""
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
