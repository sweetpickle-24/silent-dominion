extends Node
## Autoloaded as `Population`. Province-level population drift (§26).
##
## Every month each populated province nudges its head-count. Peace and
## quiet grow it, slowly; unrest, plague, famine, and war erode it. The
## raw number is never shown — the Map detail panel reads qualitative
## phrases off `phrase_for()`. Large enough swings against the seeded
## baseline publish a single dispatch so the scroll can pick it up.
##
## Tuning is deliberately gentle: full peace is barely a percent a year,
## a province in revolt drops noticeably over a season, and a plague
## compounds on top of its production hit. Nothing here is meant to
## outrun player play; it is meant to make a continent that is watched
## for fifty years look like it actually lived them.

signal province_population_changed(province_id: String)

# Base natural growth is an annualised figure; we divide by twelve.
const BASE_ANNUAL_GROWTH: float = 0.005

# Monthly loss rates stacked on top of the base. Revolting provinces
# hurt the hardest; plague also carries its own monthly drag in
# addition to the production cut applied by RandomEvents.
const REVOLT_LOSS: float    = 0.008
const SEETHING_LOSS: float  = 0.003
const PLAGUE_LOSS: float    = 0.010
const FAMINE_LOSS: float    = 0.004
## Kingdoms at war drag their border provinces down a little. Small,
## because most provinces don't see the army up close.
const WAR_LOSS: float       = 0.001

## Provinces have to be at least this large before we bother announcing
## a boom/collapse publicly. Populations are stored in thousands, so
## this is 150k souls. A village of five thousand halving is not news
## the scroll should carry.
const ANNOUNCE_MIN_POP: int = 150

const COLLAPSE_RATIO: float = 0.75
const BOOM_RATIO: float     = 1.25

var _seed_population: Dictionary = {}  # province_id -> int seeded pop
var _last_band: Dictionary = {}        # province_id -> StringName
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	DevLogger.write("Population: ready")
	_rng.randomize()
	if WorldData.is_loaded():
		_snapshot_seed()
	else:
		WorldData.world_loaded.connect(_snapshot_seed, CONNECT_ONE_SHOT)
	GameClock.month_passed.connect(_on_month_passed)


# --- Public API --------------------------------------------------------------

## Seeded starting population for a province, for ratio-based phrasing.
func seed_for(province_id: String) -> int:
	return int(_seed_population.get(province_id, 0))


## §D3 Current population/seed ratio for a province. 1.0 ≈ steady,
## < COLLAPSE_RATIO = emptying, > BOOM_RATIO = swelling. Returns 1.0
## on unknown ids so callers can safely lerp without a null check.
## Used by the map renderer's famine overlay.
func population_ratio(province_id: String) -> float:
	var p: Province = WorldData.get_province(province_id)
	if p == null or p.population <= 0:
		return 1.0
	var base: int = seed_for(province_id)
	if base <= 0:
		return 1.0
	return float(p.population) / float(base)


## §D3 True when the province has been tagged with a hard famine
## event by the simulation (UnrestManager / random_events set
## `prod_modifier.cause = "famine"` on the province meta).
func is_famine(province_id: String) -> bool:
	var p: Province = WorldData.get_province(province_id)
	if p == null:
		return false
	if not p.has_meta("prod_modifier"):
		return false
	var m: Dictionary = p.get_meta("prod_modifier")
	return String(m.get("cause", "")) == "famine"


## Qualitative description of the current population state relative to
## its seed. The player never sees the raw number.
func phrase_for(province_id: String) -> String:
	var p: Province = WorldData.get_province(province_id)
	if p == null or p.population <= 0:
		return ""
	var base: int = seed_for(province_id)
	if base <= 0:
		base = p.population
	var ratio: float = float(p.population) / float(base)
	if ratio <= 0.60:
		return "half-empty by the standards of the elders"
	if ratio <= COLLAPSE_RATIO:
		return "noticeably thinned from a generation ago"
	if ratio <= 0.95:
		return "a little quieter than it was"
	if ratio < 1.05:
		return "about the size it has always been"
	if ratio < BOOM_RATIO:
		return "fuller than it was, the markets livelier"
	return "visibly thicker than within living memory"


func snapshot() -> Dictionary:
	var pops: Array = []
	if WorldData.is_loaded():
		for p in WorldData.provinces.values():
			pops.append({
				"id":                 p.id,
				"population":         p.population,
				"manpower_fraction":  p.manpower_fraction,
			})
	return {
		"pops":      pops,
		"seed":      _seed_population.duplicate(),
		"last_band": _last_band.duplicate(),
	}


func restore(d: Dictionary) -> void:
	if not WorldData.is_loaded():
		return
	for entry in d.get("pops", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var p: Province = WorldData.get_province(String(entry.get("id", "")))
		if p == null:
			continue
		p.population = int(entry.get("population", p.population))
		p.manpower_fraction = clampf(float(entry.get("manpower_fraction", 1.0)), 0.0, 1.0)
	_seed_population.clear()
	var seeded_raw: Variant = d.get("seed", {})
	if seeded_raw is Dictionary:
		for k in (seeded_raw as Dictionary).keys():
			_seed_population[String(k)] = int(seeded_raw[k])
	_last_band.clear()
	var last_raw: Variant = d.get("last_band", {})
	if last_raw is Dictionary:
		for k in (last_raw as Dictionary).keys():
			_last_band[String(k)] = StringName(String(last_raw[k]))


# --- Internal ----------------------------------------------------------------

func _snapshot_seed() -> void:
	_seed_population.clear()
	for p in WorldData.provinces.values():
		_seed_population[p.id] = p.population


func _on_month_passed(_y: int, _m: int) -> void:
	if not WorldData.is_loaded():
		return
	if _seed_population.is_empty():
		_snapshot_seed()
	for p in WorldData.provinces.values():
		if p.population <= 0:
			continue
		_tick_province(p)
		_tick_manpower_recovery(p)


## §B10 manpower pool regenerates slowly in peace and a touch slower
## in war. A fully drained province takes ~6 years to come back up —
## long enough that repeated wars visibly dry the villages out.
func _tick_manpower_recovery(p: Province) -> void:
	if p.manpower_fraction >= 1.0:
		return
	var at_war: bool = false
	if p.owning_kingdom != "":
		at_war = Relations.ids_in_state(
			p.owning_kingdom, int(Relations.RelationState.AT_WAR)
		).size() > 0
	var recover: float = 0.015 if not at_war else 0.005
	p.manpower_fraction = clampf(p.manpower_fraction + recover, 0.0, 1.0)


func _tick_province(p: Province) -> void:
	var rate: float = BASE_ANNUAL_GROWTH / 12.0

	var band: StringName = p.unrest_band()
	if band == &"in revolt":
		rate -= REVOLT_LOSS
	elif band == &"seething":
		rate -= SEETHING_LOSS

	if p.has_meta("prod_modifier"):
		var cause: String = String(
			(p.get_meta("prod_modifier") as Dictionary).get("cause", "")
		)
		match cause:
			"plague":
				rate -= PLAGUE_LOSS
			"famine":
				rate -= FAMINE_LOSS

	if p.owning_kingdom != "":
		var fronts: int = Relations.ids_in_state(
			p.owning_kingdom, int(Relations.RelationState.AT_WAR)
		).size()
		if fronts > 0:
			var war_drag: float = WAR_LOSS * float(fronts)
			# City walls save the population when the frontier moves —
			# the province is still a target, but a harder one.
			if p.has_building(&"city_walls"):
				war_drag *= 0.5
			rate -= war_drag

	# Tiny per-province noise so the numbers don't drift in lockstep.
	rate += _rng.randf_range(-0.0005, 0.0005)

	# Populations here are expressed in thousands (Athens = 220). Let
	# the fractional drift accumulate into whole integer steps instead
	# of forcing a ±1 jerk every tick — on the scale of a continent that
	# would boil the numbers in a year.
	var raw: float = float(p.population) * rate
	var fraction: float = float(p.get_meta("pop_residual", 0.0)) + raw
	var delta: int = int(round(fraction))
	p.set_meta("pop_residual", fraction - float(delta))
	if delta == 0:
		return

	var new_pop: int = maxi(0, p.population + delta)
	if new_pop == p.population:
		return
	p.population = new_pop
	province_population_changed.emit(p.id)
	_maybe_announce(p)


func _maybe_announce(p: Province) -> void:
	var base: int = int(_seed_population.get(p.id, p.population))
	if base < ANNOUNCE_MIN_POP:
		return
	var ratio: float = float(p.population) / float(base)
	var new_band: StringName = &"steady"
	if ratio <= COLLAPSE_RATIO:
		new_band = &"collapse"
	elif ratio >= BOOM_RATIO:
		new_band = &"boom"

	var old_band: StringName = _last_band.get(p.id, &"steady")
	if new_band == old_band:
		return
	_last_band[p.id] = new_band

	match new_band:
		&"collapse":
			EventBus.public_event.emit({
				"kind":       &"population_collapse",
				"kingdom_id": p.owning_kingdom,
				"province":   p.id,
				"headline":   "Emptying of %s" % p.province_name,
				"body":       "Travellers say the lanes of %s are quieter than a generation ago. Fewer hearths, fewer hands in the fields. The elders count the empty houses without being asked." % p.province_name,
			})
		&"boom":
			EventBus.public_event.emit({
				"kind":       &"population_boom",
				"kingdom_id": p.owning_kingdom,
				"province":   p.id,
				"headline":   "Fuller streets in %s" % p.province_name,
				"body":       "The markets of %s are thicker than the elders remember. New houses going up at the edges; the gate-clerks cannot keep pace with the tolls." % p.province_name,
			})
		_:
			pass
