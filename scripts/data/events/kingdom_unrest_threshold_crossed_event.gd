class_name KingdomUnrestThresholdCrossedEvent
extends EventBase

@export var kingdom_id: StringName = &""
@export var old_unrest: int = 0
@export var new_unrest: int = 0
@export var threshold: int = 0  # the threshold that was crossed (e.g. 50, 70)
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
