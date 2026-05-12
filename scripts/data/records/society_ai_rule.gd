class_name SocietyAIRule
extends Resource

@export var id: StringName
@export var society_id: StringName = &""
@export var priority: int = 100

@export var rule_tier: StringName = &"operational"
@export var description: String = ""

@export_multiline var condition: String = ""

@export var action_kind: StringName = &"dispatch_scheme"
@export var action_params: Dictionary = {}

@export var last_fired_at_day: int = -1
@export var times_fired: int = 0
@export var cooldown_days: int = 30
