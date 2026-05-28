class_name TreatyRecord
extends Resource

@export var id: StringName = &""
@export var proposal_id: StringName = &""
@export var signatory_a_immortal_id: StringName = &""  # alphabetical-first
@export var signatory_b_immortal_id: StringName = &""  # alphabetical-second
@export var signatory_a_society_id: StringName = &""
@export var signatory_b_society_id: StringName = &""

@export var primitives: Array[TreatyPrimitive] = []

@export var signed_at_day: int = 0
@export var expires_at_day: int = -1  # -1 if perpetual

# Active state
@export var violations: Array = []       # array of {day, violator_immortal_id, primitive_id, evidence}
@export var renegotiations: Array = []   # array of {day, changed_primitives}

# Reputation contribution
@export var reputation_contribution_a: int = 0
@export var reputation_contribution_b: int = 0

# Status
@export var status: StringName = &"active"  # &"active" | &"violated_terminated" | &"expired" | &"mutually_terminated"
