class_name Province
extends Resource
## A single geographic province.
##
## Provinces are the atomic unit of the world: land, people, and the
## resources those people produce. Kingdoms hold collections of these.
## Sea/empty provinces have zero population and production and are used
## for strategic connectivity (trade routes, fleet movement) only.

enum Terrain {
	PLAINS,
	FOREST,
	MOUNTAINS,
	DESERT,
	COASTAL,
	HILLS,
	STEPPE,
}

enum Climate {
	MEDITERRANEAN,
	TEMPERATE,
	ARID,
	TROPICAL,
	NORTHERN,
}

@export var id: String = ""
@export var province_name: String = ""
@export var terrain: Terrain = Terrain.PLAINS
@export var climate: Climate = Climate.MEDITERRANEAN
@export var population: int = 0
@export var grain_production: float = 0.0
@export var silver_production: float = 0.0
@export var iron_production: float = 0.0
@export var timber_production: float = 0.0
@export var owning_kingdom: String = ""

## Unrest is a 0–100 scalar tracked per province by Unrest (autoload).
## The number is never shown to the player; the Map panel reads it
## through unrest_phrase() / unrest_band().
@export var unrest: int = 0

## Completed infrastructure projects built in this province (§8.7).
## Persistent once finished. Recognised kinds:
##   &"road_network"  — kingdom-wide trade boost
##   &"city_walls"    — softens war attrition against the province
##   &"granary"       — softens famine/plague unrest bumps
##   &"harbour"       — coastal only; boosts silver production
## The Infrastructure autoload owns the construction pipeline; this
## field only records what has been completed.
@export var buildings: Array[StringName] = []


func has_building(kind: StringName) -> bool:
	return buildings.has(kind)


static func from_dict(d: Dictionary) -> Province:
	var p: Province = Province.new()
	p.id = String(d.get("id", ""))
	p.province_name = String(d.get("province_name", ""))
	p.terrain = _terrain_from_string(String(d.get("terrain", "PLAINS")))
	p.climate = _climate_from_string(String(d.get("climate", "MEDITERRANEAN")))
	p.population = int(d.get("population", 0))
	p.grain_production  = float(d.get("grain_production", 0.0))
	p.silver_production = float(d.get("silver_production", 0.0))
	p.iron_production   = float(d.get("iron_production", 0.0))
	p.timber_production = float(d.get("timber_production", 0.0))
	p.owning_kingdom    = String(d.get("owning_kingdom", ""))
	p.unrest            = int(d.get("unrest", 0))
	p.buildings = []
	for b in d.get("buildings", []):
		p.buildings.append(StringName(String(b)))
	return p


static func _terrain_from_string(s: String) -> Terrain:
	match s.to_upper():
		"PLAINS":    return Terrain.PLAINS
		"FOREST":    return Terrain.FOREST
		"MOUNTAINS": return Terrain.MOUNTAINS
		"DESERT":    return Terrain.DESERT
		"COASTAL":   return Terrain.COASTAL
		"HILLS":     return Terrain.HILLS
		"STEPPE":    return Terrain.STEPPE
		_:           return Terrain.PLAINS


static func _climate_from_string(s: String) -> Climate:
	match s.to_upper():
		"MEDITERRANEAN": return Climate.MEDITERRANEAN
		"TEMPERATE":     return Climate.TEMPERATE
		"ARID":          return Climate.ARID
		"TROPICAL":      return Climate.TROPICAL
		"NORTHERN":      return Climate.NORTHERN
		_:               return Climate.MEDITERRANEAN


func terrain_name() -> String:
	return Terrain.keys()[terrain]


func climate_name() -> String:
	return Climate.keys()[climate]


## Qualitative band for the current unrest level. Matches the codebook.
func unrest_band() -> StringName:
	if unrest <= 4:   return &"quiet"
	if unrest < 20:   return &"uneasy"
	if unrest < 45:   return &"restless"
	if unrest < 70:   return &"seething"
	return &"in revolt"


## A longer sentence the Map panel prints instead of the raw number.
func unrest_phrase() -> String:
	match unrest_band():
		&"quiet":     return "The streets are quiet. Children at the fountain, elders at the gate."
		&"uneasy":    return "A certain watchfulness has entered the markets. Nothing named, yet."
		&"restless":  return "Knots of men argue in corners. The guard is paid to look tired and does."
		&"seething": return "Broadsides appear on walls at night. The crown's name is being said in the wrong tones."
		_:            return "The province is past orderly. Stones in the square, doors barred, names shouted."
