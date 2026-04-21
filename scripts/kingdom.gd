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

@export var id: String = ""
@export var kingdom_name: String = ""
@export var owned_provinces: Array[String] = []
@export var treasury_silver: float = 0.0
@export var treasury_gold: float = 0.0
@export var treasury_condition: TreasuryCondition = TreasuryCondition.STABLE


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
	return k


static func _condition_from_string(s: String) -> TreasuryCondition:
	match s.to_upper():
		"FLUSH":    return TreasuryCondition.FLUSH
		"STABLE":   return TreasuryCondition.STABLE
		"STRAINED": return TreasuryCondition.STRAINED
		"INDEBTED": return TreasuryCondition.INDEBTED
		"BROKE":    return TreasuryCondition.BROKE
		_:          return TreasuryCondition.STABLE


func treasury_condition_name() -> String:
	return TreasuryCondition.keys()[treasury_condition]
