class_name CoverageAssignment
extends Resource

@export var immortal_id: StringName = &""
@export var province_id: StringName = &""
@export var coverage_level: int = 0
@export var bandwidth_cost: int = 0


func effective_detection_multiplier() -> float:
	return clampf(coverage_level / 100.0, 0.0, 1.0)
