class_name CharacterDiedEvent
extends EventBase

@export var character_id: StringName = &""
@export var character_name: String = ""
@export var place_id: StringName = &""
@export var cause: StringName = &"old_age"  # &"old_age" | &"plague" | &"famine" | &"war"
@export var was_ruler: bool = false
@export var kingdom_id: StringName = &""
@export var was_chain_member: bool = false
@export var chain_status: StringName = &""
@export var society_id: StringName = &""
@export var day: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
