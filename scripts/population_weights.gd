extends Node
## Autoloaded as `PopWeights`. Generational trait drift (§8.11).
##
## Current-condition modifiers already live in ActorRegistry's
## `_apply_regional_weights` (war right now, plague right now). This
## module adds the thing that one can't do in a single-year snapshot:
## **compounding over generations.** It watches every kingdom each
## year, accumulates drift into per-trait modifiers, and hands those
## modifiers to ActorRegistry when a new character is rolled.
##
## Why a separate module:
##   - State has to persist across years, so `_apply_regional_weights`
##     is the wrong place (it's a pure function of the current tick).
##   - Rival societies read these modifiers too — they exploit
##     paranoid populations the player bred.
##
## How drift works:
##   Each year we look at the kingdom's state and add per-trait
##   increments (always small — at most a few points per year in
##   the worst cases). Drift decays slowly toward zero when the
##   causing condition is removed, so a century of peace undoes a
##   century of war, but not overnight.

const TRAITS: Array[StringName] = [
	&"ambition", &"paranoia", &"loyalty", &"piety",
	&"intellect", &"ruthlessness", &"curiosity",
]

# Each kingdom-year nudge is clamped to this range so pathological
# conditions don't instantly rewrite a population.
const MAX_YEARLY_STEP: int = 2
# Hard cap on accumulated drift in any direction — prevents a trait
# from being pegged to one extreme by long-running conditions.
const MAX_DRIFT: int = 25
# Passive decay toward zero each year. Slow enough that a century of
# war visibly shapes the populations born during and after.
const DECAY_PER_YEAR: float = 0.25

# kingdom_id -> { trait_key -> int drift }
var _drift: Dictionary = {}


func _ready() -> void:
	if WorldData.is_loaded():
		_initialise()
	else:
		WorldData.world_loaded.connect(_initialise)
	GameClock.year_passed.connect(_on_year_passed)


func _initialise() -> void:
	for kid in WorldData.kingdoms.keys():
		if not _drift.has(kid):
			_drift[kid] = _empty_drift_block()


func _empty_drift_block() -> Dictionary:
	var d: Dictionary = {}
	for t in TRAITS:
		d[t] = 0
	return d


# --- Public API --------------------------------------------------------------

## Apply the accumulated generational drift to a freshly rolled
## actor. Called from ActorRegistry._apply_regional_weights after the
## current-condition pass.
func apply_to_newborn(a: Actor, kingdom_id: String) -> void:
	if a == null or kingdom_id == "":
		return
	var block: Dictionary = _drift.get(kingdom_id, {})
	if block.is_empty():
		return
	for t in TRAITS:
		var d: int = int(block.get(t, 0))
		if d == 0:
			continue
		var current: int = int(a.get(t))
		a.set(t, clampi(current + d, 10, 90))


## Read-only peek. Mostly for the rival AI and for dev tooling —
## knowing that a kingdom's population has drifted +18 paranoid over
## the last two centuries is something the rivals can exploit.
func drift_for(kingdom_id: String, trait_key: StringName) -> int:
	var block: Dictionary = _drift.get(kingdom_id, {})
	return int(block.get(trait_key, 0))


## Qualitative phrase for the map / dossier. Returns empty string for
## kingdoms whose drift is within normal noise.
func headline_for(kingdom_id: String) -> String:
	var block: Dictionary = _drift.get(kingdom_id, {})
	if block.is_empty():
		return ""
	var biggest_key: StringName = &""
	var biggest_mag: int = 0
	for t in TRAITS:
		var v: int = int(block.get(t, 0))
		if abs(v) > biggest_mag:
			biggest_mag = abs(v)
			biggest_key = t
	if biggest_mag < 8:
		return ""
	var v2: int = int(block.get(biggest_key, 0))
	match String(biggest_key):
		"paranoia":     return "a population that has learned to watch its own shoulder" if v2 > 0 else "a trusting, open population"
		"loyalty":      return "a folk who no longer assume the crown is clean" if v2 < 0 else "a strikingly loyal generation"
		"piety":        return "a pious, devoted population" if v2 > 0 else "a conspicuously secular generation"
		"intellect":    return "a generation shaped toward learning" if v2 > 0 else "a generation shaped away from letters"
		"curiosity":    return "a restless, questioning population" if v2 > 0 else "an incurious, settled population"
		"ambition":     return "a hungry, upward-reaching generation" if v2 > 0 else "a complacent, comfortable generation"
		"ruthlessness": return "a hardened, practical population" if v2 > 0 else "a gentler generation than their parents"
	return ""


# --- Yearly accumulator ------------------------------------------------------

func _on_year_passed(_y: int) -> void:
	for kid in WorldData.kingdoms.keys():
		_accumulate_for(String(kid))
	_decay_toward_zero()


func _accumulate_for(kingdom_id: String) -> void:
	var k: Kingdom = WorldData.get_kingdom(kingdom_id)
	if k == null:
		return
	if not _drift.has(kingdom_id):
		_drift[kingdom_id] = _empty_drift_block()
	var block: Dictionary = _drift[kingdom_id]

	# 1. Sustained war — each year at war adds a tick of paranoia,
	#    piety (seeking comfort), ruthlessness; subtracts intellect,
	#    curiosity, loyalty in the hardest treasury condition.
	if Relations.ids_in_state(kingdom_id, int(Relations.RelationState.AT_WAR)).size() > 0:
		_nudge(block, &"paranoia",     1)
		_nudge(block, &"piety",        1)
		_nudge(block, &"ruthlessness", 1)
		_nudge(block, &"intellect",   -1)
		_nudge(block, &"curiosity",   -1)

	# 2. Sustained unrest across the kingdom's provinces.
	var restless: int = 0
	var in_revolt: int = 0
	for pid in k.owned_provinces:
		var p: Province = WorldData.get_province(pid)
		if p == null:
			continue
		var band: StringName = p.unrest_band()
		if band == &"restless":
			restless += 1
		elif band == &"seething" or band == &"in revolt":
			in_revolt += 1
	if in_revolt > 0:
		_nudge(block, &"loyalty",  -2)
		_nudge(block, &"paranoia",  1)
		_nudge(block, &"ambition",  1)
	elif restless > 0:
		_nudge(block, &"loyalty",  -1)

	# 3. Sustained peace + solid treasury — complacency.
	var treasury_solid: bool = (
		k.treasury_condition == Kingdom.TreasuryCondition.FLUSH
		or k.treasury_condition == Kingdom.TreasuryCondition.STABLE
	)
	if Relations.ids_in_state(kingdom_id, int(Relations.RelationState.AT_WAR)).is_empty() \
			and treasury_solid \
			and in_revolt == 0 and restless == 0:
		_nudge(block, &"ambition",  -1)
		_nudge(block, &"paranoia",  -1)

	# 4. Religious saturation — when a dominant faith holds the
	#    kingdom deeply, generational piety ticks up. Signal: average
	#    piety_bias across the kingdom's provinces.
	var piety_total: int = 0
	var piety_samples: int = 0
	for pid in k.owned_provinces:
		piety_samples += 1
		piety_total += Religions.piety_bias_for(pid)
	if piety_samples > 0:
		@warning_ignore("integer_division")
		var piety_avg: int = piety_total / piety_samples
		if piety_avg >= 4:
			_nudge(block, &"piety",    1)
			_nudge(block, &"curiosity", -1)
		elif piety_avg <= -3:
			_nudge(block, &"piety",    -1)
			_nudge(block, &"intellect", 1)

	# 5. Literacy / scholarly density — proxy: count of living
	#    philosophers per kingdom relative to population.
	var scholars: int = 0
	for a in Actors.actors_in_kingdom(kingdom_id):
		if a.is_alive() and a.role == Actor.Role.PHILOSOPHER:
			scholars += 1
	if scholars >= 3:
		_nudge(block, &"intellect", 1)
		_nudge(block, &"curiosity", 1)

	# 6. Ruinous taxation compounds into chronic distrust.
	if k.tax_level == Kingdom.TaxLevel.RUINOUS:
		_nudge(block, &"loyalty",  -1)
		_nudge(block, &"paranoia",  1)


func _nudge(block: Dictionary, key: StringName, delta: int) -> void:
	var clamped: int = clampi(delta, -MAX_YEARLY_STEP, MAX_YEARLY_STEP)
	var current: int = int(block.get(key, 0))
	block[key] = clampi(current + clamped, -MAX_DRIFT, MAX_DRIFT)


func _decay_toward_zero() -> void:
	for kid in _drift.keys():
		var block: Dictionary = _drift[kid]
		for t in TRAITS:
			var v: float = float(block.get(t, 0))
			if v == 0.0:
				continue
			if v > 0.0:
				v = max(0.0, v - DECAY_PER_YEAR)
			else:
				v = min(0.0, v + DECAY_PER_YEAR)
			block[t] = int(round(v))


# --- Save / load -------------------------------------------------------------

func snapshot() -> Dictionary:
	var out: Dictionary = {}
	for kid in _drift.keys():
		var block: Dictionary = _drift[kid]
		var copy: Dictionary = {}
		for t in TRAITS:
			copy[String(t)] = int(block.get(t, 0))
		out[String(kid)] = copy
	return {"drift": out}


func restore(d: Dictionary) -> void:
	var raw: Dictionary = d.get("drift", {})
	_drift.clear()
	for kid in raw.keys():
		var block: Dictionary = {}
		var src: Dictionary = raw[kid]
		for t in TRAITS:
			block[t] = int(src.get(String(t), 0))
		_drift[String(kid)] = block
	# Fill any missing kingdoms with zero blocks.
	if WorldData.is_loaded():
		for kid in WorldData.kingdoms.keys():
			if not _drift.has(kid):
				_drift[kid] = _empty_drift_block()
