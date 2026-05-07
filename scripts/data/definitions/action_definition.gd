class_name ActionDefinition
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var tier: int = 1

# Cost dimensions per action-palette.md §3.5 — calibration values, T2-1 revises.
@export var baseline_exposure_cost: float = 1.0
@export var baseline_bandwidth_cost: int = 1
@export var baseline_financial_cost: int = 0
@export var baseline_time_days: int = 30

# Capabilities required of the executing Operative.
@export var required_capabilities: Array[StringName] = []

# Phase-specific timing overrides. Values override Chain default for that phase.
# -1 or absent means Chain uses its own default for that phase.
@export var phase_timing_overrides: Dictionary = {}
