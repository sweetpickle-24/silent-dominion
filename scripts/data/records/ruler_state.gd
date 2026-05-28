class_name RulerState
extends Resource

@export var ruler_character_id: StringName = &""
@export var kingdom_id: StringName = &""

# Standing goals (weighted)
@export var goal_weights: Dictionary = {}  # &"maintain_power" -> int, &"secure_succession" -> int, etc.

# Advisor influence
@export var advisor_influence: Dictionary = {}  # advisor_character_id -> influence_weight (0-100)

# Recent decisions (last N)
@export var recent_decisions: Array = []  # [{decision, day, outcome}]
const MAX_RECENT_DECISIONS: int = 20

# Confidence modifier from recent history
@export var confidence_modifier: int = 0  # -20..+20

# Fidelity
@export var fidelity: StringName = &"low"  # &"full" | &"low"

# Per-rule memory (reuses SocietyAI memory pattern via RuleListRunner)
@export var rule_memory: Dictionary = {}


func record_decision(decision: StringName, day: int, outcome: StringName = &"pending") -> void:
	recent_decisions.append({"decision": decision, "day": day, "outcome": outcome})
	if recent_decisions.size() > MAX_RECENT_DECISIONS:
		recent_decisions.pop_front()
	# Update confidence based on outcome
	if outcome == &"success":
		confidence_modifier = mini(confidence_modifier + 3, 20)
	elif outcome == &"failure":
		confidence_modifier = maxi(confidence_modifier - 5, -20)
