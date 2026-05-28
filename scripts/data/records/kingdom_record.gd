class_name KingdomRecord
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var ruler_character_id: StringName = &""
@export var capital_place_id: StringName = &""
@export var member_place_ids: Array[StringName] = []

# Stored policy/state (NOT derived)
@export var tax_level: int = 40                   # 0-100, ruler policy
@export var legitimacy: int = 60                  # 0-100
@export var unrest: int = 10                      # 0-100
@export var debt_by_creditor: Dictionary = {}     # creditor_id -> int owed
@export var standing_army: int = 100              # placeholder until Military (11.20)

# Faction balance (which faction dominates policy)
@export var faction_military: int = 25
@export var faction_clergy: int = 25
@export var faction_merchants: int = 25
@export var faction_nobility: int = 25

# Cached condition band (updated per-day from derived treasury value)
@export var treasury_condition: StringName = &"stable"  # flush/stable/strained/indebted/broke

# Era modifiers (placeholder)
@export var era_tax_efficiency_modifier: float = 1.0

# Rivalry tensions toward other kingdoms
@export var rivalry_tensions: Dictionary = {}     # other_kingdom_id -> int (0-100)


func dominant_faction() -> StringName:
	var m: Dictionary = {
		&"military": faction_military,
		&"clergy": faction_clergy,
		&"merchants": faction_merchants,
		&"nobility": faction_nobility,
	}
	var best: StringName = &"military"
	var best_v: int = -1
	for k: StringName in m:
		if m[k] > best_v:
			best_v = m[k]
			best = k
	return best


func total_debt() -> int:
	var total: int = 0
	for amount: int in debt_by_creditor.values():
		total += amount
	return total
