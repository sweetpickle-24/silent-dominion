extends Node
## Autoloaded as `Armies`. One standing army per kingdom (§27).
##
## Each kingdom carries a single Army resource. Peace rebuilds it, war
## grinds it. Thresholds are tuned for a fifty-year continent: a
## sustained war slides morale and supply downward by visible bands,
## while a kingdom at peace for a decade trends back to ceiling.
##
## Battles proper (§9.1) are resolved in battle_resolver.gd and mutate
## the army fields; this module only handles the background drift.

signal army_changed(kingdom_id: String)
## Emitted when an army's size, morale, or loyalty crosses a public
## band — so the scroll can speak of "Persia under arms" or "Corinth's
## ranks thinning" without exposing the numbers.
@warning_ignore("unused_signal")
signal army_band_crossed(kingdom_id: String, band: StringName)

# Ceiling as a fraction of total kingdom population. In units of
# "thousands of men per thousand of population" — so 0.04 means a
# kingdom of one million souls tops out near forty thousand men under
# arms. Historically high for the era; this is a strategy game.
const CEILING_RATIO: float = 0.040

# Starting fill vs ceiling. Kingdoms do not begin the game fully
# mobilised; they can ramp in wartime.
const START_FILL: float = 0.55

# --- Monthly drift tuning ----------------------------------------------------

const PEACE_RECRUIT_RATE: float = 0.015   # 1.5% of ceiling per month at peace
const WAR_RECRUIT_RATE:   float = 0.030   # emergency mobilisation
const PEACE_ATTRITION:    float = 0.003   # 0.3% monthly leave-the-colours

# Supply and morale drift each month. Positive = trending up.
const SUPPLY_RECOVER_PER_MONTH: int = 4
const SUPPLY_WAR_DRAIN:         int = 3

const MORALE_PEACE_RECOVER:  int = 2
const MORALE_WAR_DRAIN:      int = 3
const MORALE_BROKE_PENALTY:  int = 2
const MORALE_LOW_SUPPLY_HIT: int = 4   # triggers if supply < 30

const LOYALTY_UNPAID_DRAIN:  int = 3   # applies when treasury BROKE/INDEBTED
const LOYALTY_REGENCY_DRAIN: int = 1
const LOYALTY_PEACE_RECOVER: int = 1

# Attrition when severely under-supplied at war.
const WAR_LOW_SUPPLY_ATTRITION: float = 0.010


var _armies: Dictionary = {}            # kingdom_id -> Army
var _last_size_band: Dictionary = {}    # kingdom_id -> StringName
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if WorldData.is_loaded():
		_seed()
	else:
		WorldData.world_loaded.connect(_seed, CONNECT_ONE_SHOT)
	GameClock.month_passed.connect(_on_month_passed)


# --- Public API --------------------------------------------------------------

func get_army(kingdom_id: String) -> Army:
	return _armies.get(kingdom_id, null)


func all_armies() -> Array[Army]:
	var out: Array[Army] = []
	for a in _armies.values():
		out.append(a)
	return out


## Shorthand strength phrase — for the ledger, map detail, reports.
func strength_phrase(kingdom_id: String) -> String:
	var a: Army = get_army(kingdom_id)
	if a == null:
		return "no standing force"
	return "%s; %s; %s" % [a.size_phrase(), a.morale_phrase(), a.supply_phrase()]


## The public size band — used by news and UI to decide whether a
## transition is newsworthy. Returns one of: broken, skeleton, modest,
## standing, great, host.
func size_band(a: Army) -> StringName:
	if a.size <= 0:
		return &"broken"
	if a.size < 3:
		return &"skeleton"
	if a.size < 8:
		return &"modest"
	if a.size < 20:
		return &"standing"
	if a.size < 50:
		return &"great"
	return &"host"


# --- Monthly tick ------------------------------------------------------------

func _on_month_passed(_y: int, _m: int) -> void:
	if not WorldData.is_loaded():
		return
	for a in _armies.values():
		_tick_army(a)


func _tick_army(a: Army) -> void:
	var k: Kingdom = WorldData.get_kingdom(a.kingdom_id)
	if k == null:
		return
	var at_war: bool = Relations.ids_in_state(
		k.id, int(Relations.RelationState.AT_WAR)
	).size() > 0

	_tick_supply(a, k, at_war)
	_tick_morale(a, k, at_war)
	_tick_loyalty(a, k)
	_tick_size(a, k, at_war)

	army_changed.emit(a.kingdom_id)
	_maybe_announce_size(a)


func _tick_supply(a: Army, k: Kingdom, at_war: bool) -> void:
	var delta: int = 0
	if at_war:
		delta -= SUPPLY_WAR_DRAIN
		# A broke crown cannot buy bread for a campaign.
		if int(k.treasury_condition) >= int(Kingdom.TreasuryCondition.INDEBTED):
			delta -= 2
	else:
		# Peace lets the quartermasters refill the stores, but only
		# as fast as the treasury permits.
		match k.treasury_condition:
			Kingdom.TreasuryCondition.FLUSH:    delta += SUPPLY_RECOVER_PER_MONTH
			Kingdom.TreasuryCondition.STABLE:   delta += SUPPLY_RECOVER_PER_MONTH - 1
			Kingdom.TreasuryCondition.STRAINED: delta += 1
			Kingdom.TreasuryCondition.INDEBTED: delta += 0
			Kingdom.TreasuryCondition.BROKE:    delta -= 1
	a.supply = clampi(a.supply + delta, 0, 100)


func _tick_morale(a: Army, k: Kingdom, at_war: bool) -> void:
	var delta: int = 0
	if at_war:
		delta -= MORALE_WAR_DRAIN
	else:
		delta += MORALE_PEACE_RECOVER
	if int(k.treasury_condition) >= int(Kingdom.TreasuryCondition.INDEBTED):
		delta -= MORALE_BROKE_PENALTY
	if a.supply < 30:
		delta -= MORALE_LOW_SUPPLY_HIT
	if k.in_regency:
		delta -= 1
	a.morale = clampi(a.morale + delta, 0, 100)


func _tick_loyalty(a: Army, k: Kingdom) -> void:
	var delta: int = 0
	if int(k.treasury_condition) >= int(Kingdom.TreasuryCondition.INDEBTED):
		delta -= LOYALTY_UNPAID_DRAIN
	else:
		delta += LOYALTY_PEACE_RECOVER
	if k.in_regency:
		delta -= LOYALTY_REGENCY_DRAIN
	a.loyalty = clampi(a.loyalty + delta, 0, 100)


func _tick_size(a: Army, k: Kingdom, at_war: bool) -> void:
	# Refresh ceiling from current population; a plague or famine
	# that halves a province reduces what the crown can raise.
	var ceiling: int = _ceiling_for(k)
	a.size_ceiling = ceiling
	if ceiling <= 0:
		return

	# Severe under-supply on campaign bleeds the rolls outright.
	if at_war and a.supply < 20:
		var attrition: int = int(round(float(a.size) * WAR_LOW_SUPPLY_ATTRITION))
		a.size = maxi(0, a.size - maxi(1, attrition))

	var rate: float = WAR_RECRUIT_RATE if at_war else PEACE_RECRUIT_RATE
	# Can't recruit what the coffers can't buy.
	match k.treasury_condition:
		Kingdom.TreasuryCondition.BROKE:    rate *= 0.0
		Kingdom.TreasuryCondition.INDEBTED: rate *= 0.3
		Kingdom.TreasuryCondition.STRAINED: rate *= 0.7

	var room: int = ceiling - a.size
	if room > 0 and rate > 0.0:
		var recruits: int = maxi(1, int(round(float(ceiling) * rate)))
		a.size = mini(ceiling, a.size + recruits)
	elif room < 0 and not at_war:
		# Peacetime attrition pulls the number back toward ceiling's
		# natural level — kingdoms don't keep more men under arms than
		# the provinces want to feed.
		var leave: int = int(round(float(a.size) * PEACE_ATTRITION))
		a.size = maxi(ceiling, a.size - maxi(1, leave))


# --- Seeding -----------------------------------------------------------------

func _seed() -> void:
	_armies.clear()
	for k in WorldData.kingdoms.values():
		var army: Army = Army.new()
		army.id = "army_%s" % k.id
		army.kingdom_id = k.id
		army.size_ceiling = _ceiling_for(k)
		army.size = int(round(float(army.size_ceiling) * START_FILL))
		# Baseline vitals with a small spread so not every crown sits
		# on identical numbers.
		army.quality = clampi(45 + _rng.randi_range(-8, 12), 10, 95)
		army.morale  = clampi(62 + _rng.randi_range(-5, 8), 10, 95)
		army.supply  = clampi(75 + _rng.randi_range(-10, 10), 10, 100)
		army.loyalty = clampi(70 + _rng.randi_range(-10, 10), 10, 100)
		_armies[k.id] = army
		_last_size_band[k.id] = size_band(army)


func _ceiling_for(k: Kingdom) -> int:
	var total_pop: int = 0
	for pid in k.owned_provinces:
		var p: Province = WorldData.get_province(pid)
		if p == null or p.population <= 0:
			continue
		total_pop += p.population
	return int(round(float(total_pop) * CEILING_RATIO))


# --- Public events -----------------------------------------------------------

func _maybe_announce_size(a: Army) -> void:
	var band: StringName = size_band(a)
	var prev: StringName = _last_size_band.get(a.kingdom_id, band)
	if band == prev:
		return
	_last_size_band[a.kingdom_id] = band
	var k: Kingdom = WorldData.get_kingdom(a.kingdom_id)
	if k == null:
		return
	var going_up: bool = _band_rank(band) > _band_rank(prev)
	var headline: String
	var body: String
	if going_up:
		headline = "%s under arms" % k.kingdom_name
		body = "Word from the border: the standard of %s has raised %s. The recruiters have taken more men than the villages expected to give." % [
			k.kingdom_name, a.size_phrase(),
		]
	else:
		headline = "The ranks thin in %s" % k.kingdom_name
		body = "The muster-rolls of %s have shrunk. %s. Whether the crown will own to it is another matter." % [
			k.kingdom_name, a.size_phrase(),
		]
	EventBus.public_event.emit({
		"kind":       &"army_shift",
		"kingdom_id": k.id,
		"headline":   headline,
		"body":       body,
	})
	army_band_crossed.emit(a.kingdom_id, band)


func _band_rank(b: StringName) -> int:
	match b:
		&"broken":   return 0
		&"skeleton": return 1
		&"modest":   return 2
		&"standing": return 3
		&"great":    return 4
		&"host":     return 5
		_:           return 2


# --- Save/load ---------------------------------------------------------------

func snapshot() -> Dictionary:
	var arr: Array = []
	for a in _armies.values():
		arr.append(a.to_dict())
	return {
		"armies":    arr,
		"last_band": _last_size_band.duplicate(),
	}


func restore(d: Dictionary) -> void:
	_armies.clear()
	for entry in d.get("armies", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var a: Army = Army.from_dict(entry)
		if a.kingdom_id == "":
			continue
		_armies[a.kingdom_id] = a
	_last_size_band.clear()
	var last: Dictionary = d.get("last_band", {})
	for k in last.keys():
		_last_size_band[String(k)] = StringName(String(last[k]))
