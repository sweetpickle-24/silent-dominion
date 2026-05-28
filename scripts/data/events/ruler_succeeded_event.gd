class_name RulerSucceededEvent
extends EventBase

@export var kingdom_id: StringName = &""
@export var old_ruler_id: StringName = &""
@export var new_ruler_id: StringName = &""
@export var succession_type: StringName = &""  # &"heir" | &"generated" | &"faction"
@export var legitimacy_hit: int = 0
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
