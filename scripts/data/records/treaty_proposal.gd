class_name TreatyProposal
extends Resource

@export var id: StringName = &""
@export var proposer_immortal_id: StringName = &""
@export var counterparty_immortal_id: StringName = &""
@export var counterparty_society_id: StringName = &""

# Primitives that make up this proposal
@export var primitives: Array[TreatyPrimitive] = []

# Lifecycle state
@export var stage: StringName = &"drafting"  # &"drafting" | &"negotiation" | &"signed" | &"active" | &"renegotiation" | &"expired" | &"violated" | &"terminated"
@export var drafted_at_day: int = 0
@export var current_round: int = 1
@export var max_rounds: int = 5

# History: array of {round, action, day, by, primitives_snapshot}
@export var history: Array = []

# Outcome
@export var signed_at_day: int = -1
@export var expires_at_day: int = -1
@export var terminated_at_day: int = -1
@export var termination_reason: String = ""
