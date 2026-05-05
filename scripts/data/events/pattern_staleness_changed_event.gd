class_name PatternStalenessChangedEvent
extends EventBase

@export var pattern_id: StringName = &""
@export var immortal_id: StringName = &""
@export var old_state: StringName = &""
@export var new_state: StringName = &""

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
