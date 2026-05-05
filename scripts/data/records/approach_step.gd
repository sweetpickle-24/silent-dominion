class_name ApproachStep
extends Resource

@export var sequence_index: int = 0
@export var action_type: StringName = &""
@export var action_parameters: Dictionary = {}
@export var indirection_level: int = 1
@export var discretion_level: int = 1
@export var target_resolution: StringName = TargetResolutionValues.USE_PATTERN_TARGET
@export var optional: bool = false
@export_multiline var skip_condition: String = ""
@export var min_day_delay: int = 0
@export var max_day_delay: int = 0
