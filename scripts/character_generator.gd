extends Node
## Autoloaded as `Characters`. Procedural character generation (§8.8, §8.11).
##
## The hand-crafted roster at boot covers the structural seats —
## rulers, heirs, generals, advisors. Around them the world needs a
## steady trickle of merchants, priests, and philosophers so that
## over decades the player has new faces to cultivate and existing
## populations don't drain as their ambient actors age out.
##
## Each month this autoload rolls a small number of new minor actors
## into random populated provinces. Rate scales with total population.
## Traits are drawn through ActorRegistry's weighted path, so a
## province that has spent thirty years in revolt produces more
## paranoid, less loyal merchants than one that has been at peace.
##
## Historical figures (§8.8) — named individuals on a historical
## timeline — are handled elsewhere; this module only fills in the
## ambient cast.

signal character_generated(actor_id: StringName)

const MINOR_ROLES: Array[int] = [
	int(Actor.Role.MERCHANT),
	int(Actor.Role.PRIEST),
	int(Actor.Role.PHILOSOPHER),
]

# Approximate minor characters generated per million souls per month.
# At ~5M total population this is roughly 0.5 per month — over a
# century, fifty new merchants/priests/philosophers. Deliberately low
# so the registry doesn't balloon.
const POP_PER_SPAWN_PER_MONTH: int = 2_000   # in units of thousands (so 2M souls ≈ 1/month)

# Hard cap per minor role per kingdom to keep the registry bounded.
const PER_KINGDOM_ROLE_CAP: int = 20

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	GameClock.month_passed.connect(_on_month_passed)


func _on_month_passed(_y: int, _m: int) -> void:
	if not WorldData.is_loaded():
		return
	var total_pop: int = 0
	for p in WorldData.provinces.values():
		if p.population > 0:
			total_pop += p.population
	if total_pop <= 0:
		return

	# Expected spawns this month. We then roll each one independently.
	var expected: float = float(total_pop) / float(POP_PER_SPAWN_PER_MONTH)
	var rolls: int = int(floor(expected))
	var frac: float = expected - float(rolls)
	if _rng.randf() < frac:
		rolls += 1

	for _i in range(rolls):
		_spawn_one()


func _spawn_one() -> void:
	var province: Province = _pick_weighted_province()
	if province == null:
		return
	var role: int = _pick_role_for(province)
	if _role_capped_in_kingdom(province.owning_kingdom, role):
		return
	var a: Actor = Actors.spawn_minor_in_province(province.id, role)
	if a == null:
		return
	character_generated.emit(a.id)


# --- Selection ---------------------------------------------------------------

func _pick_weighted_province() -> Province:
	# Weight each province by population so larger cities produce more
	# public figures than backwaters. Skip empty/sea provinces.
	var total: int = 0
	var pool: Array = []
	for p in WorldData.provinces.values():
		if p.population <= 0:
			continue
		total += p.population
		pool.append({"p": p, "cum": total})
	if pool.is_empty():
		return null
	var roll: int = _rng.randi_range(1, total)
	for entry in pool:
		if roll <= int(entry["cum"]):
			return entry["p"]
	return pool[pool.size() - 1]["p"]


func _pick_role_for(p: Province) -> int:
	# Mild per-province bias: merchant-heavy harbour towns, priest-heavy
	# post-plague provinces, philosopher-heavy roaded provinces. Bias
	# adjusts weights rather than locks the choice.
	var w_merchant: float = 1.0
	var w_priest: float   = 1.0
	var w_phil: float     = 0.6
	if p.has_building(&"harbour"):
		w_merchant += 0.8
	if p.has_building(&"road_network"):
		w_phil += 0.4
	if p.has_meta("prod_modifier"):
		var cause: String = String((p.get_meta("prod_modifier") as Dictionary).get("cause", ""))
		if cause == "plague":
			w_priest += 0.8
		elif cause == "famine":
			w_priest += 0.4
	var total: float = w_merchant + w_priest + w_phil
	var roll: float = _rng.randf() * total
	if roll < w_merchant:
		return int(Actor.Role.MERCHANT)
	if roll < w_merchant + w_priest:
		return int(Actor.Role.PRIEST)
	return int(Actor.Role.PHILOSOPHER)


func _role_capped_in_kingdom(kingdom_id: String, role: int) -> bool:
	var count: int = 0
	for a in Actors.actors_in_kingdom(kingdom_id):
		if a.is_alive() and int(a.role) == role:
			count += 1
			if count >= PER_KINGDOM_ROLE_CAP:
				return true
	return false
