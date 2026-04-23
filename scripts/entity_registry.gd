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
	DevLogger.write("Entities: ready")
	_rng.randomize()
	GameClock.month_passed.connect(_on_month_passed)
	GameClock.year_passed.connect(_on_year_passed)
	EventBus.actor_died.connect(_on_actor_died)
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
		home_province if home_province != "" else str(randi() % 100000),
	])
	e.display_name  = display_name
	e.kind          = kind
	e.home_province = home_province
	e.home_kingdom  = home_kingdom if home_kingdom != "" else _kingdom_for_province(home_province)
	e.founded_year  = founded_year if founded_year != 0 else -GameClock.year
	_apply_kind_defaults(e)
	_issue_papers(e)
	register(e)
	return e


## Found a banking-house-kind entity and wire it to a matching
## `BankingHouse` resource in `Finance`. Returns the entity; its
## `banking_house_id` field points at the newly-registered house.
## The pair is created atomically: a failure to create the backing
## house means no entity is registered.
func found_banking_house(
	display_name: String,
	home_province: String,
	home_kingdom: String = "",
	founded_year: int = 0,
	house_kind_label: String = "merchant consortium",
) -> OwnedEntity:
	var kid: String = home_kingdom if home_kingdom != "" else _kingdom_for_province(home_province)
	if kid == "":
		return null
	var house_id: StringName = StringName("house_%s_%d" % [kid, Time.get_ticks_msec() + int(randi() % 1000)])
	var h: BankingHouse = BankingHouse.new()
	h.id = house_id
	h.display_name = display_name
	h.home_kingdom = kid
	h.house_kind = house_kind_label
	h.capacity = 30
	h.max_capacity = 40
	h.monthly_regen_pct = 22
	h.discretion = 50
	h.reach = [kid]
	# Newly founded banking houses start without gold unless they
	# advertise bullion explicitly in their name.
	if house_kind_label == "silver-weighers' guild" or house_kind_label == "temple treasury":
		h.gold_max_capacity = 8
		h.gold_capacity = 6
	Finance.houses[h.id] = h
	Finance.house_added.emit(h)

	var e: OwnedEntity = found_entity(
		OwnedEntity.Kind.BANKING_HOUSE, display_name, home_province, kid, founded_year
	)
	e.banking_house_id = house_id
	entity_changed.emit(e.id)
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
	# Issue the starter consortium's papers pre-dated to its founding
	# so they don't ring new when inspected on turn one.
	_issue_papers(e)
	e.papers_founding_year = e.founded_year
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
	# rival has a hand on it. §B15 also folds in the director's
	# own traits: ambitious directors skim more, paranoid ones
	# clamp down.
	var drift: float = CORRUPTION_DRIFT_PER_MONTH
	if _proxy_is_dead(e):
		drift += 0.3
	if e.home_kingdom != "" and Fidelity.is_low(e.home_kingdom):
		drift += 0.1
	if e.compromised:
		drift += 0.8
	# A disrupted entity drifts faster: the new political masters
	# have no obligation to the old proxies, and corruption takes
	# the gap as an opportunity.
	if e.control_disrupted:
		drift += 0.4
	drift += _director_trait_drift(e)
	e.corruption = clampi(e.corruption + int(ceil(drift)), 0, 100)
	_maybe_emit_suspicious_dealings(e)

	# 2. Silver yield — only while control is live. A disrupted
	# entity keeps breathing, keeps archives, keeps contacts —
	# but pays the player nothing until a new proxy is seated.
	var yield_silver: int = e.monthly_yield_silver
	if e.control_disrupted:
		yield_silver = 0
	elif e.corruption >= LOSS_WARN_THRESHOLD:
		yield_silver = 0
	elif e.corruption >= LEAK_WARN_THRESHOLD:
		yield_silver = int(round(yield_silver * (1.0 - CORRUPTION_SKIM_AT_LEAK)))
	if e.compromised:
		yield_silver = 0
	# Institutional memory sweetens the pot for survivors — fat
	# old houses collect a few extra coins per month purely on
	# the strength of being older than the laws that regulate them.
	if yield_silver > 0 and e.institutional_memory >= OwnedEntity.MEMORY_BONUS_FLOOR:
		@warning_ignore("integer_division")
		var memory_bonus: int = clampi(e.institutional_memory / 20, 1, 12)
		yield_silver += memory_bonus
	if yield_silver > 0:
		Purse.add(yield_silver)

	# 3. Visibility bumps. The tick adds a modest amount up to a
	# ceiling — entities are background infrastructure, not surveillance.
	if e.control_live() and e.corruption < LOSS_WARN_THRESHOLD and e.monthly_visibility_bump > 0:
		_bump_capped(e.home_kingdom, e.monthly_visibility_bump)
		if e.kind == OwnedEntity.Kind.TRADING_COMPANY:
			for kid in e.reach:
				@warning_ignore("integer_division")
				var reach_bump: int = max(1, e.monthly_visibility_bump / 2)
				_bump_capped(String(kid), reach_bump)
		elif e.kind == OwnedEntity.Kind.MONASTERY:
			# Monasteries hold steady visibility through everything —
			# a small but perpetual baseline that resists decay.
			_bump_capped(e.home_kingdom, 1)
		# Old houses leak continent-wide low-grade intelligence
		# purely via correspondence.
		if e.institutional_memory >= OwnedEntity.MEMORY_BONUS_FLOOR:
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
	return a == null or not a.is_alive()


## §B15 per-entity trait-based corruption drift. The proxy's own
## personality shapes how much they skim. Ambition reads as greed
## (the kind that skims); paranoia reads as oversight (the kind
## that tightens the books). Net drift is small per month, but
## compounds over a decade.
func _director_trait_drift(e: OwnedEntity) -> float:
	if e.proxy_actor_id == &"":
		return 0.0
	var a: Actor = Actors.get_actor(e.proxy_actor_id)
	if a == null or not a.is_alive():
		return 0.0
	# Centre the traits around 50 and scale to a fraction of a
	# corruption point per month. Ambitious director (≥70): +0.3
	# to +0.5. Paranoid director (≥70): -0.2 to -0.4.
	var greed: float = maxf(0.0, float(a.ambition - 50)) / 50.0
	var oversight: float = maxf(0.0, float(a.paranoia - 50)) / 50.0
	return greed * 0.5 - oversight * 0.4


## §B15 Once an entity crosses the leak threshold, its proxy starts
## skimming noticeably. A low-frequency letter surfaces the fact —
## always naming the director so the player can decide whether to
## audit, replace, or burn them.
func _maybe_emit_suspicious_dealings(e: OwnedEntity) -> void:
	if e.corruption < OwnedEntity.CORRUPTION_LEAK_THRESHOLD:
		return
	if e.corruption >= OwnedEntity.CORRUPTION_LOSS_THRESHOLD:
		return
	# ~5% chance per month once leaking. One or two letters per year
	# on average — enough to feel like a live story, not a spam feed.
	if randf() > 0.05:
		return
	var director_phrase: String = "the proxy"
	if e.proxy_actor_id != &"":
		var a: Actor = Actors.get_actor(e.proxy_actor_id)
		if a != null:
			director_phrase = a.display_name()
	EventBus.public_event.emit({
		"kind":        &"entity_event",
		"kingdom_id":  e.home_kingdom,
		"entity_id":   String(e.id),
		"headline":    "Suspicious dealings in %s" % e.display_name,
		"body":        "The books of %s are no longer closing cleanly. A trusted set of eyes reports that %s has been taking a little extra off the top — far from enough to bring down the house, but far too much to pretend is a clerk's error. An audit would answer the question; a replacement would answer it louder." % [e.display_name, director_phrase],
	})


## §B15 Public entry point for the `audit_entity` action. Clamps the
## entity's corruption back to a healthy band at a silver cost the
## caller (ActionRunner) already accounted for. Returns true on
## success. Does nothing for already-dissolved or compromised
## entities.
func audit_entity(entity_id: StringName) -> bool:
	var e: OwnedEntity = entities.get(entity_id, null)
	if e == null or e.dissolved or e.compromised:
		return false
	var before: int = e.corruption
	e.corruption = maxi(0, e.corruption - 30)
	EventBus.public_event.emit({
		"kind":        &"entity_event",
		"kingdom_id":  e.home_kingdom,
		"entity_id":   String(e.id),
		"headline":    "Auditors walk the floor of %s" % e.display_name,
		"body":        "A quiet, thorough audit has closed in %s. %d points of drift have been pulled back; the proxy has been spoken to. The books are cleaner than they were last quarter, and the director knows what eyes are on them now." % [e.display_name, before - e.corruption],
	})
	return true


# --- Longevity (§20.4) -------------------------------------------------------

func _on_year_passed(_y: int) -> void:
	# Archives, contacts, contracts. One tick per game-year, up to
	# the per-entity cap.
	for e in entities.values():
		if e.dissolved:
			continue
		if e.institutional_memory < OwnedEntity.INSTITUTIONAL_MEMORY_CAP:
			e.institutional_memory += 1


## The ruler of an entity's home kingdom falling is the loudest
## signal we have that the political floor has shifted underneath
## it. The entity survives; the beneficial-control chain does not.
func _on_actor_died(actor_id: StringName, _was_host: bool, cause: StringName) -> void:
	for e in entities.values():
		if e.dissolved or e.control_disrupted:
			continue
		if e.home_kingdom == "":
			continue
		# If the dead actor was the ruler of the home kingdom,
		# the political floor moved — disrupt the entity.
		var dead_actor: Actor = Actors.get_actor(actor_id)
		if dead_actor != null and dead_actor.role == Actor.Role.RULER and dead_actor.kingdom_id == e.home_kingdom:
			_disrupt_control(e, StringName("regime_change_%s" % String(cause)))
			continue
		# If the dead actor *was* the entity's proxy, disrupt too.
		if e.proxy_actor_id != &"" and String(actor_id) == String(e.proxy_actor_id):
			_disrupt_control(e, &"proxy_died")


## Public hook — RivalRegistry / WorldAI can call this when a
## political upheaval flips an entity's home province (war,
## succession crisis, revolt). Idempotent.
func disrupt_control(entity_id: StringName, reason: StringName) -> void:
	var e: OwnedEntity = entities.get(entity_id, null)
	if e == null:
		return
	_disrupt_control(e, reason)


func _disrupt_control(e: OwnedEntity, reason: StringName) -> void:
	if e.control_disrupted or e.dissolved:
		return
	e.control_disrupted = true
	e.control_disrupted_reason = reason
	e.control_disrupted_year = -GameClock.year
	entity_changed.emit(e.id)
	_announce_disruption(e, reason)


## Re-establish beneficial control by seating a fresh proxy.
## Typical caller is the Ledger UI once the player commits to the
## work. Returns true if control has been restored.
func reestablish_control(entity_id: StringName, new_proxy_id: StringName) -> bool:
	var e: OwnedEntity = entities.get(entity_id, null)
	if e == null or not e.control_disrupted or e.dissolved:
		return false
	e.proxy_actor_id = new_proxy_id
	e.control_disrupted = false
	e.control_disrupted_reason = &""
	# Re-establishment does not erase the corruption that crept in
	# during the gap, but it does shake out the worst of it.
	e.corruption = maxi(0, e.corruption - 8)
	# Fresh charter, new nominal owner. The old paper trail is
	# invalidated the moment the succession completes.
	_refresh_papers(e)
	entity_changed.emit(e.id)
	_announce_reestablished(e)
	return true


func _announce_disruption(e: OwnedEntity, reason: StringName) -> void:
	var why: String = "a change at the top"
	match String(reason):
		"regime_change_natural":   why = "the succession in %s" % _kingdom_name_of(e.home_kingdom)
		"regime_change_violent":   why = "the fall of the old ruler in %s" % _kingdom_name_of(e.home_kingdom)
		"regime_change_old_age":   why = "the orderly succession in %s" % _kingdom_name_of(e.home_kingdom)
		"proxy_died":              why = "the death of their proxy"
		_:                         if String(reason).begins_with("regime_change_"):
			why = "a change at the top of %s" % _kingdom_name_of(e.home_kingdom)
	var date: GameDate = GameDate.today()
	var letter_id: StringName = StringName("entity_disrupt_%s_%d" % [String(e.id), Time.get_ticks_msec()])
	var body: String = (
		"%s has not stopped trading, teaching, or praying. But the old arrangements no longer hold — %s has knocked the chain of proxies loose. The books will not find your purse until a new proxy is seated. The archives are intact."
	) % [e.display_name, why]
	var letter: Letter = Letter.create(
		letter_id,
		OrgRoles.sender_line(OrgRoles.GO_BETWEEN, e.home_kingdom),
		date,
		"The house is still there, but not ours: %s" % e.display_name,
		body,
		&"operative"
	)
	EventBus.letter_delivered.emit(letter)


func _announce_reestablished(e: OwnedEntity) -> void:
	var date: GameDate = GameDate.today()
	var letter_id: StringName = StringName("entity_reclaim_%s_%d" % [String(e.id), Time.get_ticks_msec()])
	var body: String = (
		"A new proxy has been seated in %s. The books will close under our direction again by the next quarter. A portion of the corruption that accumulated during the interregnum has been swept out with the previous hand."
	) % e.display_name
	var letter: Letter = Letter.create(
		letter_id,
		OrgRoles.sender_line(OrgRoles.GO_BETWEEN, e.home_kingdom),
		date,
		"The house answers again: %s" % e.display_name,
		body,
		&"operative"
	)
	EventBus.letter_delivered.emit(letter)


func _kingdom_name_of(kid: String) -> String:
	var k: Kingdom = WorldData.get_kingdom(kid)
	return k.kingdom_name if k != null else kid


# --- Defaults per kind -------------------------------------------------------

# --- §20 paperwork ----------------------------------------------------------

const _PAPERS_GIVEN_NAMES: Array[String] = [
	"Mnesarkhos", "Euphronos", "Lysias", "Kallias", "Diomedon",
	"Timaios", "Hermodoros", "Theron", "Kleon", "Antigonos",
	"Eudamos", "Nikarchos", "Xenokrates", "Philokles", "Straton",
]

const _PAPERS_PATRONYMICS: Array[String] = [
	"son of Dion", "son of Eupeithes", "son of Theogenes",
	"son of Mnasippos", "son of Kritoboulos", "son of Polyainos",
	"son of Aristion", "daughter of Polydeukes",
	"daughter of Nausikrates", "daughter of Hegesippos",
]


## Assembles a plausible-looking cover owner and a short proxy
## chain for a newly founded entity. Kept in the registry, not the
## resource, so the RNG stays reproducible via `_rng`.
func _issue_papers(e: OwnedEntity) -> void:
	if e.nominal_owner_name != "":
		return
	var given: String = _PAPERS_GIVEN_NAMES[_rng.randi_range(0, _PAPERS_GIVEN_NAMES.size() - 1)]
	var patronym: String = _PAPERS_PATRONYMICS[_rng.randi_range(0, _PAPERS_PATRONYMICS.size() - 1)]
	e.nominal_owner_name = "%s %s" % [given, patronym]
	e.nominal_owner_role = _role_label_for_kind(e.kind)
	e.papers_founding_year = -GameClock.year
	e.proxy_chain = _fresh_proxy_chain(e)


func _fresh_proxy_chain(e: OwnedEntity) -> Array[StringName]:
	# A short chain of plausible intermediaries. The real ids the
	# registry tracks elsewhere; here we just want shape and depth.
	# Depth scales with kind: trading companies route money and so
	# tend to be more layered than a single rural estate.
	var depth: int = 2
	if e.kind == OwnedEntity.Kind.TRADING_COMPANY:
		depth = 3
	elif e.kind == OwnedEntity.Kind.ESTATE:
		depth = 1
	var out: Array[StringName] = []
	for i in range(depth):
		out.append(StringName("paper_%s_%d_%d" % [String(e.id), i, _rng.randi()]))
	return out


func _role_label_for_kind(k: OwnedEntity.Kind) -> String:
	match k:
		OwnedEntity.Kind.TRADING_COMPANY: return "shipper of record"
		OwnedEntity.Kind.ACADEMY:         return "principal sponsor"
		OwnedEntity.Kind.MONASTERY:       return "founding donor"
		OwnedEntity.Kind.GUILD:           return "master of the charter"
		OwnedEntity.Kind.ESTATE:          return "landholder of record"
	return "holder of record"


## Rewrites the paper trail. Called when a new proxy is seated and
## the registry wants the old charter replaced — long gaps in the
## books have to look like something.
func _refresh_papers(e: OwnedEntity) -> void:
	e.nominal_owner_name = ""
	e.nominal_owner_role = ""
	e.proxy_chain = []
	_issue_papers(e)


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
		OwnedEntity.Kind.BANKING_HOUSE:
			# A banking-house entity is a wrapper around a `BankingHouse`
			# resource; its silver flow comes from the underlying house
			# (capacity loans, IOUs) rather than a flat monthly yield.
			e.monthly_yield_silver    = 6
			e.monthly_visibility_bump = 2


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
	var al_raw: Variant = d.get("_announced_lost", {})
	_announced_lost = (al_raw as Dictionary).duplicate(true) if al_raw is Dictionary else {}
