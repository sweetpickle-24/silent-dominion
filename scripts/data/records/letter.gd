class_name Letter
extends Resource

@export var id: StringName = &""
@export var immortal_id: StringName = &""

@export var sender_ref: StringName = &""
@export var sender_kind: StringName = &"system"

@export var subject: String = ""
@export var body: String = ""
@export var content_category: StringName = &""

@export var day_received: int = 0
@export var action_ref: StringName = &""
@export var triggering_event_class: StringName = &""

@export var is_read: bool = false
@export var tier: StringName = &"active"
@export var read_day: int = -1


func mark_read(day: int) -> void:
	is_read = true
	read_day = day
