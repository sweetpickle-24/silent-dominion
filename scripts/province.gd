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
@export var gold_production: float = 0.0
@export var horses_production: float = 0.0
@export var cloth_production: float = 0.0
@export var salt_production: float = 0.0
@export var owning_kingdom: String = ""

## Unrest is a 0–100 scalar tracked per province by Unrest (autoload).
## The number is never shown to the player; the Map panel reads it
## through unrest_phrase() / unrest_band().
@export var unrest: int = 0

## §B10 manpower pool. Ratio of recruitable men currently left
## against the province's baseline pool. 1.0 means fully replenished,
## 0.0 means the villages have been drained to the last boy. Bled by
## ArmyRegistry on mobilisation; regenerates slowly in peace
## (see PopulationManager._tick_manpower_recovery).
@export_range(0.0, 1.0) var manpower_fraction: float = 1.0

## §B10 dominant culture of the province. A short StringName so
## recruited armies can track a `culture_mix` dictionary without
## having to model a full ethnography. Defaults empty ("generic").
@export var culture: StringName = &""

## §D2 Optional city attached to this province. Null for the vast
## majority of provinces — only politically/culturally dense places
## (Athens, Sparta, etc.) carry one. Populated at world-load from
## JSON; player coverage lifts its district fog at tick time.
@export var city: City = null

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


## Total production value in silver-equivalent units for the treasury.
## Does not apply unrest / infrastructure modifiers — those live in
## `KingdomEconomy._monthly_income`. Gold carries a higher inherent
## value because bullion is bullion; the rest are already priced in
## silver-equivalent abstract units.
func total_production() -> float:
	return (
		grain_production
		+ silver_production
		+ iron_production
		+ timber_production
		+ gold_production * 4.0
		+ horses_production
		+ cloth_production
		+ salt_production
	)


## Resource-kind lookup used by `KingdomEconomy.total_resource`.
## Accepts the bare commodity name as StringName.
func production_of(kind: StringName) -> float:
	match kind:
		&"grain":  return grain_production
		&"silver": return silver_production
		&"iron":   return iron_production
		&"timber": return timber_production
		&"gold":   return gold_production
		&"horses": return horses_production
		&"cloth":  return cloth_production
		&"salt":   return salt_production
	return 0.0


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
	p.gold_production   = float(d.get("gold_production", 0.0))
	p.horses_production = float(d.get("horses_production", 0.0))
	p.cloth_production  = float(d.get("cloth_production", 0.0))
	p.salt_production   = float(d.get("salt_production", 0.0))
	p.owning_kingdom    = String(d.get("owning_kingdom", ""))
	p.unrest            = int(d.get("unrest", 0))
	p.manpower_fraction = clampf(float(d.get("manpower_fraction", 1.0)), 0.0, 1.0)
	p.culture           = StringName(String(d.get("culture", "")))
	p.buildings = []
	for b in d.get("buildings", []):
		p.buildings.append(StringName(String(b)))
	# §D2 optional embedded city
	var cd: Variant = d.get("city", null)
	if cd is Dictionary and not (cd as Dictionary).is_empty():
		p.city = City.from_dict(cd)
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


# --- Seasonality (§B7) -----------------------------------------------------
#
# GameClock months are 1-12. A province is "in campaign season" when an
# army can march and fight there without disproportionate attrition.
# NORTHERN and TEMPERATE climates shut down in their own winter windows;
# MEDITERRANEAN, ARID, and TROPICAL climates are open year-round in the
# simulation (real-world heat/monsoon nuance is intentionally out of
# scope at this zoom). Mountains / steppes tighten the window further.

func campaign_season(month: int) -> bool:
	var m: int = clampi(month, 1, 12)
	var is_winter_north: bool = m <= 2 or m == 12
	var is_shoulder: bool = m == 3 or m == 11
	match climate:
		Climate.NORTHERN:
			if is_winter_north:
				return false
			# Mountains / steppe lock down a month longer on each side.
			if is_shoulder and (terrain == Terrain.MOUNTAINS or terrain == Terrain.STEPPE):
				return false
			return true
		Climate.TEMPERATE:
			if is_winter_north:
				return false
			if is_shoulder and terrain == Terrain.MOUNTAINS:
				return false
			return true
		_:
			return true


## Trade throughput multiplier for this province for `month`. 1.0 is
## unaffected; below 1.0 signals a slow season (winter/storms); above
## 1.0 signals a caravan peak (post-harvest). Kept deliberately gentle
## so swings are visible without distorting yearly P&L.
func trade_season_multiplier(month: int) -> float:
	var m: int = clampi(month, 1, 12)
	match climate:
		Climate.MEDITERRANEAN:
			# Winter mare clausum on coastal / open provinces.
			if terrain == Terrain.COASTAL and (m <= 2 or m == 12):
				return 0.30
			if m == 3 or m == 11:
				return 0.75
			return 1.00
		Climate.TEMPERATE:
			if m <= 2 or m == 12:
				return 0.55
			if m == 3 or m == 11:
				return 0.85
			return 1.00
		Climate.NORTHERN:
			# Long winter stand-down, short trade peak.
			if m <= 3 or m == 12:
				return 0.35
			if m == 4 or m == 11:
				return 0.75
			return 1.00
		Climate.ARID:
			# Caravan heat-troughs: midsummer is the bad time, not winter.
			if m >= 6 and m <= 8:
				return 0.70
			return 1.00
		Climate.TROPICAL:
			# Monsoon approximation: one broad wet-season trough.
			if m >= 6 and m <= 9:
				return 0.70
			return 1.00
	return 1.00


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
