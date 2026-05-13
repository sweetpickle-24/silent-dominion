class_name TraceEmittedEvent
extends EventBase

@export var trace_id: StringName = &""
@export var emitting_immortal_id: StringName = &""
@export var emitting_society_id: StringName = &""
@export var target_place_id: StringName = &""
@export var emission_strength: float = 0.0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
