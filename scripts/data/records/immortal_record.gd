class_name ImmortalRecord
extends Resource

@export var id: StringName
@export var origin_day: int = 0
@export var canonical_name: String = ""

@export var character: CharacterRecord

@export var current_cover_identity: StringName = &""
@export var accumulated_legend: int = 0
@export var society_id: StringName = &""


func is_player() -> bool:
	return id == &"player"
