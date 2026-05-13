class_name CultivationAdvancedEvent
extends EventBase

@export var target_character_id: StringName = &""
@export var immortal_id: StringName = &""
@export var old_chain_status: StringName = &""
@export var new_chain_status: StringName = &""
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
