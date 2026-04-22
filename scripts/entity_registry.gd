extends Node
## Autoloaded as `Entities`. Registry + monthly tick for owned entities
## the player holds through proxies (§20). Banking houses are owned
## entities too, but live in `Finance` — they predate this system and
## kept their own mechanics. Everything else — trading companies,
## academies, monasteries, guilds, estates — lives here.
##
## What the tick does each month:
##   - pays yield silver into Purse (minus a skim for corrupt entities)
##   - bumps Picture visibility in the relevant kingdoms (home always;
##     trading company reach on top; monasteries add a small stale-
##     proof baseline)
##   - advances corruption slowly; faster in unstable / low-fidelity
##     kingdoms or when the proxy is dead
##   - emits a public event when an entity loses or recovers control
##   - on first-time founding seeds a single starter asset so the
##     player begins with something observable, in keeping with the
##     "you inherit a machine" framing

signal entity_added(id: StringName)
signal entity_changed(id: StringName)
signal entity_lost(id: StringName, reason: StringName)

const VISIBILITY_CAP: int = 35           # entities alone can't push past cautious recognition
const CORRUPTION_DRIFT_PER_MONTH: float = 0.15
const CORRUPTION_SKIM_AT_LEAK: float = 0.15     # 15% off the top once leaking
const CORRUPTION_SKIM_AT_LOSS: float = 1.0      # 100% gone once past the loss threshold
const LEAK_WARN_THRESHOLD:     int = OwnedEntity.CORRUPTION_LEAK_THRESHOLD
const LOSS_WARN_THRESHOLD:     int = OwnedEntity.CORRUPTION_LOSS_THRESHOLD

# id -> OwnedEntity
var entities: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Entities we've already announced as lost; prevents repeat events.
var _announced_lost: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	GameClock.month_passed.connect(_on_month_passed)
	# Seed starter holdings once the world is ready.
	if WorldData.is_loaded():
		call_deferred("_seed_starter_entities_if_empty")
	else:
		WorldData.world_loaded.connect(_seed_starter_entities_if_empty)


# --- Public API --------------------------------------------------------------

func all_entities() -> Array[OwnedEntity]:
	var out: Array[OwnedEntity] = []
	for e in entities.values():
		out.append(e)
	return out


func active_entities() -> Array[OwnedEntity]:
	var out: Array[OwnedEntity] = []
	for e in entities.values():
		if e.is_active():
			out.append(e)
	return out


func get_entity(id: StringName) -> OwnedEntity:
	return entities.get(id, null)


## Adds an entity to the registry. Caller is responsible for setting
## its fields; the registry wires it into the tick and the save file.
func register(e: OwnedEntity) -> void:
	if e == null or e.id == &"":
		return
	entities[e.id] = e
	entity_added.emit(e.id)


## Simple founding helper. The caller provides type + home + silver
## cost; the helper spins up an OwnedEntity with sensible defaults
## for its kind and registers it. Used by seeding and by any future
## "found_trading_company" etc. action.
func found_entity(
	kind: OwnedEntity.Kind,
	display_name: String,
	home_province: String,
	home_kingdom: String = "",
	founded_year: int = 0,
) -> OwnedEntity:
	var e: OwnedEntity = OwnedEntity.new()
	e.id = StringName("%s_%d_%s" % [
		OwnedEntity.Kind.keys()[kind].to_lower(),
		founded_year if founded_year != 0 else GameClock.year,
		home_province if home_province != "" else String(randi() % 100000),
	])
	e.display_name  = display_name
	e.kind          = kind
	e.home_province = home_province
	e.home_kingdom  = home_kingdom if home_kingdom != "" else _kingdom_for_province(home_province)
	e.founded_year  = founded_year if founded_year != 0 else -GameClock.year
	_apply_kind_defaults(e)
	register(e)
	return e


# --- Seeding -----------------------------------------------------------------

func _seed_starter_entities_if_empty() -> void:
	if not entities.is_empty():
		return
	# Starter asset: a single trading company anchored in the player's
	# home region. The exact province is picked lazily so we don't
	# assume any particular starting city.
	var home_prov: String = _pick_starter_province()
	if home_prov == "":
		return
	var home_king: String = _kingdom_for_province(home_prov)
	var e: OwnedEntity = OwnedEntity.new()
	e.id             = StringName("trading_company_inherited")
	e.display_name   = "Inherited trading consortium"
	e.kind           = OwnedEntity.Kind.TRADING_COMPANY
	e.home_province  = home_prov
	e.home_kingdom   = home_king
	e.founded_year   = -GameClock.year - 40   # 40 years old on game start
	_apply_kind_defaults(e)
	# A handful of mature routes into neighbouring kingdoms. Kept small
	# so the player doesn't start with planetary reach.
	var extra_reach: Array[String] = []
	for k in WorldData.kingdoms.values():
		if k.id == home_king:
			continue
		if extra_reach.size() < 2:
			extra_reach.append(k.id)
	for k in extra_reach:
		e.reach.append(k)
	register(e)


func _pick_starter_province() -> String:
	# Anchor the starter consortium in Attica if it exists (the
	# Phase-1 default home), otherwise the first populated kingdom's
	# first province. Good enough until the player can pick a home.
	var p: Province = WorldData.get_province("attica")
	if p != null:
		return p.id
	for k in WorldData.kingdoms.values():
		if k.owned_provinces.size() > 0:
			return String(k.owned_provinces[0])
	return ""


# --- Monthly tick ------------------------------------------------------------

func _on_month_passed(_y: int, _m: int) -> void:
	if entities.is_empty():
		return
	for e in entities.values():
		if e.dissolved:
			continue
		_tick_entity(e)


func _tick_entity(e: OwnedEntity) -> void:
	# 1. Corruption drift. Slow by default, faster if the proxy is
	# dead, if the entity sits in a low-fidelity kingdom, or if a
	# rival has a hand on it.
	var drift: float = CORRUPTION_DRIFT_PER_MONTH
	if _proxy_is_dead(e):
		drift += 0.3
	if e.home_kingdom != "" and Fidelity.is_low(e.home_kingdom):
		drift += 0.1
	if e.compromised:
		drift += 0.8
	e.corruption = clampi(e.corruption + int(ceil(drift)), 0, 100)

	# 2. Silver yield, less the skim taken by corruption.
	var yield_silver: int = e.monthly_yield_silver
	if e.corruption >= LOSS_WARN_THRESHOLD:
		yield_silver = 0
	elif e.corruption >= LEAK_WARN_THRESHOLD:
		yield_silver = int(round(yield_silver * (1.0 - CORRUPTION_SKIM_AT_LEAK)))
	if e.compromised:
		yield_silver = 0
	if yield_silver > 0:
		Purse.add(yield_silver)

	# 3. Visibility bumps. The tick adds a modest amount up to a
	# ceiling — entities are background infrastructure, not surveillance.
	if not e.compromised and e.corruption < LOSS_WARN_THRESHOLD and e.monthly_visibility_bump > 0:
		_bump_capped(e.home_kingdom, e.monthly_visibility_bump)
		if e.kind == OwnedEntity.Kind.TRADING_COMPANY:
			for kid in e.reach:
				_bump_capped(String(kid), max(1, e.monthly_visibility_bump / 2))
		elif e.kind == OwnedEntity.Kind.MONASTERY:
			# Monasteries hold steady visibility through everything —
			# a small but perpetual baseline that resists decay.
			_bump_capped(e.home_kingdom, 1)

	# 4. Loss / compromise transitions.
	if e.corruption >= LOSS_WARN_THRESHOLD and not e.compromised:
		_announce_loss(e, &"corruption")


func _bump_capped(kingdom_id: String, amount: int) -> void:
	if kingdom_id == "" or amount <= 0:
		return
	var current: int = Picture.score_for(kingdom_id)
	# Entities contribute up to VISIBILITY_CAP; beyond that operative
	# work is what moves the needle. Don't starve a richly-covered
	# kingdom, just stop adding to it.
	if current >= VISIBILITY_CAP:
		return
	var room: int = VISIBILITY_CAP - current
	Picture.bump_visibility(kingdom_id, min(amount, room), &"owned_entity")


func _announce_loss(e: OwnedEntity, reason: StringName) -> void:
	if _announced_lost.has(e.id):
		return
	_announced_lost[e.id] = true
	entity_lost.emit(e.id, reason)
	EventBus.public_event.emit({
		"kind":     &"entity_lost",
		"channel":  "operative",
		"headline": "We have lost control of %s" % e.display_name,
		"body":     "The books no longer close. The proxy's loyalty is somewhere else — or nowhere at all. %s continues to operate, but it no longer answers us." % e.display_name,
	})


func _proxy_is_dead(e: OwnedEntity) -> bool:
	if e.proxy_actor_id == &"":
		return false
	var a: Actor = Actors.get_actor(e.proxy_actor_id)
	return a == null or a.dead


# --- Defaults per kind -------------------------------------------------------

func _apply_kind_defaults(e: OwnedEntity) -> void:
	# The numbers are deliberately small so entities are never the
	# main source of anything — they're a dependable background.
	match e.kind:
		OwnedEntity.Kind.TRADING_COMPANY:
			e.monthly_yield_silver    = 18
			e.monthly_visibility_bump = 2
		OwnedEntity.Kind.ACADEMY:
			e.monthly_yield_silver    = 4
			e.monthly_visibility_bump = 3     # ideas travel
		OwnedEntity.Kind.MONASTERY:
			e.monthly_yield_silver    = 6
			e.monthly_visibility_bump = 2
		OwnedEntity.Kind.GUILD:
			e.monthly_yield_silver    = 10
			e.monthly_visibility_bump = 2
		OwnedEntity.Kind.ESTATE:
			e.monthly_yield_silver    = 14
			e.monthly_visibility_bump = 1


func _kingdom_for_province(pid: String) -> String:
	var p: Province = WorldData.get_province(pid)
	if p == null:
		return ""
	return p.owning_kingdom


# --- Save / load -------------------------------------------------------------

func snapshot() -> Dictionary:
	var arr: Array = []
	for e in entities.values():
		arr.append(e.to_dict())
	return {
		"entities":        arr,
		"_announced_lost": _announced_lost.duplicate(true),
	}


func restore(d: Dictionary) -> void:
	entities.clear()
	for entry in d.get("entities", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var e: OwnedEntity = OwnedEntity.from_dict(entry)
		if e.id == &"":
			continue
		entities[e.id] = e
	_announced_lost = (d.get("_announced_lost", {}) as Dictionary).duplicate(true)
