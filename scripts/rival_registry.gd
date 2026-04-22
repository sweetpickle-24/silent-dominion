extends Node
## Autoloaded as `Rivals`. Owns the RivalSociety instances and the
## monthly AI tick that produces their operations per §5 and §8.12.
##
## Rival operations are expressed as public news events with a hidden
## `rival_signature` key (the society id) plus a `rival_method` tag.
## Those keys are invisible to normal UI renders — the player only
## surfaces them through the fingerprint investigation chain (m8).
##
## Design tenets:
##   - Simulation-only. Never emits a signal the UI binds to directly.
##   - Cheap. Monthly tick is O(societies × kingdoms) in the worst case.
##   - Fingerprintable. Every op carries enough metadata for §8.12 to
##     later reconstruct who did it.

signal society_acted(society_id: StringName, op: Dictionary)

const PYRE_METHODS: Array[StringName] = [
	&"accelerate_collapse", &"fan_unrest", &"burn_granaries", &"undermine_legitimacy",
]
const ARCHITECT_METHODS: Array[StringName] = [
	&"consolidate_succession", &"strengthen_bureaucracy", &"suppress_dissent", &"reinforce_orthodoxy",
]
const WEAVER_METHODS: Array[StringName] = [
	&"arrange_marriage", &"engineer_heir", &"break_rival_line", &"bury_bastard",
]
const VEIL_METHODS: Array[StringName] = [
	&"shelter_scholar", &"quietly_copy_library", &"protect_heretic", &"suppress_book_burning",
]
const COMPACT_METHODS: Array[StringName] = [
	&"fund_underdog", &"balance_power", &"stall_conqueror", &"leak_to_rival",
]

# Cover stories per method. Each entry is a small dictionary: the
# public-event `kind` to tag the news with (ruler_decree, famine,
# etc.), plus a list of headline templates. Templates use `%s` for
# the kingdom's display name so the prose reads local.
const METHOD_COVERS: Dictionary = {
	&"accelerate_collapse": {
		"kind":     &"unrest",
		"templates": [
			"Grain shortage bites in %s",
			"Bread riots in the lower quarters of %s",
			"A tax officer is killed in %s, and no one claims the deed",
		],
	},
	&"fan_unrest": {
		"kind":     &"unrest",
		"templates": [
			"Factional brawling in %s refuses to die down",
			"Another strike of the dockhands in %s",
		],
	},
	&"burn_granaries": {
		"kind":     &"unrest",
		"templates": [
			"A granary fire in %s takes half the winter stores",
			"In %s, the public silos were found empty at audit",
		],
	},
	&"undermine_legitimacy": {
		"kind":     &"rumour",
		"templates": [
			"A persistent rumour in %s says the ruler is not the son of their father",
			"Pamphlets in %s mock the court in verses no one admits to writing",
		],
	},
	&"consolidate_succession": {
		"kind":     &"ruler_decree",
		"templates": [
			"%s names a new chancellor with unusually broad writ",
			"In %s, the succession is formally fixed in favour of the elder son",
		],
	},
	&"strengthen_bureaucracy": {
		"kind":     &"ruler_decree",
		"templates": [
			"%s announces a new register of every household in the capital",
			"A new revenue office opens in %s, staffed entirely from outside the city",
		],
	},
	&"suppress_dissent": {
		"kind":     &"ruler_decree",
		"templates": [
			"%s bans three named philosophers from the public square",
			"In %s, the old opposition families are quietly relieved of their estates",
		],
	},
	&"reinforce_orthodoxy": {
		"kind":     &"religion",
		"templates": [
			"The senior priests of %s issue a joint ruling on the new cult",
			"In %s, the old rites are restored by decree",
		],
	},
	&"arrange_marriage": {
		"kind":     &"dynasty",
		"templates": [
			"A betrothal is announced between the houses of %s",
			"The heir of %s is quietly promised to a cousin of no great wealth but of very careful ancestry",
		],
	},
	&"engineer_heir": {
		"kind":     &"dynasty",
		"templates": [
			"A surprise pregnancy at the court of %s",
			"In %s, a forgotten cousin is suddenly produced as the closest surviving claimant",
		],
	},
	&"break_rival_line": {
		"kind":     &"dynasty",
		"templates": [
			"A minor prince of %s dies of a fever no one had heard of last week",
			"In %s, the bride-to-be of the heir dies in a riding accident",
		],
	},
	&"bury_bastard": {
		"kind":     &"dynasty",
		"templates": [
			"A woman of %s disappears from the court records between two seasons",
			"In %s, a quietly-raised child is sent abroad with no stated reason",
		],
	},
	&"shelter_scholar": {
		"kind":     &"misc",
		"templates": [
			"A foreign philosopher takes up quiet residence at the academy of %s",
			"An exiled astronomer is given a stipend and a roof in %s, and no one explains by whom",
		],
	},
	&"quietly_copy_library": {
		"kind":     &"misc",
		"templates": [
			"A copyist shop opens outside the walls of %s, taking only older commissions",
			"The scribes of %s are busy on a project the temple will not describe",
		],
	},
	&"protect_heretic": {
		"kind":     &"religion",
		"templates": [
			"A heresiarch thought arrested in %s is reported teaching again, in a different courtyard",
			"In %s, the names of the condemned are struck from the record mid-trial",
		],
	},
	&"suppress_book_burning": {
		"kind":     &"misc",
		"templates": [
			"A scheduled burning in %s is cancelled without explanation",
			"In %s, the library's banned shelf is found full again the morning after the inspection",
		],
	},
	&"fund_underdog": {
		"kind":     &"war",
		"templates": [
			"A weaker neighbour of %s has suddenly fielded a better army than last season",
			"Mercenaries have appeared in the service of the smaller side in %s's border quarrel",
		],
	},
	&"balance_power": {
		"kind":     &"diplomacy",
		"templates": [
			"A surprise alliance is sealed against %s by three of its lesser neighbours",
			"%s finds its debts called in, all in the same week, by three separate houses",
		],
	},
	&"stall_conqueror": {
		"kind":     &"war",
		"templates": [
			"A campaign by %s is broken before the season by a logistics failure no quartermaster owns",
			"The auxiliaries of %s arrive a month late and without the horses they were promised",
		],
	},
	&"leak_to_rival": {
		"kind":     &"rumour",
		"templates": [
			"The war plans of %s turn up, with perfect accuracy, on the table of their enemy",
			"A dispatch out of %s is read by a foreign chancellor before it is read by its addressee",
		],
	},
}

# Tempo → monthly chance an individual society acts (0..1). Multiplied
# by a crude intensity factor at tick-time so that busy months look
# busy and quiet months stay quiet.
const TEMPO_MONTHLY_CHANCE: Dictionary = {
	RivalSociety.Tempo.SLOW:         0.08,
	RivalSociety.Tempo.REACTIVE:     0.25,
	RivalSociety.Tempo.GENERATIONAL: 0.10,
	RivalSociety.Tempo.STEADY:       0.20,
	RivalSociety.Tempo.CONSTANT:     0.45,
}

var societies: Dictionary = {}  # StringName id -> RivalSociety
var op_log: Array = []          # Dictionaries of past ops (capped)

const OP_LOG_MAX: int = 400

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seeded: bool = false


func _ready() -> void:
	_rng.randomize()
	# Societies seed only after the world is on disk — we need the
	# kingdom ids to resolve strongholds.
	if WorldData.is_loaded():
		_maybe_seed()
	else:
		WorldData.world_loaded.connect(_maybe_seed, CONNECT_ONE_SHOT)
	GameClock.month_passed.connect(_on_month_passed)


# --- Public: queries -------------------------------------------------------

func all_societies() -> Array[RivalSociety]:
	var out: Array[RivalSociety] = []
	for s in societies.values():
		out.append(s)
	return out


func get_society(id: StringName) -> RivalSociety:
	return societies.get(id)


## Total hidden footprint of all rival societies in a kingdom. Used by
## the fingerprint chain to bias Level 0 "anomaly" detection toward
## regions where something is genuinely happening.
func total_foothold_in(kingdom_id: String) -> int:
	var n: int = 0
	for s in societies.values():
		n += s.foothold_in(kingdom_id)
	return n


## Recent ops in a kingdom. The fingerprint chain will walk this list
## to build a pattern view when the player cross-references.
func recent_ops_in(kingdom_id: String, lookback_days: int = 720) -> Array:
	var cutoff: int = GameClock.absolute_day() - lookback_days
	var out: Array = []
	for op in op_log:
		if int(op.get("abs_day", 0)) < cutoff:
			continue
		if String(op.get("kingdom_id", "")) == kingdom_id:
			out.append(op)
	return out


# --- Monthly tick ----------------------------------------------------------

func _on_month_passed(_y: int, _m: int) -> void:
	if societies.is_empty():
		return
	for s in societies.values():
		_tick_society(s)
	_decay_inactive_footholds()


func _tick_society(s: RivalSociety) -> void:
	var chance: float = TEMPO_MONTHLY_CHANCE.get(s.tempo, 0.2)
	# Strong societies are more visible because more arms are moving.
	var total: int = 0
	for v in s.footholds.values():
		total += int(v)
	if total > 200:
		chance *= 1.25
	if _rng.randf() > chance:
		return

	var kid: String = _pick_operating_region(s)
	if kid.is_empty():
		return
	_run_operation(s, kid)


func _run_operation(s: RivalSociety, kingdom_id: String) -> void:
	var method: StringName = _pick_method(s, kingdom_id)
	if method == &"":
		return
	var cover: Dictionary = METHOD_COVERS.get(method, {})
	var templates: Array = cover.get("templates", [])
	if templates.is_empty():
		return

	var headline: String = String(templates[_rng.randi_range(0, templates.size() - 1)]) % _kingdom_name(kingdom_id)
	var body: String = _body_for(s, method, kingdom_id)

	var op_id: String = "op_%d_%s_%s" % [
		GameClock.absolute_day(),
		String(s.id),
		_rng.randi(),
	]
	var op: Dictionary = {
		"op_id":             op_id,
		"kind":              cover.get("kind", &"misc"),
		"headline":          headline,
		"body":              body,
		"kingdom_id":        kingdom_id,
		"abs_day":           GameClock.absolute_day(),
		# Hidden metadata. The fingerprint chain unlocks these
		# progressively — a bare public-news render never surfaces them.
		"rival_signature":   String(s.id),
		"rival_method":      String(method),
		# The player's current investigation level on this op. 0 means
		# "they saw the headline and nothing more." Raised by the
		# Fingerprints singleton as actions resolve.
		"rival_suspected":   true,
	}

	op_log.append(op)
	if op_log.size() > OP_LOG_MAX:
		op_log = op_log.slice(op_log.size() - OP_LOG_MAX, op_log.size())

	s.ops_count += 1
	s.bump_foothold(kingdom_id, 4 if s.stronghold_kingdoms.has(kingdom_id) else 6)

	# Ops elsewhere marginally accelerate instability: the target
	# kingdom gets a small exposure-analogue bump we surface as unrest.
	EventBus.public_event.emit(op)
	society_acted.emit(s.id, op)


# --- Internals: operation selection ---------------------------------------

func _pick_operating_region(s: RivalSociety) -> String:
	# Primary: strongholds (always eligible). Secondary: any kingdom
	# where the society already has some foothold. Tertiary: one
	# random neighbouring kingdom to model expansion pressure.
	var candidates: Array[Dictionary] = []
	for kid in s.stronghold_kingdoms:
		if WorldData.get_kingdom(kid) != null:
			candidates.append({"kid": kid, "weight": 50 + s.foothold_in(kid)})
	for kid in s.footholds.keys():
		var fh: int = s.foothold_in(String(kid))
		if fh <= 0 or s.stronghold_kingdoms.has(String(kid)):
			continue
		candidates.append({"kid": String(kid), "weight": maxi(10, fh)})
	# Expansion: one random kingdom not yet touched.
	var fresh: Array[String] = []
	for kid in WorldData.kingdoms.keys():
		var kid_s: String = String(kid)
		if s.footholds.has(kid_s) or s.stronghold_kingdoms.has(kid_s):
			continue
		fresh.append(kid_s)
	if not fresh.is_empty():
		candidates.append({
			"kid":    fresh[_rng.randi_range(0, fresh.size() - 1)],
			"weight": 15,
		})

	if candidates.is_empty():
		return ""
	var total: int = 0
	for c in candidates:
		total += int(c.weight)
	var pick: int = _rng.randi_range(1, total)
	var running: int = 0
	for c in candidates:
		running += int(c.weight)
		if pick <= running:
			return String(c.kid)
	return String(candidates[0].kid)


func _pick_method(s: RivalSociety, _kingdom_id: String) -> StringName:
	if s.preferred_methods.is_empty():
		return &""
	# Weighted pick: earlier methods in the list are more characteristic.
	var weights: Array[int] = []
	var running: int = 0
	for i in range(s.preferred_methods.size()):
		var w: int = maxi(1, s.preferred_methods.size() - i)
		weights.append(w)
		running += w
	var pick: int = _rng.randi_range(1, running)
	var acc: int = 0
	for i in range(weights.size()):
		acc += weights[i]
		if pick <= acc:
			return s.preferred_methods[i]
	return s.preferred_methods[0]


func _body_for(s: RivalSociety, method: StringName, kingdom_id: String) -> String:
	# Note: we deliberately do not name the society in the body. The
	# attribution is the prize of the fingerprint chain; it must not
	# appear on a plain news read.
	var region: String = _kingdom_name(kingdom_id)
	var prefix: String = ""
	match s.tempo:
		RivalSociety.Tempo.SLOW:         prefix = "A long-arranged piece of business in "
		RivalSociety.Tempo.REACTIVE:     prefix = "Something moves quickly in "
		RivalSociety.Tempo.GENERATIONAL: prefix = "A matter of households and inheritance in "
		RivalSociety.Tempo.STEADY:       prefix = "Another small correction in "
		RivalSociety.Tempo.CONSTANT:     prefix = "More quiet weather in "
	return (
		prefix + region + " has fallen out the way someone wanted it to. "
		+ "There is no obvious beneficiary. Whoever shaped the moment "
		+ "had reason enough to keep their name off every document."
	)


# --- Internals: foothold upkeep --------------------------------------------

func _decay_inactive_footholds() -> void:
	for s in societies.values():
		var keys: Array = s.footholds.keys().duplicate()
		for kid in keys:
			var kid_s: String = String(kid)
			var prev: int = s.foothold_in(kid_s)
			if prev <= 0:
				continue
			# Strongholds: soft regen toward 60. Elsewhere: -1 per month.
			if s.stronghold_kingdoms.has(kid_s):
				if prev < 60:
					s.footholds[kid_s] = prev + 1
			else:
				s.footholds[kid_s] = maxi(0, prev - 1)
				if s.footholds[kid_s] == 0:
					s.footholds.erase(kid_s)


func _kingdom_name(kid: String) -> String:
	var k: Kingdom = WorldData.get_kingdom(kid)
	return k.kingdom_name if k != null else kid


# --- Seeding ---------------------------------------------------------------

func _maybe_seed() -> void:
	if _seeded:
		return
	# Skip seeding if a save has already populated us.
	if not societies.is_empty():
		_seeded = true
		return
	_seed_default_societies()
	_seeded = true


func _seed_default_societies() -> void:
	_add_society(_make_architects())
	_add_society(_make_pyre())
	_add_society(_make_weavers())
	_add_society(_make_veil())
	_add_society(_make_compact())


func _add_society(s: RivalSociety) -> void:
	societies[s.id] = s
	# Prime footholds in strongholds so they aren't inert on month 1.
	for kid in s.stronghold_kingdoms:
		s.footholds[kid] = 55 + _rng.randi_range(0, 15)


func _make_architects() -> RivalSociety:
	var s: RivalSociety = RivalSociety.new()
	s.id = &"architects"
	s.display_name = "The Architects"
	s.philosophy = "Total civilisational order; a perfected hierarchy."
	s.network_shape = RivalSociety.NetworkShape.HIERARCHICAL
	s.tempo = RivalSociety.Tempo.SLOW
	s.preferred_methods = ARCHITECT_METHODS
	s.stronghold_kingdoms = _filter_existing(["persia", "egypt"])
	return s


func _make_pyre() -> RivalSociety:
	var s: RivalSociety = RivalSociety.new()
	s.id = &"pyre"
	s.display_name = "The Pyre"
	s.philosophy = "Collapse and rebirth; only destruction purifies."
	s.network_shape = RivalSociety.NetworkShape.CELLULAR
	s.tempo = RivalSociety.Tempo.REACTIVE
	s.preferred_methods = PYRE_METHODS
	s.stronghold_kingdoms = _filter_existing(["thrace", "macedon", "illyria"])
	return s


func _make_weavers() -> RivalSociety:
	var s: RivalSociety = RivalSociety.new()
	s.id = &"weavers"
	s.display_name = "The Weavers"
	s.philosophy = "Preserve specific bloodlines as vessels of legitimate power."
	s.network_shape = RivalSociety.NetworkShape.FAMILY
	s.tempo = RivalSociety.Tempo.GENERATIONAL
	s.preferred_methods = WEAVER_METHODS
	s.stronghold_kingdoms = _filter_existing(["sparta", "persia", "carthage"])
	return s


func _make_veil() -> RivalSociety:
	var s: RivalSociety = RivalSociety.new()
	s.id = &"veil"
	s.display_name = "The Veil"
	s.philosophy = "Protect and accumulate knowledge above all else."
	s.network_shape = RivalSociety.NetworkShape.DISTRIBUTED
	s.tempo = RivalSociety.Tempo.STEADY
	s.preferred_methods = VEIL_METHODS
	s.stronghold_kingdoms = _filter_existing(["athens", "corinth", "egypt"])
	return s


func _make_compact() -> RivalSociety:
	var s: RivalSociety = RivalSociety.new()
	s.id = &"compact"
	s.display_name = "The Compact"
	s.philosophy = "Controlled, sustainable power; no single actor should dominate."
	s.network_shape = RivalSociety.NetworkShape.DIFFUSE
	s.tempo = RivalSociety.Tempo.CONSTANT
	s.preferred_methods = COMPACT_METHODS
	s.stronghold_kingdoms = _filter_existing(["corinth", "syracuse", "massalia", "rome"])
	return s


func _filter_existing(ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id in ids:
		if WorldData.get_kingdom(String(id)) != null:
			out.append(String(id))
	return out


# --- Save / load ------------------------------------------------------------

func snapshot() -> Dictionary:
	var arr: Array = []
	for s in societies.values():
		arr.append(s.to_dict())
	return {
		"societies": arr,
		"op_log":    op_log.duplicate(true),
		"seeded":    _seeded,
	}


func restore(d: Dictionary) -> void:
	societies.clear()
	op_log.clear()
	_seeded = bool(d.get("seeded", false))
	var arr: Variant = d.get("societies", [])
	if arr is Array:
		for sd in arr:
			if sd is Dictionary:
				var s: RivalSociety = RivalSociety.from_dict(sd)
				if s.id != &"":
					societies[s.id] = s
	var log_arr: Variant = d.get("op_log", [])
	if log_arr is Array:
		for entry in log_arr:
			if entry is Dictionary:
				op_log.append(entry.duplicate(true))
