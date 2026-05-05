class_name SchemeRecord
extends Resource

@export var id: StringName
@export var immortal_id: StringName = &""

@export var action_type: StringName = &""
@export var target_ref: StringName = &""
@export var target_place_ref: StringName = &""

@export var current_phase: StringName = SchemePhases.DRAFTED
@export var dispatched_at_day: int = 0
@export var current_phase_entered_at_day: int = 0
@export var phase_history: Array[Dictionary] = []

@export var outcome: StringName = &""
@export var resolved_at_day: int = -1
