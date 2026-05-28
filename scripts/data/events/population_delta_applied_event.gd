class_name PopulationDeltaAppliedEvent
extends EventBase

@export var place_id: StringName = &""
@export var old_population: int = 0
@export var new_population: int = 0
@export var delta: int = 0
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
