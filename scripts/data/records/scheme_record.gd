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

# Chain assignments — populated as scheme advances.
@export var assigned_lieutenant_id: StringName = &""
@export var assigned_coordinator_id: StringName = &""
@export var assigned_operative_id: StringName = &""

# Cost computed at dispatch from ActionDefinition x public_position
@export var exposure_cost_total: float = 0.0
@export var financial_cost_total: int = 0

# Resolution
@export var outcome: StringName = &""
@export var resolved_at_day: int = -1
@export var cancellation_reason: StringName = &""

# Mutual cultivation conflict: true if target belongs to another society
@export var is_recruit_attempt: bool = false
