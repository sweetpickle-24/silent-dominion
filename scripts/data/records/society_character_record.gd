class_name SocietyCharacterRecord
extends Resource

@export var society_id: StringName = &""
@export var display_name: String = ""

@export var disposition_baseline: int = 0

# Character properties from inter-society-mechanics.md "Per-society character."
# Authored on the Veil at Step 8 but no consumer reads them yet.
@export var value_weights: Dictionary = {}
@export var capability_profile: Dictionary = {}
@export var forbidden_moves: Array[StringName] = []

@export var disposition_modifier_rules: Array[Rule] = []

# AI rule list (T1-3) — deferred to a later step.
@export var ai_rules: Array[Rule] = []
