extends Node
## Autoloaded as `Infrastructure`. Autonomous construction of permanent
## province-level infrastructure (§8.7).
##
## The player never builds anything directly — kingdoms decide. Each
## month a kingdom with a healthy enough treasury rolls a small chance
## to commit to a new project in one of its provinces. Construction
## runs over 1–3 years; completion is announced on the public scroll
## and mutates Province.buildings, which persists forever (unless a
## future system demolishes it).
##
## This module only models the construction pipeline. Effects — walls
## softening war attrition, granaries softening famine bumps, harbours
## lifting silver — live in the subsystems that care (Population,
## RandomEvents, KingdomEconomy) and read `Province.has_building()`.

signal project_started(kingdom_id: String, province_id: String, kind: StringName)
signal project_completed(kingdom_id: String, province_id: String, kind: StringName)

const TASK_KIND: StringName = &"infrastructure_done"

# Monthly per-kingdom chance to start a new project. Kept modest — a
# continent shouldn't fill up with castles in a decade.
const START_CHANCE_FLUSH:  float = 0.18
const START_CHANCE_STABLE: float = 0.10
const START_CHANCE_OTHER:  float = 0.02   # only at peace

const PROJECT_COSTS: Dictionary = {
	&"road_network": 26.0,
	&"city_walls":   42.0,
	&"granary":      18.0,
	&"harbour":      34.0,
}

# Construction timelines in days. Range inclusive.
const PROJECT_DAYS: Dictionary = {
	&"road_network": [540, 900],
	&"city_walls":   [720, 1260],
	&"granary":      [240, 420],
	&"harbour":      [540, 900],
}

var _in_progress: Dictionary = {}   # province_id -> Array of StringName kinds under construction
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	GameClock.month_passed.connect(_on_month_passed)
	Scheduler.task_due.connect(_on_task_due)


# --- Public helpers ----------------------------------------------------------

func is_under_construction(province_id: String, kind: StringName) -> bool:
	var arr: Array = _in_progress.get(province_id, [])
	return arr.has(kind)


func construction_list_for(province_id: String) -> Array:
	return (_in_progress.get(province_id, []) as Array).duplicate()


## Flavour phrase describing the finished and in-progress work on a
## province. Used by the map detail panel.
func phrase_for(province_id: String) -> String:
	var p: Province = WorldData.get_province(province_id)
	if p == null:
		return ""
	var parts: Array[String] = []
	if p.has_building(&"city_walls"):
		parts.append("stone walls enclose the old quarter")
	if p.has_building(&"road_network"):
		parts.append("the paved road reaches the capital")
	if p.has_building(&"granary"):
		parts.append("a crown granary stands by the forum")
	if p.has_building(&"harbour"):
		parts.append("a dressed-stone harbour guards the bay")
	var pending: Array = construction_list_for(p.id)
	for k in pending:
		parts.append("a %s is under construction" % _kind_phrase(k))
	if parts.is_empty():
		return ""
	return ".  ".join(parts) + "."


# --- Monthly roll ------------------------------------------------------------

func _on_month_passed(_y: int, _m: int) -> void:
	if not WorldData.is_loaded():
		return
	for k in WorldData.kingdoms.values():
		_maybe_start_project(k)


func _maybe_start_project(k: Kingdom) -> void:
	var at_war: bool = Relations.ids_in_state(
		k.id, int(Relations.RelationState.AT_WAR)
	).size() > 0

	var chance: float = 0.0
	match k.treasury_condition:
		Kingdom.TreasuryCondition.FLUSH:    chance = START_CHANCE_FLUSH
		Kingdom.TreasuryCondition.STABLE:   chance = START_CHANCE_STABLE
		Kingdom.TreasuryCondition.STRAINED: chance = START_CHANCE_OTHER
		_:                                  return   # indebted/broke crowns don't commission walls

	# Crowns at war almost never start civilian projects; the exception
	# is walls, rolled separately below with their own pathway.
	if at_war:
		chance *= 0.25

	if _rng.randf() > chance:
		return

	var choice: Dictionary = _pick_project(k, at_war)
	if choice.is_empty():
		return
	_commit_project(k, choice)


func _pick_project(k: Kingdom, at_war: bool) -> Dictionary:
	# Build a list of (province, kind) candidates weighted by need.
	var candidates: Array = []
	for pid in k.owned_provinces:
		var p: Province = WorldData.get_province(pid)
		if p == null or p.population <= 0:
			continue
		for kind_v in PROJECT_COSTS.keys():
			var kind: StringName = StringName(String(kind_v))
			if p.has_building(kind) or is_under_construction(p.id, kind):
				continue
			var weight: float = _score_project(k, p, kind, at_war)
			if weight <= 0.0:
				continue
			candidates.append({"province": p, "kind": kind, "weight": weight})
	if candidates.is_empty():
		return {}

	var total: float = 0.0
	for c in candidates:
		total += float(c["weight"])
	var roll: float = _rng.randf() * total
	var cum: float = 0.0
	for c in candidates:
		cum += float(c["weight"])
		if roll <= cum:
			return c
	return candidates[candidates.size() - 1]


func _score_project(k: Kingdom, p: Province, kind: StringName, at_war: bool) -> float:
	var cost: float = float(PROJECT_COSTS.get(kind, 99.0))
	if k.treasury_silver < cost:
		return 0.0

	match kind:
		&"harbour":
			if p.terrain != Province.Terrain.COASTAL:
				return 0.0
			return 1.0 + float(p.population) / 400.0
		&"city_walls":
			var base: float = 0.6 + float(p.population) / 500.0
			if at_war:
				base *= 2.0
			if p.unrest >= 45:
				base *= 1.4
			return base
		&"granary":
			if at_war:
				return 0.2
			var base2: float = 0.8 + float(p.population) / 700.0
			if p.has_meta("prod_modifier"):
				base2 *= 1.8
			return base2
		&"road_network":
			if at_war:
				return 0.3
			return 0.5 + float(p.population) / 600.0
	return 0.0


func _commit_project(k: Kingdom, choice: Dictionary) -> void:
	var kind: StringName = StringName(String(choice["kind"]))
	var p: Province = choice["province"]
	var cost: float = float(PROJECT_COSTS.get(kind, 0.0))
	k.treasury_silver = maxf(0.0, k.treasury_silver - cost)

	var bounds: Array = PROJECT_DAYS.get(kind, [480, 720])
	var days: int = _rng.randi_range(int(bounds[0]), int(bounds[1]))
	Scheduler.schedule_task_in_days(days, {
		"kind":        String(TASK_KIND),
		"province_id": p.id,
		"building":    String(kind),
	})

	var arr: Array = _in_progress.get(p.id, [])
	arr.append(kind)
	_in_progress[p.id] = arr

	project_started.emit(k.id, p.id, kind)
	# Ground-breaking is colour, not record. A ribbon-cutting (the
	# "construction_done" event further down) is structural and always
	# fires. The opener stays quiet for kingdoms we have no eyes on.
	if Fidelity.is_high(k.id):
		EventBus.public_event.emit({
			"kind":       &"construction_start",
			"kingdom_id": k.id,
			"province":   p.id,
			"headline":   "The crown of %s breaks ground in %s" % [k.kingdom_name, p.province_name],
			"body":       _start_body(k, p, kind),
		})


func _on_task_due(descriptor: Dictionary) -> void:
	if String(descriptor.get("kind", "")) != String(TASK_KIND):
		return
	var pid: String = String(descriptor.get("province_id", ""))
	var kind: StringName = StringName(String(descriptor.get("building", "")))
	var p: Province = WorldData.get_province(pid)
	if p == null or kind == &"":
		return

	var arr: Array = _in_progress.get(pid, [])
	arr.erase(kind)
	if arr.is_empty():
		_in_progress.erase(pid)
	else:
		_in_progress[pid] = arr

	if not p.has_building(kind):
		p.buildings.append(kind)

	project_completed.emit(p.owning_kingdom, pid, kind)
	var k: Kingdom = WorldData.get_kingdom(p.owning_kingdom)
	var kname: String = k.kingdom_name if k != null else p.owning_kingdom
	EventBus.public_event.emit({
		"kind":       &"construction_done",
		"kingdom_id": p.owning_kingdom,
		"province":   p.id,
		"headline":   "%s: %s complete" % [p.province_name, _kind_title(kind)],
		"body":       _completion_body(p, kname, kind),
	})


# --- Flavour -----------------------------------------------------------------

func _start_body(_k: Kingdom, p: Province, kind: StringName) -> String:
	match kind:
		&"road_network":
			return "Surveyors and gravel carts seen on the approach to %s. The crown intends to pave the road from the capital; the project will take several seasons." % p.province_name
		&"city_walls":
			return "Stonemasons hired out to %s. The old earthworks are being replaced with dressed stone — the work will not be finished this reign, but it has begun." % p.province_name
		&"granary":
			return "A crown granary is going up near the forum of %s. The bricks are already rising. Grain is being bought at quiet prices against the day it opens." % p.province_name
		&"harbour":
			return "The bay at %s has been surveyed; pilings driven at the new mole. A dressed-stone harbour is intended — the sort of work that will be named after the ruler if they live to cut the ribbon." % p.province_name
	return "Construction begins in %s." % p.province_name


func _completion_body(p: Province, kname: String, kind: StringName) -> String:
	match kind:
		&"road_network":
			return "The paved road from the capital has reached %s. Carts move faster than walkers now; the tax-clerks on both ends have already begun arguing about who owns the extra revenue." % p.province_name
		&"city_walls":
			return "The new walls of %s are up. The crown of %s paid for them, eventually. A besieger will need a different plan than the last one had." % [p.province_name, kname]
		&"granary":
			return "The crown granary at %s stands finished. It will not prevent a famine — but it will make the next one less of a disaster than the one before it." % p.province_name
		&"harbour":
			return "The new harbour at %s opens this season. Larger ships in, larger ships out, larger tolls either way. The %s treasury will feel it next spring." % [p.province_name, kname]
	return "The work at %s is finished." % p.province_name


func _kind_title(kind: StringName) -> String:
	match kind:
		&"road_network": return "the paved road"
		&"city_walls":   return "new walls"
		&"granary":      return "a crown granary"
		&"harbour":      return "a dressed-stone harbour"
	return String(kind)


func _kind_phrase(kind: StringName) -> String:
	match kind:
		&"road_network": return "new paved road"
		&"city_walls":   return "new set of walls"
		&"granary":      return "new granary"
		&"harbour":      return "new harbour"
	return String(kind)


# --- Save/load ---------------------------------------------------------------

func snapshot() -> Dictionary:
	var buildings: Array = []
	if WorldData.is_loaded():
		for p in WorldData.provinces.values():
			if not p.buildings.is_empty():
				buildings.append({
					"id": p.id,
					"buildings": _array_to_strings(p.buildings),
				})
	var pending: Dictionary = {}
	for pid in _in_progress.keys():
		pending[pid] = _array_to_strings(_in_progress[pid])
	return {
		"buildings": buildings,
		"pending":   pending,
	}


func restore(d: Dictionary) -> void:
	_in_progress.clear()
	if WorldData.is_loaded():
		for p in WorldData.provinces.values():
			p.buildings = []
		for entry in d.get("buildings", []):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var p: Province = WorldData.get_province(String(entry.get("id", "")))
			if p == null:
				continue
			for b in entry.get("buildings", []):
				p.buildings.append(StringName(String(b)))
	var pending: Dictionary = d.get("pending", {})
	for pid in pending.keys():
		var arr: Array = []
		for b in pending[pid]:
			arr.append(StringName(String(b)))
		_in_progress[String(pid)] = arr


func _array_to_strings(arr: Array) -> Array:
	var out: Array = []
	for v in arr:
		out.append(String(v))
	return out
