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
var operatives: Dictionary = {} # String operative_id -> Dictionary

const OP_LOG_MAX: int = 400

# §C2 internal-org tuning. Each coordinator handles at most this many
# operatives before we spawn a sibling coordinator. Lieutenants handle
# up to this many coordinators before a sibling lieutenant is created.
const _COORD_OP_CAP: int = 3
const _LT_COORD_CAP: int = 3
# Below this coverage value, a coordinator is considered "blown" — they
# get reassigned (new id, coverage reset, all operatives lose
# coordinator_id for the interval until re-linked). Mirrors the
# player-side strain mechanic.
const _COORD_REASSIGN_THRESHOLD: int = 20
const _LT_REASSIGN_THRESHOLD: int = 15

# Roster of flavour name fragments used to stamp a rival operative when
# one is seeded. Kept local — we never reveal these to the player
# before the sweep action resolves.
const _FIRST_NAMES: Array[String] = [
	"Hesiod", "Kallias", "Agathon", "Manius", "Drusa", "Hipponax",
	"Eumenes", "Lysias", "Nikias", "Thraso", "Orestes", "Phaidra",
	"Vibius", "Tanaquil", "Appia", "Numa", "Zenon", "Demetria",
]
const _TRADES: Array[String] = [
	"grain factor", "customs clerk", "copyist", "priest of minor office",
	"moneychanger", "harbourmaster's aide", "gatekeeper", "scribe",
	"physician", "horse trader", "caravan agent", "minor landlord",
]

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


## All rival operatives currently placed in a kingdom. Returns the
## raw state dicts — callers are expected to read, not mutate. Use
## `detect_operative`, `turn_operative`, `neutralize_operative`
## to change state so the audit trail stays in one place.
func operatives_in(kingdom_id: String, include_neutralized: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in operatives.values():
		if String(e.get("kingdom_id", "")) != kingdom_id:
			continue
		if not include_neutralized and bool(e.get("neutralized", false)):
			continue
		out.append(e)
	return out


func detected_operatives_in(kingdom_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in operatives_in(kingdom_id):
		if bool(e.get("detected", false)):
			out.append(e)
	return out


func undetected_operatives_in(kingdom_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in operatives_in(kingdom_id):
		if not bool(e.get("detected", false)):
			out.append(e)
	return out


## Flip the `detected` flag on one operative. Returns the operative
## (so the caller can render a detection report) or {} if no
## plausible candidate exists. Picks the hottest un-detected target,
## biased by the player's confirmation on the controlling society.
func detect_first_available(kingdom_id: String) -> Dictionary:
	var pool: Array[Dictionary] = undetected_operatives_in(kingdom_id)
	if pool.is_empty():
		return {}
	var best: Dictionary = {}
	var best_score: int = -1
	for e in pool:
		var sid: StringName = StringName(String(e.get("society_id", "")))
		@warning_ignore("integer_division")
		var score: int = int(e.get("heat", 0)) + Fingerprints.confirmation_for(sid) / 2
		if score > best_score:
			best_score = score
			best = e
	if best.is_empty():
		return {}
	best["detected"] = true
	return best


## Turn the first eligible (detected, not-turned, not-neutralized)
## operative in the kingdom. Returns the operative or {}. A turned
## operative acts as a slow intelligence drip on their controlling
## society (handled in _on_month_passed).
func turn_first_eligible(kingdom_id: String) -> Dictionary:
	for e in detected_operatives_in(kingdom_id):
		if bool(e.get("turned", false)) or bool(e.get("neutralized", false)):
			continue
		e["turned"] = true
		return e
	return {}


## Neutralise the first eligible (detected, not-neutralized) operative
## in the kingdom. Also docks the society's foothold there.
func neutralize_first_eligible(kingdom_id: String) -> Dictionary:
	for e in detected_operatives_in(kingdom_id):
		if bool(e.get("neutralized", false)):
			continue
		e["neutralized"] = true
		e["turned"] = false
		var sid: StringName = StringName(String(e.get("society_id", "")))
		var s: RivalSociety = get_society(sid)
		if s != null:
			s.bump_foothold(kingdom_id, -15)
			_dock_coordinator_on_burn(s, e, 30)
		return e
	return {}


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


## §8.13 false-flag. Forge an op in `kingdom_id` that reads, to any
## investigation, as having been authored by the named society. The
## forgery stays good unless someone (future mechanic) actively
## audits it as a fake — we mark the op with `false_flag_by_player`
## so that future unmasking has a hook. Returns the op dict on
## success, or an empty dict if the inputs were invalid.
func create_false_flag_op(society_id: StringName, kingdom_id: String) -> Dictionary:
	var s: RivalSociety = get_society(society_id)
	if s == null:
		return {}
	if WorldData.get_kingdom(kingdom_id) == null:
		return {}
	var method: StringName = _pick_method(s, kingdom_id)
	if method == &"":
		return {}
	var cover: Dictionary = METHOD_COVERS.get(method, {})
	var templates: Array = cover.get("templates", [])
	if templates.is_empty():
		return {}
	var headline: String = String(templates[_rng.randi_range(0, templates.size() - 1)]) % _kingdom_name(kingdom_id)
	var body: String = _body_for(s, method, kingdom_id)
	var op_id: String = "ff_%d_%s_%s" % [
		GameClock.absolute_day(),
		String(s.id),
		_rng.randi(),
	]
	var op: Dictionary = {
		"op_id":                op_id,
		"kind":                 cover.get("kind", &"misc"),
		"headline":             headline,
		"body":                 body,
		"kingdom_id":           kingdom_id,
		"abs_day":              GameClock.absolute_day(),
		"rival_signature":      String(s.id),
		"rival_method":         String(method),
		"rival_suspected":      true,
		# Hook for future unmasking. Nothing reads this today beyond
		# the forgery cell's own logs; fingerprint chain treats it as
		# a real op, which is the whole point of the mechanic.
		"false_flag_by_player": true,
	}
	op_log.append(op)
	if op_log.size() > OP_LOG_MAX:
		op_log = op_log.slice(op_log.size() - OP_LOG_MAX, op_log.size())
	s.ops_count += 1
	s.bump_foothold(kingdom_id, 5 if s.stronghold_kingdoms.has(kingdom_id) else 8)
	EventBus.public_event.emit(op)
	society_acted.emit(s.id, op)
	return op


## Find the highest-confirmation society the player can impersonate.
## Returns &"" if no society is at or above CONFIRMED (65). Biased
## toward societies that already have a foothold in the target
## kingdom: the forgery reads more plausibly where they are known.
func best_impersonation_target(kingdom_id: String) -> StringName:
	var best_sid: StringName = &""
	var best_score: int = -1
	for s in all_societies():
		var conf: int = Fingerprints.confirmation_for(s.id)
		if conf < 65:
			continue
		@warning_ignore("integer_division")
		var score: int = conf + (s.foothold_in(kingdom_id) / 4)
		if score > best_score:
			best_score = score
			best_sid = s.id
	return best_sid


# --- Monthly tick ----------------------------------------------------------

func _on_month_passed(_y: int, _m: int) -> void:
	if societies.is_empty():
		return
	for s in societies.values():
		_tick_society(s)
	_decay_inactive_footholds()
	_tick_turned_operatives()


## Turned operatives feed us a slow trickle of intelligence on their
## society and occasionally raise the fingerprint confirmation. They
## are also, per §5 and §14.6, running a risk of discovery — every
## month a turned op's controller rolls against them, and eventually
## they get burned by the other side.
func _tick_turned_operatives() -> void:
	for e in operatives.values():
		if not bool(e.get("turned", false)):
			continue
		if bool(e.get("neutralized", false)):
			continue
		var sid: StringName = StringName(String(e.get("society_id", "")))
		# Quiet intel drip. Caps out at 85 — final confirmation still
		# requires a library match.
		if Fingerprints.confirmation_for(sid) < 85:
			Fingerprints.bump_confirmation(sid, 3)
		# Discovery roll. Rises with heat; halved for strongholds
		# because their controller has more local eyes.
		var heat: int = int(e.get("heat", 0))
		var chance: float = 0.03 + float(heat) * 0.002
		var s: RivalSociety = get_society(sid)
		var kid: String = String(e.get("kingdom_id", ""))
		if s != null and s.stronghold_kingdoms.has(kid):
			chance *= 1.6
		if _rng.randf() < chance:
			e["neutralized"] = true
			e["turned"] = false
			# The player's exposure ticks because a scene was made.
			Exposure.bump(4.0, "double_agent_burned")
			var s2: RivalSociety = get_society(sid)
			if s2 != null:
				_dock_coordinator_on_burn(s2, e, 25)


func _tick_society(s: RivalSociety) -> void:
	var chance: float = TEMPO_MONTHLY_CHANCE.get(s.tempo, 0.2)
	# Strong societies are more visible because more arms are moving.
	var total: int = 0
	for v in s.footholds.values():
		total += int(v)
	if total > 200:
		chance *= 1.25
	# §5.5: a posthumous society (founder killed or never alive)
	# runs on mortal inheritance only. Tempo halves and it cannot
	# seed new operatives.
	if _is_posthumous(s):
		chance *= 0.5
	# §10.6 Aggressive-rivals modifier: doubles action frequency.
	chance *= DifficultyProfile.current().rival_action_frequency()
	if _rng.randf() > minf(chance, 0.99):
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

	# §C4 rival false-flag against the player. If this op fires in a
	# kingdom where the player has visible presence (a non-burned
	# coordinator), 10% chance the rival stamps the event with the
	# player's fingerprint. The in-world outcome: a public accusation
	# surfaces. The player can clear it with `investigate_anomaly`.
	# We flag the op (not the society) because the forgery is a single
	# act, not a standing doctrine.
	if _player_has_presence_in(kingdom_id) and _rng.randf() < 0.10:
		op["rival_false_flagged_player"] = true
		op["false_flag_cleared"] = false
		_emit_public_accusation_letter(s, kingdom_id)

	op_log.append(op)
	if op_log.size() > OP_LOG_MAX:
		op_log = op_log.slice(op_log.size() - OP_LOG_MAX, op_log.size())

	s.ops_count += 1
	s.bump_foothold(kingdom_id, 4 if s.stronghold_kingdoms.has(kingdom_id) else 6)

	# An active operation heats any placed operative by this society
	# in this kingdom (they were the ones carrying the silver). Heat
	# is what makes a sweep detect them.
	for op_entry in operatives.values():
		if String(op_entry.get("society_id", "")) == String(s.id) \
				and String(op_entry.get("kingdom_id", "")) == kingdom_id \
				and not bool(op_entry.get("neutralized", false)):
			op_entry["heat"] = mini(100, int(op_entry.get("heat", 0)) + 6)

	# Seed operatives on strong footholds. We keep the density low (a
	# kingdom with no operatives gets one; then one more per ~25 foothold)
	# because every operative is a detection surface for the player and
	# a memory cost for us.
	_maybe_seed_operative(s, kingdom_id)

	# §B9 institution↔institution: a society that has consolidated
	# a kingdom (>50 foothold) actively shoulders other societies
	# out of recruitment there. This creates the "turf" behaviour
	# the player sees when they try to triangulate between rivals.
	if s.foothold_in(kingdom_id) > 50:
		for other in societies.values():
			if String(other.id) == String(s.id):
				continue
			if other.foothold_in(kingdom_id) >= 30:
				InstRelations.block_in_province(String(s.id), String(other.id), kingdom_id)

	# Ops elsewhere marginally accelerate instability: the target
	# kingdom gets a small exposure-analogue bump we surface as unrest.
	EventBus.public_event.emit(op)
	society_acted.emit(s.id, op)


func _maybe_seed_operative(s: RivalSociety, kingdom_id: String) -> void:
	if s.foothold_in(kingdom_id) < 30:
		return
	# Posthumous societies cannot recruit new operatives: the founder
	# carried the induction mystery, and that mystery is gone.
	if _is_posthumous(s):
		return
	# §B9: if a rival society currently has this kingdom under turf
	# block, the would-be operative never gets inducted. The block
	# expires on its own timer (see InstRelations).
	if not InstRelations.blockers_of(String(s.id), kingdom_id).is_empty():
		return
	var already: int = 0
	for e in operatives.values():
		if String(e.get("society_id", "")) == String(s.id) \
				and String(e.get("kingdom_id", "")) == kingdom_id \
				and not bool(e.get("neutralized", false)):
			already += 1
	@warning_ignore("integer_division")
	var cap: int = 1 + (s.foothold_in(kingdom_id) / 30)
	if already >= cap:
		return
	# 35% chance per triggering op once under cap.
	if _rng.randf() > 0.35:
		return

	var id: String = "riv_%s_%s_%d" % [String(s.id), kingdom_id, GameClock.absolute_day()]
	var first: String = _FIRST_NAMES[_rng.randi_range(0, _FIRST_NAMES.size() - 1)]
	var trade: String = _TRADES[_rng.randi_range(0, _TRADES.size() - 1)]
	var coord_id: String = _ensure_coordinator_for(s, kingdom_id)
	var entry: Dictionary = {
		"id":             id,
		"name":           first,
		"cover_role":     trade,
		"society_id":     String(s.id),
		"kingdom_id":     kingdom_id,
		"detected":       false,
		"turned":         false,
		"neutralized":    false,
		"heat":           10,
		"placed_day":     GameClock.absolute_day(),
		# §C2 link back up the chain. Coordinators degrade when their
		# operatives burn; lieutenants degrade when their coordinators
		# get reassigned. This is the spine the investigation UI reads.
		"coordinator_id": coord_id,
	}
	operatives[id] = entry


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


func _body_for(s: RivalSociety, _method: StringName, kingdom_id: String) -> String:
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


## §5.5 gate: a society is posthumous when its founding immortal is
## not alive (dead, escaped counts as alive for these purposes since
## an escaped founder is still actively running the society).
func _is_posthumous(s: RivalSociety) -> bool:
	var im: OtherImmortal = Immortals.get_by_society(s.id)
	if im == null:
		return false
	return im.kill_state == OtherImmortal.KillState.POSTHUMOUS


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
	# §10.6 Aggressive-rivals: each society starts with one
	# pre-installed lieutenant in its first stronghold, so the
	# machine is already moving on turn 1.
	if DifficultyProfile.current().aggressive_rivals and not s.stronghold_kingdoms.is_empty():
		_spawn_lieutenant(s, s.stronghold_kingdoms[0])


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


# --- §C2 internal-org plumbing --------------------------------------------

## Find an existing coordinator for this society in this kingdom, or
## spawn one. When spawned, also ensures a lieutenant exists to parent
## it. Returns the coordinator id.
func _ensure_coordinator_for(s: RivalSociety, kingdom_id: String) -> String:
	# Prefer an under-capacity, still-active coordinator already in the
	# region. A coordinator is "active" if not explicitly blown.
	for k in s.org_coordinators.keys():
		var c: Dictionary = s.org_coordinators[k]
		if String(c.get("kingdom_id", "")) != kingdom_id:
			continue
		if int(c.get("coverage", 0)) <= _COORD_REASSIGN_THRESHOLD:
			continue
		var load_count: int = _coord_operative_count(s, String(c.get("id", "")))
		if load_count < _COORD_OP_CAP:
			return String(c.get("id", ""))
	return _spawn_coordinator(s, kingdom_id)


func _spawn_coordinator(s: RivalSociety, kingdom_id: String) -> String:
	var lt_id: String = _ensure_lieutenant_for(s, kingdom_id)
	var coord_id: String = "rco_%s_%s_%d_%d" % [
		String(s.id), kingdom_id, GameClock.absolute_day(), _rng.randi(),
	]
	s.org_coordinators[coord_id] = {
		"id":             coord_id,
		"parent_lt":      lt_id,
		"kingdom_id":     kingdom_id,
		"coverage":       70,
		"reassigned_day": 0,
	}
	return coord_id


## Find a lieutenant whose region already includes this kingdom; if
## none, try to append to an under-capacity lieutenant; else spawn a
## new lieutenant. Regions grow organically as the society pushes into
## new kingdoms.
func _ensure_lieutenant_for(s: RivalSociety, kingdom_id: String) -> String:
	for k in s.org_lieutenants.keys():
		var lt: Dictionary = s.org_lieutenants[k]
		if int(lt.get("coverage", 0)) <= _LT_REASSIGN_THRESHOLD:
			continue
		var kingdoms: Array = lt.get("kingdoms", [])
		if kingdoms.has(kingdom_id):
			return String(lt.get("id", ""))
	for k in s.org_lieutenants.keys():
		var lt2: Dictionary = s.org_lieutenants[k]
		if int(lt2.get("coverage", 0)) <= _LT_REASSIGN_THRESHOLD:
			continue
		var coord_count: int = _lt_coord_count(s, String(lt2.get("id", "")))
		if coord_count < _LT_COORD_CAP:
			var k_arr: Array = lt2.get("kingdoms", [])
			if not k_arr.has(kingdom_id):
				k_arr.append(kingdom_id)
				lt2["kingdoms"] = k_arr
			return String(lt2.get("id", ""))
	return _spawn_lieutenant(s, kingdom_id)


func _spawn_lieutenant(s: RivalSociety, kingdom_id: String) -> String:
	var lt_id: String = "rlt_%s_%d_%d" % [
		String(s.id), GameClock.absolute_day(), _rng.randi(),
	]
	s.org_lieutenants[lt_id] = {
		"id":             lt_id,
		"kingdoms":       [kingdom_id],
		"coverage":       80,
		"reassigned_day": 0,
	}
	return lt_id


func _coord_operative_count(s: RivalSociety, coord_id: String) -> int:
	var n: int = 0
	for e in operatives.values():
		if bool(e.get("neutralized", false)):
			continue
		if String(e.get("society_id", "")) != String(s.id):
			continue
		if String(e.get("coordinator_id", "")) == coord_id:
			n += 1
	return n


func _lt_coord_count(s: RivalSociety, lt_id: String) -> int:
	var n: int = 0
	for c in s.org_coordinators.values():
		if String(c.get("parent_lt", "")) == lt_id \
				and int(c.get("coverage", 0)) > _COORD_REASSIGN_THRESHOLD:
			n += 1
	return n


## When an operative burns, the coordinator takes a hit. If coverage
## falls below the reassign threshold, the coordinator is considered
## blown, gets reassigned (orphaning their operatives), and the
## lieutenant above them takes collateral damage. The player sees a
## letter only if they have enough confirmation on the society to
## have earned the insight.
func _dock_coordinator_on_burn(s: RivalSociety, op: Dictionary, delta: int) -> void:
	var coord_id: String = String(op.get("coordinator_id", ""))
	if coord_id == "":
		return
	var c: Dictionary = s.org_coordinators.get(coord_id, {})
	if c.is_empty():
		return
	var prev: int = int(c.get("coverage", 0))
	var next_v: int = maxi(0, prev - delta)
	c["coverage"] = next_v
	s.org_coordinators[coord_id] = c
	if prev > _COORD_REASSIGN_THRESHOLD and next_v <= _COORD_REASSIGN_THRESHOLD:
		_reassign_coordinator(s, c)


func _reassign_coordinator(s: RivalSociety, c: Dictionary) -> void:
	var coord_id: String = String(c.get("id", ""))
	var kid: String = String(c.get("kingdom_id", ""))
	c["reassigned_day"] = GameClock.absolute_day()
	s.org_coordinators[coord_id] = c
	# Orphan the operatives: they lose their handler and run hot until
	# a new coordinator re-links them (future operation ticks will
	# rewire via _ensure_coordinator_for).
	for e in operatives.values():
		if String(e.get("coordinator_id", "")) == coord_id:
			e["coordinator_id"] = ""
			e["heat"] = mini(100, int(e.get("heat", 0)) + 10)
	# Dock the lieutenant above — they're answerable for this.
	var lt_id: String = String(c.get("parent_lt", ""))
	if lt_id != "" and s.org_lieutenants.has(lt_id):
		var lt: Dictionary = s.org_lieutenants[lt_id]
		var lt_prev: int = int(lt.get("coverage", 0))
		var lt_next: int = maxi(0, lt_prev - 12)
		lt["coverage"] = lt_next
		s.org_lieutenants[lt_id] = lt
		if lt_prev > _LT_REASSIGN_THRESHOLD and lt_next <= _LT_REASSIGN_THRESHOLD:
			lt["reassigned_day"] = GameClock.absolute_day()
			s.org_lieutenants[lt_id] = lt
	# Surface a letter only if the player has enough confirmation on
	# the society. Otherwise the reassignment is silent — the world
	# doesn't report things the player can't yet perceive.
	if Fingerprints.confirmation_for(s.id) >= 50:
		_emit_coordinator_reassigned_letter(s, kid)


func _emit_coordinator_reassigned_letter(s: RivalSociety, kid: String) -> void:
	EventBus.public_event.emit({
		"kind":             &"rival_event",
		"kingdom_id":       kid,
		"headline":         "%s goes quiet in %s" % [s.display_name, _kingdom_name(kid)],
		"body": (
			"Their hand in %s has stilled. The market stall, the scribe "
			+ "at the harbour, the coin-changer who always had the right "
			+ "answer first — all three have stopped answering the same way. "
			+ "Someone up the chain has pulled them back. The network will "
			+ "re-thread in a season; it always does. But for a few months "
			+ "%s will be quieter than it was."
		) % [_kingdom_name(kid), _kingdom_name(kid)],
		"rival_signature": String(s.id),
		"news_tier":       &"FACTIONAL",
	})


func _player_has_presence_in(kingdom_id: String) -> bool:
	var c: OrgMember = Org.coverage_for(kingdom_id)
	return c != null and not c.burned


func _emit_public_accusation_letter(s: RivalSociety, kid: String) -> void:
	# The rival society's name is never visible in the body — the
	# attribution is always the player's to earn. Exposure bumps
	# because the accusation genuinely damages legend-adjacent cover.
	Exposure.bump(6.0, "public_false_flag_against_player")
	EventBus.public_event.emit({
		"kind":             &"rumour",
		"kingdom_id":       kid,
		"headline":         "Market-square gossip in %s points at your coordinator's name" % _kingdom_name(kid),
		"body": (
			"In %s, the authorship of the last strange thing has been "
			+ "decided in the markets before anyone official got to it. "
			+ "The name being spoken belongs to our coordinator in that "
			+ "city. I cannot find a single document that puts her in the "
			+ "place at the time, and yet three different merchants and a "
			+ "dockhand agree she was seen. The accusation will stand "
			+ "unless we walk the ground under it ourselves."
		) % _kingdom_name(kid),
		"rival_signature": String(s.id),
		"news_tier":       &"LOCAL",
	})


## Called by `investigate_anomaly` when the player pays to walk the
## ground under an accusation. Finds the most recent still-standing
## false-flag in this kingdom and clears it. Returns the op dict if
## one was cleared, or {} if none was available.
func clear_false_flag_in(kingdom_id: String) -> Dictionary:
	for i in range(op_log.size() - 1, -1, -1):
		var op: Dictionary = op_log[i]
		if String(op.get("kingdom_id", "")) != kingdom_id:
			continue
		if not bool(op.get("rival_false_flagged_player", false)):
			continue
		if bool(op.get("false_flag_cleared", false)):
			continue
		op["false_flag_cleared"] = true
		return op
	return {}


## Public accessor for the library view (§C3). Returns flat list of
## inferred lieutenants/coordinators/operatives under this society,
## filtered to only those the player has evidence for. Evidence rule:
## - operatives: must be `detected`;
## - coordinators: at least one detected operative under them OR
##                 confirmation ≥ 60 on the society;
## - lieutenants: at least one revealed coordinator under them OR
##                confirmation ≥ 80 on the society.
func inferred_chain_for(society_id: StringName) -> Dictionary:
	var s: RivalSociety = get_society(society_id)
	if s == null:
		return {}
	var conf: int = Fingerprints.confirmation_for(society_id)
	var out: Dictionary = {
		"society_id":   String(society_id),
		"lieutenants":  [],
		"coordinators": [],
		"operatives":   [],
	}
	# Operatives: the ones the player has actually caught.
	var visible_coord_ids: Dictionary = {}
	for e in operatives.values():
		if String(e.get("society_id", "")) != String(society_id):
			continue
		if not bool(e.get("detected", false)):
			continue
		out["operatives"].append(e.duplicate(true))
		var cid: String = String(e.get("coordinator_id", ""))
		if cid != "":
			visible_coord_ids[cid] = true
	# Coordinators.
	var visible_lt_ids: Dictionary = {}
	for c in s.org_coordinators.values():
		var cid2: String = String(c.get("id", ""))
		var via_operative: bool = visible_coord_ids.has(cid2)
		var via_confirmation: bool = conf >= 60
		if via_operative or via_confirmation:
			var copy: Dictionary = c.duplicate(true)
			copy["revealed_by"] = "evidence" if via_operative else "inferred"
			out["coordinators"].append(copy)
			var lt_id: String = String(c.get("parent_lt", ""))
			if lt_id != "":
				visible_lt_ids[lt_id] = true
	# Lieutenants.
	for lt in s.org_lieutenants.values():
		var lid: String = String(lt.get("id", ""))
		var via_coord: bool = visible_lt_ids.has(lid)
		var via_high_conf: bool = conf >= 80
		if via_coord or via_high_conf:
			var lt_copy: Dictionary = lt.duplicate(true)
			lt_copy["revealed_by"] = "evidence" if via_coord else "inferred"
			out["lieutenants"].append(lt_copy)
	return out


# --- Save / load ------------------------------------------------------------

func snapshot() -> Dictionary:
	var arr: Array = []
	for s in societies.values():
		arr.append(s.to_dict())
	return {
		"societies":  arr,
		"op_log":     op_log.duplicate(true),
		"operatives": operatives.duplicate(true),
		"seeded":     _seeded,
	}


func restore(d: Dictionary) -> void:
	societies.clear()
	op_log.clear()
	operatives.clear()
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
	var ops_v: Variant = d.get("operatives", {})
	if ops_v is Dictionary:
		for k in ops_v:
			operatives[String(k)] = (ops_v[k] as Dictionary).duplicate(true)
