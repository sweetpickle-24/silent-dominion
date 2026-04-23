class_name City
extends Resource
## §D2 A city contained in a province.
##
## Most provinces have a single notional settlement absorbed into the
## province-level abstraction. A handful — Athens, Sparta, Rome,
## Persepolis — are large enough that the player needs to see below
## the province to track what is happening in which quarter. Those
## are modelled as a `City` resource hung off `Province.city`.
##
## Districts are minimal: a kind (palace/temple/market/docks/workshops),
## a per-district `fog` scalar, and a short list of resident actor ids
## that a coordinator placed in the city can uncover one at a time.
##
## Fog mechanics (§D2):
##   - Initial fog per district is 100 ("we have heard the name, nothing more").
##   - A non-burned coordinator in the kingdom that holds this city
##     halves the fog on each tick (up to a floor of 10) until all
##     districts are clear.
##   - No player-action is required beyond having coverage; the city
##     is a reward for running an org, not a target you pay to unlock.

enum DistrictKind {
	PALACE,
	TEMPLE,
	MARKET,
	DOCKS,
	WORKSHOPS,
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var districts: Array = []


static func make(id_: StringName, name_: String, district_kinds: Array[int]) -> City:
	var c: City = City.new()
	c.id = id_
	c.display_name = name_
	for k in district_kinds:
		c.districts.append({
			"kind":                int(k),
			"fog":                 100,
			"resident_actor_ids":  [],
		})
	return c


func district_kind_name(k: int) -> String:
	match k:
		DistrictKind.PALACE:    return "palace"
		DistrictKind.TEMPLE:    return "temple"
		DistrictKind.MARKET:    return "market"
		DistrictKind.DOCKS:     return "docks"
		DistrictKind.WORKSHOPS: return "workshops"
	return "quarter"


## Reduce fog on every district by `amount`, floored at `floor_value`.
## Returns true if any district's fog actually moved (UI can render a
## subtle highlight on the districts whose fog lifted).
func lift_fog(amount: int, floor_value: int = 10) -> bool:
	var changed: bool = false
	for d in districts:
		var prev: int = int(d.get("fog", 100))
		var next_v: int = maxi(floor_value, prev - amount)
		if next_v != prev:
			d["fog"] = next_v
			changed = true
	return changed


func to_dict() -> Dictionary:
	var dl: Array = []
	for d in districts:
		dl.append(d.duplicate(true))
	return {
		"id":           String(id),
		"display_name": display_name,
		"districts":    dl,
	}


static func from_dict(d: Dictionary) -> City:
	var c: City = City.new()
	c.id = StringName(String(d.get("id", "")))
	c.display_name = String(d.get("display_name", ""))
	var dl: Variant = d.get("districts", [])
	if dl is Array:
		for entry in dl:
			if entry is Dictionary:
				c.districts.append(entry.duplicate(true))
	return c
