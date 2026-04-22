class_name Kingdom
extends Resource
## A political entity that owns provinces and keeps a treasury.
##
## `treasury_condition` is a qualitative label kept alongside the raw
## silver/gold figures so downstream UI can say "Strained" without every
## subsystem reimplementing a threshold table.

enum TreasuryCondition {
	FLUSH,
	STABLE,
	STRAINED,
	INDEBTED,
	BROKE,
}

## How hard the crown squeezes its provinces. Drives the crown's cut of
## provincial output (income) and a small unrest pressure (not modelled
## yet but reserved here for §32.6). Rulers shift this between bands as
## their condition degrades; the player can only observe the band.
enum TaxLevel {
	INDULGENT,   # barely collected; popular, hollow treasury
	MODEST,      # traditional; the default
	BURDENED,    # squeezing; revenue up, patience down
	RUINOUS,     # emergency levies; can only last a season
}

@export var id: String = ""
@export var kingdom_name: String = ""
@export var owned_provinces: Array[String] = []
@export var treasury_silver: float = 0.0
@export var treasury_gold: float = 0.0
@export var treasury_condition: TreasuryCondition = TreasuryCondition.STABLE
@export var tax_level: TaxLevel = TaxLevel.MODEST

## True while the crown sits empty after a failed succession. The
## council governs in its own name; the province yields are skimmed
## harder by local magnates. Cleared when a new ruler is installed.
@export var in_regency: bool = false


static func from_dict(d: Dictionary) -> Kingdom:
	var k: Kingdom = Kingdom.new()
	k.id = String(d.get("id", ""))
	k.kingdom_name = String(d.get("kingdom_name", ""))

	# JSON arrays come back as untyped Array; copy into a typed one.
	k.owned_provinces = []
	for pid in d.get("owned_provinces", []):
		k.owned_provinces.append(String(pid))

	k.treasury_silver = float(d.get("treasury_silver", 0.0))
	k.treasury_gold   = float(d.get("treasury_gold", 0.0))
	k.treasury_condition = _condition_from_string(
		String(d.get("treasury_condition", "STABLE"))
	)
	k.tax_level = _tax_from_string(String(d.get("tax_level", "MODEST")))
	return k


static func _condition_from_string(s: String) -> TreasuryCondition:
	match s.to_upper():
		"FLUSH":    return TreasuryCondition.FLUSH
		"STABLE":   return TreasuryCondition.STABLE
		"STRAINED": return TreasuryCondition.STRAINED
		"INDEBTED": return TreasuryCondition.INDEBTED
		"BROKE":    return TreasuryCondition.BROKE
		_:          return TreasuryCondition.STABLE


static func _tax_from_string(s: String) -> TaxLevel:
	match s.to_upper():
		"INDULGENT": return TaxLevel.INDULGENT
		"MODEST":    return TaxLevel.MODEST
		"BURDENED":  return TaxLevel.BURDENED
		"RUINOUS":   return TaxLevel.RUINOUS
		_:           return TaxLevel.MODEST


func treasury_condition_name() -> String:
	return TreasuryCondition.keys()[treasury_condition]


func tax_level_name() -> String:
	return TaxLevel.keys()[tax_level]


## Short qualitative phrase the player sees in the Map detail panel
## and Ledger. Never exposes the raw multiplier.
func tax_level_phrase() -> String:
	match tax_level:
		TaxLevel.INDULGENT: return "a light hand at the tax bench"
		TaxLevel.MODEST:    return "the traditional tithe, no more"
		TaxLevel.BURDENED:  return "taxes that leave the plate thin"
		TaxLevel.RUINOUS:   return "extraordinary levies, openly resented"
		_:                  return ""
