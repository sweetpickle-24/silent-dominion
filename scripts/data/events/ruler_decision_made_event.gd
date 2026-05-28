class_name RulerDecisionMadeEvent
extends EventBase

@export var kingdom_id: StringName = &""
@export var ruler_character_id: StringName = &""
@export var decision: StringName = &""
@export var params: Dictionary = {}
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
