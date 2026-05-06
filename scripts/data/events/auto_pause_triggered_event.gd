class_name AutoPauseTriggeredEvent
extends EventBase

@export var trigger_category: StringName = &""
@export var trigger_source_event_id: StringName = &""
@export var urgency: StringName = &"normal"

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
