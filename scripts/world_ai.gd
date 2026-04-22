extends Node
## Autoloaded as `WorldAI`. The quiet autonomous pulse of the world.
##
## On every month_passed tick this module rolls a small number of
## events for kingdoms and notable actors. Events are published via
## EventBus.public_event, so the Public News scroll (and anything else)
## can pick them up without WorldAI caring who's listening.
##
## Phase-0 scope (§13.1 "living world"):
##   - Ruler decrees (flavour, tied to ruler traits).
##   - Treasury crises for kingdoms in bad fiscal states.
##   - Rare war declarations between two random kingdoms.
##   - Natural deaths of aged actors.
##   - Assassination attempts when an heir burns to ambition.
##
## Everything is rolled off a deterministic seed so a save/load round
## trip reproduces the exact same rolls.

const BASE_DECREE_CHANCE:        float = 0.03   # per ruler per month
const WAR_DECLARATION_CHANCE:    float = 0.005  # per month (world-wide)
const TREASURY_CRISIS_CHANCE_BASE: float = 0.20  # scaled up by condition

# --- Coup rolls (§24.3 plot engine) ------------------------------------------
#
# A plotter is a living non-ruler whose role is close enough to the seat
# to take it, whose ambition has climbed past COUP_AMBITION_FLOOR, and
# whose loyalty has slipped below COUP_LOYALTY_CEILING. Drift (M31) can
# push a once-loyal general or advisor into that bracket over time.
# Per-month attempt chance scales with (ambition - loyalty) and, more
# surprisingly, the ruler's paranoia — a paranoid court is a tense
# court, and tense courts produce attempts. Success is a separate roll
# that runs when the attempt fires.
const COUP_AMBITION_FLOOR:  int   = 70
const COUP_LOYALTY_CEILING: int   = 50
const COUP_ROLES: Array[int]      = [
	Actor.Role.HEIR, Actor.Role.ADVISOR, Actor.Role.GENERAL,
]
const COUP_BASE_CHANCE:         float = 0.0025     # per qualified plotter / month
const COUP_WARN_CHANCE:         float = 0.12       # per qualified plotter / month
const COUP_WARN_COOLDOWN_MONTHS: int  = 4          # don't repeat a warning

# --- Host defection rolls (§5 fragility) -------------------------------------
#
# Someone who was once cultivated into a host (ever_host=true) but has
# since cooled can turn on the player. The "knife in the back" scenario:
# their ambition or a rival has flipped them, and they try to clear
# their name by burning yours. Triggers only when the relationship has
# gone openly hostile and their loyalty trait is already weak.
const DEFECT_RELATIONSHIP_CEILING: int = -20
const DEFECT_LOYALTY_CEILING:      int = 40
const DEFECT_BASE_CHANCE:          float = 0.015   # per qualified ex-host / month
const DEFECT_EXPOSURE_BUMP:        float = 20.0    # a clean denunciation hurts

const DEATH_BASE_AGE: int = 60                  # before this, no natural death roll
const DEATH_CURVE: float  = 0.0018              # (age - 60) * curve = monthly death chance

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# plotter_id -> GameClock.absolute_day when last warned. Prevents the
# scroll from re-announcing the same conspiracy every month for as long
# as the traits stay high.
var _plot_warning_last_day: Dictionary = {}

# --- Regency resolution tuning -----------------------------------------------
#
# A kingdom without a ruler stays in regency until a strongman takes
# the crown. We don't resolve immediately — factions need time to
# jockey. After REGENCY_GRACE_MONTHS a monthly roll fires, escalating
# with time, until a successor is installed. If no eligible actors
# exist at all, the regency simply persists (empty throne).
const REGENCY_GRACE_MONTHS: int   = 6
const REGENCY_BASE_CHANCE:  float = 0.06
const REGENCY_RAMP:         float = 0.02
const REGENCY_CAP:          float = 0.35

var _regency_months: Dictionary = {}   # kingdom_id -> months since regency began


func _ready() -> void:
	_rng.randomize()
	GameClock.month_passed.connect(_on_month_passed)


# --- Main tick ---------------------------------------------------------------

func _on_month_passed(_y: int, _m: int) -> void:
	if not WorldData.is_loaded():
		return

	_roll_ruler_decrees()
	_roll_treasury_crises()
	_roll_natural_deaths()
	_roll_assassination_attempts()
	_roll_host_defections()
	_roll_regency_resolutions()
	_roll_war_declaration()


# --- Event generators --------------------------------------------------------

func _roll_ruler_decrees() -> void:
	for k in WorldData.kingdoms.values():
		var ruler: Actor = Actors.ruler_of(k.id)
		if ruler == null:
			continue
		# Ambitious, pious, or paranoid rulers make noise more often.
		var personal_bonus: float = 0.0
		personal_bonus += max(0.0, (float(ruler.ambition) - 50.0) / 400.0)
		personal_bonus += max(0.0, (float(ruler.piety) - 50.0) / 500.0)
		personal_bonus += max(0.0, (float(ruler.paranoia) - 50.0) / 500.0)
		if _rng.randf() < (BASE_DECREE_CHANCE + personal_bonus):
			_emit_decree(ruler, k)


func _roll_treasury_crises() -> void:
	for k in WorldData.kingdoms.values():
		if k.treasury_condition == Kingdom.TreasuryCondition.FLUSH \
				or k.treasury_condition == Kingdom.TreasuryCondition.STABLE:
			continue
		var severity: float = 1.0
		match k.treasury_condition:
			Kingdom.TreasuryCondition.STRAINED: severity = 0.25
			Kingdom.TreasuryCondition.INDEBTED: severity = 0.60
			Kingdom.TreasuryCondition.BROKE:    severity = 1.00
		if _rng.randf() < TREASURY_CRISIS_CHANCE_BASE * severity:
			_emit_treasury_crisis(k)


func _roll_natural_deaths() -> void:
	for a in Actors.all_actors():
		if not a.is_alive():
			continue
		var age: int = a.age_in(GameClock.year)
		if age < DEATH_BASE_AGE:
			continue
		var chance: float = float(age - DEATH_BASE_AGE) * DEATH_CURVE
		# Resilience shrinks the tail a little — iron constitutions
		# don't make you immortal, but they move the needle.
		chance *= clampf(1.0 - (float(a.resilience) - 50.0) / 200.0, 0.4, 1.6)
		if _rng.randf() < chance:
			_kill_actor(a)


func _roll_assassination_attempts() -> void:
	for a in Actors.all_actors():
		if not a.is_alive():
			continue
		if not (a.role in COUP_ROLES):
			continue
		if a.ambition < COUP_AMBITION_FLOOR or a.loyalty > COUP_LOYALTY_CEILING:
			continue
		var ruler: Actor = Actors.ruler_of(a.kingdom_id)
		if ruler == null or not ruler.is_alive():
			continue

		# Tension scales with both plotter motivation and ruler paranoia.
		# An ambition-60/loyalty-30 general under a paranoid ruler plots
		# far more often than the same general under a stable one.
		var motive: float    = float(a.ambition - a.loyalty) / 100.0   # 0.2..2.0 range
		var pressure: float  = 1.0 + (float(ruler.paranoia) - 50.0) / 100.0
		pressure             = clampf(pressure, 0.6, 1.8)
		var chance: float    = COUP_BASE_CHANCE * motive * pressure

		# First: possible forewarning. The court's whispers reach the
		# player via the scroll before blood is drawn.
		_maybe_emit_plot_warning(a, ruler)

		# Then: the attempt roll itself.
		if _rng.randf() < chance:
			_emit_assassination_attempt(a, ruler)


## Occasionally emit a qualitative public dispatch indicating that a
## plot is being discussed in the background. This is pure flavor
## signaling: it does not advance or delay the attempt roll itself.
## A plotter is warned about once per COUP_WARN_COOLDOWN_MONTHS so the
## Public News scroll isn't flooded.
func _maybe_emit_plot_warning(plotter: Actor, ruler: Actor) -> void:
	var today: int = GameClock.absolute_day()
	var last: int  = int(_plot_warning_last_day.get(plotter.id, -99999))
	if today - last < COUP_WARN_COOLDOWN_MONTHS * 30:
		return
	if _rng.randf() >= COUP_WARN_CHANCE:
		return
	# Plot whispers in a court the player has no eyes on are useless
	# noise — and the host channel below couldn't fire there anyway.
	if Fidelity.is_low(plotter.kingdom_id):
		return
	_plot_warning_last_day[plotter.id] = today
	var k: Kingdom = WorldData.get_kingdom(plotter.kingdom_id)
	var kname: String = k.kingdom_name if k != null else plotter.kingdom_id
	var line: String
	if plotter.role == Actor.Role.GENERAL:
		line = "The garrison around %s keeps their own counsel. Orders that were once read out in the square are now delivered behind closed doors." % kname
	elif plotter.role == Actor.Role.ADVISOR:
		line = "The council of %s no longer laughs at the same jokes. %s and %s are no longer seen in the same rooms." % [
			kname, _actor_link(ruler), _actor_link(plotter),
		]
	else:
		line = "In the court of %s, attendants are noticing whom %s walks with — and whom they do not." % [
			kname, _actor_link(plotter),
		]
	_publish({
		"kind":       &"plot_brewing",
		"kingdom_id": plotter.kingdom_id,
		"actors":     [String(plotter.id), String(ruler.id)],
		"headline":   "A quiet thickens in the court of %s" % kname,
		"body":       line,
	})

	_maybe_deliver_host_plot_warning(plotter, ruler, kname)


## Private channel: if the player has a loyal host at this court, they
## receive an unambiguous letter naming the plotter — days, sometimes
## weeks, before any public dispatch would identify them. Each plot
## warning delivers at most one host letter; we pick the highest-
## relationship host available and let the others stay quiet.
func _maybe_deliver_host_plot_warning(plotter: Actor, ruler: Actor, kname: String) -> void:
	var candidates: Array[Actor] = Actors.hosts_in(plotter.kingdom_id)
	if candidates.is_empty():
		return
	# Don't let the plotter themself write the warning about themself.
	candidates = candidates.filter(func(h): return h.id != plotter.id and h.id != ruler.id)
	if candidates.is_empty():
		return
	candidates.sort_custom(func(x: Actor, y: Actor) -> bool: return x.relationship > y.relationship)
	var host: Actor = candidates[0]

	var plotter_link: String = _actor_link(plotter)
	var body: String = (
		"A matter you should know of before the scroll carries it.\n\n"
		+ "At %s the name on quiet lips is %s. I do not yet have the shape of the plan — who is in, who is merely listening — but the direction is unmistakable. They are measuring the crown.\n\n"
		+ "I will send more as I have it. If you mean to act, act before the court finds out that the court knows."
	) % [kname, plotter_link]

	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var letter_id: StringName = StringName(
		"host_plot_warning_%s_%d" % [String(plotter.id), Time.get_ticks_msec()]
	)
	var sender: String = "%s, at the court of %s" % [host.display_name(), kname]
	var letter: Letter = Letter.create(
		letter_id,
		sender,
		date,
		"A name in the wrong mouths",
		body,
		&"host"
	)
	EventBus.letter_delivered.emit(letter)


## Ex-hosts (ever_host=true) who've cooled into active hostility can
## decide, on any given month, to burn the player by denouncing them to
## their court. A single roll per qualified actor per month, gated by
## the `betrayed` latch so the same hand only stabs you once.
func _roll_host_defections() -> void:
	for a in Actors.all_actors():
		if not a.is_alive():
			continue
		if not a.ever_host:
			continue
		if a.betrayed:
			continue
		if a.is_host():
			# Still loyal. No defection to roll.
			continue
		if a.relationship > DEFECT_RELATIONSHIP_CEILING:
			continue
		if a.loyalty > DEFECT_LOYALTY_CEILING:
			continue

		# Chance scales with how far they've curdled and how little
		# loyalty they had to begin with. A -20 relationship / 40 loyalty
		# ex-host defects rarely; -80 / 10 defects often.
		var cold: float = float(DEFECT_RELATIONSHIP_CEILING - a.relationship) / 100.0
		cold = clampf(cold, 0.0, 1.2)
		var disloyalty: float = float(DEFECT_LOYALTY_CEILING - a.loyalty) / 50.0
		disloyalty = clampf(disloyalty, 0.0, 1.5)
		var chance: float = DEFECT_BASE_CHANCE * (1.0 + cold + disloyalty)

		if _rng.randf() < chance:
			_emit_host_defection(a)


func _emit_host_defection(a: Actor) -> void:
	a.betrayed = true
	# They can't harbour a grudge that could re-trigger this later: pin
	# the relationship to the floor so they fall out of every other
	# consideration (hosts list, dossier warmth, digest tracking).
	a.relationship = -100

	Exposure.bump(DEFECT_EXPOSURE_BUMP, "host_defected_" + String(a.id))

	var k: Kingdom = WorldData.get_kingdom(a.kingdom_id)
	var kname: String = k.kingdom_name if k != null else a.kingdom_id

	# Public dispatch — the court's version. They don't name the player
	# directly (no court would believe in an immortal patron); they
	# name a "foreign hand" or "unseen purse".
	_publish({
		"kind":       &"host_turned",
		"kingdom_id": a.kingdom_id,
		"actors":     [String(a.id)],
		"headline":   "A confession in the court of %s" % kname,
		"body":       "At %s, %s has gone to their ruler and named, in a written statement read aloud, a foreign purse that has been paying them for years. No names of consequence were given — none could be verified — but the court now knows, or thinks it knows, the shape of an influence that was here all along." % [
			kname, _actor_link(a),
		],
	})

	# Letter to the player — the go-between explains what just happened.
	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var letter_id: StringName = StringName("host_turned_%s_%d" % [String(a.id), Time.get_ticks_msec()])
	var body: String = (
		"It is %s. They went to the court themselves — not dragged, not pressed. "
		+ "They read out what they could remember of our arrangement. They did not have your name. They did not have a name at all. "
		+ "But they had enough, and they said it aloud, and a room full of dangerous people listened.\n\n"
		+ "Your exposure in that quarter has, in effect, risen. "
		+ "Assume for now that anyone who was close to them is now closer to whoever is looking for you.\n\n"
		+ "Do not send further work to that city for a season. Treat that name as burned."
	) % a.display_name()
	var letter: Letter = Letter.create(
		letter_id,
		"Your go-between",
		date,
		"A hand turned",
		body,
		&"host"
	)
	EventBus.letter_delivered.emit(letter)


func _roll_war_declaration() -> void:
	if _rng.randf() >= WAR_DECLARATION_CHANCE:
		return
	var ids: Array = WorldData.kingdoms.keys()
	if ids.size() < 2:
		return

	# Prefer pairs that are already hostile. This keeps wars from
	# appearing out of nowhere between serene partners most of the
	# time; a cold war can now escalate naturally.
	var hostile_pairs: Array = []
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: String = String(ids[i])
			var b: String = String(ids[j])
			var s: int = Relations.state_between(a, b)
			if s == int(Relations.RelationState.AT_WAR):
				continue
			if s == int(Relations.RelationState.HOSTILE):
				hostile_pairs.append([a, b])

	var a_id: String
	var b_id: String
	if not hostile_pairs.is_empty() and _rng.randf() < 0.75:
		var pair: Array = hostile_pairs[_rng.randi_range(0, hostile_pairs.size() - 1)]
		a_id = String(pair[0])
		b_id = String(pair[1])
	else:
		a_id = String(ids[_rng.randi_range(0, ids.size() - 1)])
		b_id = a_id
		var safety: int = 6
		while (b_id == a_id or Relations.state_between(a_id, b_id) == int(Relations.RelationState.AT_WAR)) and safety > 0:
			b_id = String(ids[_rng.randi_range(0, ids.size() - 1)])
			safety -= 1
		if a_id == b_id:
			return

	_emit_war_declaration(a_id, b_id)


# --- Event authors -----------------------------------------------------------

func _emit_decree(ruler: Actor, k: Kingdom) -> void:
	# Court flavour from a kingdom we have no eyes on is noise — let
	# the ruler issue their decree, just don't spam the scroll with it
	# (§9.6 low-fidelity AI).
	if Fidelity.is_low(k.id):
		return
	var decrees_bank: Array[String] = [
		"orders a new census of able-bodied men",
		"commands a sacrifice on the grand altar",
		"raises the salt tax by a tenth",
		"forbids the wearing of purple in the provinces",
		"grants remission of debts for the coming year",
		"summons the council of notables to the capital",
		"names a new commander of the royal guard",
		"prohibits the import of foreign cloth",
		"declares a day of fasting",
		"orders the walls of the capital reinforced",
	]
	var line: String = decrees_bank[_rng.randi_range(0, decrees_bank.size() - 1)]
	_publish({
		"kind":       &"ruler_decree",
		"kingdom_id": k.id,
		"actors":     [String(ruler.id)],
		"headline":   "%s decrees a new order in %s" % [ruler.given_name, k.kingdom_name],
		"body":       "From the court of %s. %s %s." % [
			k.kingdom_name, _actor_link(ruler), line,
		],
	})


func _emit_treasury_crisis(k: Kingdom) -> void:
	var phrases: Array[String] = [
		"Creditors are heard to speak openly of unpaid interest.",
		"The royal mint has been quiet for weeks.",
		"A regiment's pay is said to be three months late.",
		"A bazaar-master has refused the kingdom's paper and demanded bullion.",
		"Temples are turning away supplicants who bring only promise, not coin.",
	]
	var line: String = phrases[_rng.randi_range(0, phrases.size() - 1)]
	_publish({
		"kind":       &"treasury_crisis",
		"kingdom_id": k.id,
		"actors":     [],
		"headline":   "The coffers of %s strain" % k.kingdom_name,
		"body":       "Trouble in %s. %s" % [k.kingdom_name, line],
	})


func _kill_actor(a: Actor) -> void:
	# GameClock.year is already negative for BCE; Actor.death_year uses
	# the same convention (matches birth_year).
	# Capture host status BEFORE setting death_year, since is_host()
	# short-circuits on is_alive().
	var was_host: bool = a.is_host()
	a.death_year = GameClock.year
	var title: String = TraitCues.role_title(a.role).to_lower()
	# Rulers and dead hosts always make the scroll, regardless of
	# coverage — a king's death is structural and a turned host is
	# the player's own intelligence. Other deaths in low-fidelity
	# kingdoms stay quiet.
	var announce: bool = (
		a.role == Actor.Role.RULER
		or was_host
		or Fidelity.is_high(a.kingdom_id)
	)
	if announce:
		_publish({
			"kind":       &"death",
			"kingdom_id": a.kingdom_id,
			"actors":     [String(a.id)],
			"headline":   "%s is no more" % a.given_name,
			"body":       "Word has travelled from %s. %s, %s, is dead. The manner of it was, as they say, unremarkable: age, at length, comes for all." % [
				_kingdom_name(a.kingdom_id), _actor_link(a), title,
			],
		})
	EventBus.actor_died.emit(a.id, was_host, &"age")
	if a.role == Actor.Role.RULER:
		_handle_succession(a)


func _emit_assassination_attempt(heir: Actor, ruler: Actor) -> void:
	# Base 35% tilts with the plotter's intellect (planning) and the
	# ruler's paranoia (vigilance). An intellect-80 general against a
	# paranoia-30 ruler lands clean far more often than the reverse.
	var intellect_bias: float = (float(heir.intellect) - 50.0) / 200.0   # ±0.25
	var paranoia_bias:  float = (float(ruler.paranoia) - 50.0) / 200.0   # ±0.25
	var chance: float = clampf(0.35 + intellect_bias - paranoia_bias, 0.10, 0.75)
	var success: bool = _rng.randf() < chance
	if success:
		var ruler_was_host: bool = ruler.is_host()
		ruler.death_year = GameClock.year
		# Self-inflicted succession: the heir takes the throne directly,
		# bypassing the regency/ambition lottery. Promote in place before
		# the dispatch so the roster read in the scroll is already true.
		var prior_role_int: int = int(heir.role)
		heir.role = Actor.Role.RULER
		Actors.schedule_replacement(heir.kingdom_id, prior_role_int)
		_publish({
			"kind":       &"assassination",
			"kingdom_id": ruler.kingdom_id,
			"actors":     [String(ruler.id), String(heir.id)],
			"headline":   "%s is slain in the palace" % ruler.given_name,
			"body":       "At %s, the ruler %s was found cold this morning. Within a day, %s has claimed the seat. The court denies all coincidence. No one believes them." % [
				_kingdom_name(ruler.kingdom_id), _actor_link(ruler), _actor_link(heir),
			],
		})
		EventBus.actor_died.emit(ruler.id, ruler_was_host, &"assassination")
	else:
		# A foiled palace blade in a kingdom the player can't see is
		# rumour, not record. Don't promote it to the scroll.
		if Fidelity.is_low(ruler.kingdom_id):
			return
		_publish({
			"kind":       &"assassination_attempt",
			"kingdom_id": ruler.kingdom_id,
			"actors":     [String(ruler.id), String(heir.id)],
			"headline":   "A blade drawn against %s" % ruler.given_name,
			"body":       "A man with a knife was taken in the halls of %s. %s is said to be untouched; suspicion, as always in such matters, reaches toward %s. Nothing is said aloud." % [
				_kingdom_name(ruler.kingdom_id), _actor_link(ruler), _actor_link(heir),
			],
		})


## Walk each kingdom currently in regency. After a grace period, roll
## a rising chance that a strongman emerges and takes the crown by
## whatever mix of pressure and deal-making the council can no
## longer resist. The installed ruler is whoever sits highest in the
## successor pool right now — which may be an actor who wasn't alive
## or wasn't eligible when the regency began.
func _roll_regency_resolutions() -> void:
	for k in WorldData.kingdoms.values():
		if not k.in_regency:
			continue
		var months: int = int(_regency_months.get(k.id, 0)) + 1
		_regency_months[k.id] = months
		if months < REGENCY_GRACE_MONTHS:
			continue
		var chance: float = clampf(
			REGENCY_BASE_CHANCE + REGENCY_RAMP * float(months - REGENCY_GRACE_MONTHS),
			REGENCY_BASE_CHANCE,
			REGENCY_CAP,
		)
		if _rng.randf() >= chance:
			continue
		_resolve_regency(k)


func _resolve_regency(k: Kingdom) -> void:
	var pools: Array = [
		[Actor.Role.HEIR],
		[Actor.Role.ADVISOR, Actor.Role.GENERAL],
		[Actor.Role.PRIEST, Actor.Role.MERCHANT, Actor.Role.PHILOSOPHER, Actor.Role.COMMONER],
	]
	var successor: Actor = null
	for pool in pools:
		successor = _pick_successor(k.id, pool)
		if successor != null:
			break
	if successor == null:
		return   # still nobody; keep the throne empty

	var prior_role: String = TraitCues.role_title(successor.role).to_lower()
	var prior_role_int: int = int(successor.role)
	successor.role = Actor.Role.RULER
	k.in_regency = false
	_regency_months.erase(k.id)
	Actors.schedule_replacement(k.id, prior_role_int)
	_publish({
		"kind":       &"succession",
		"kingdom_id": k.id,
		"actors":     [String(successor.id)],
		"headline":   "%s takes the empty throne of %s" % [successor.given_name, k.kingdom_name],
		"body":       "The regency in %s has broken. The %s %s has been raised to the crown — by council decree in the record, by force in the room. The other claimants have either sworn allegiance or stopped being a problem." % [
			k.kingdom_name, prior_role, _actor_link(successor),
		],
	})


## A ruler has died. Find the most plausible successor already on the
## roster and promote them; if nothing fits, leave the seat empty and
## mark it as a regency in the public dispatch.
func _handle_succession(dead_ruler: Actor) -> void:
	var kid: String = dead_ruler.kingdom_id
	var k: Kingdom = WorldData.get_kingdom(kid)
	if k == null:
		return

	# Preferred pool: living, non-ruler actors in the same kingdom.
	# HEIR beats ADVISOR beats GENERAL beats anyone else. Within a
	# tier, pick the most ambitious — the one who wanted it most.
	var pools: Array = [
		[Actor.Role.HEIR],
		[Actor.Role.ADVISOR, Actor.Role.GENERAL],
		[Actor.Role.PRIEST, Actor.Role.MERCHANT, Actor.Role.PHILOSOPHER, Actor.Role.COMMONER],
	]
	var successor: Actor = null
	for pool in pools:
		successor = _pick_successor(kid, pool)
		if successor != null:
			break

	if successor == null:
		k.in_regency = true
		_regency_months[kid] = 0
		_publish({
			"kind":       &"regency",
			"kingdom_id": kid,
			"actors":     [String(dead_ruler.id)],
			"headline":   "A regency is declared in %s" % k.kingdom_name,
			"body":       "No heir was named or survives. The council of %s governs in its own name while the crown remains empty. This will hold until it does not." % k.kingdom_name,
		})
		return

	var prior_role: String = TraitCues.role_title(successor.role).to_lower()
	var prior_role_int: int = int(successor.role)
	successor.role = Actor.Role.RULER
	k.in_regency = false
	_regency_months.erase(kid)
	Actors.schedule_replacement(kid, prior_role_int)
	_publish({
		"kind":       &"succession",
		"kingdom_id": kid,
		"actors":     [String(dead_ruler.id), String(successor.id)],
		"headline":   "%s takes the seat in %s" % [successor.given_name, k.kingdom_name],
		"body":       "With the death of %s, the %s %s has been raised to the throne of %s. The oaths are not yet dry. Every nearby court is composing the first letter of the new era." % [
			_actor_link(dead_ruler), prior_role, _actor_link(successor), k.kingdom_name,
		],
	})


func _pick_successor(kingdom_id: String, roles: Array) -> Actor:
	var best: Actor = null
	for a in Actors.actors_in_kingdom(kingdom_id):
		if not a.is_alive():
			continue
		if a.role == Actor.Role.RULER:
			continue
		if not (a.role in roles):
			continue
		if best == null or a.ambition > best.ambition:
			best = a
	return best


func _emit_war_declaration(a_id: String, b_id: String) -> void:
	var a: Kingdom = WorldData.get_kingdom(a_id)
	var b: Kingdom = WorldData.get_kingdom(b_id)
	if a == null or b == null:
		return
	Relations.set_at_war(a_id, b_id)
	_publish({
		"kind":       &"war_declaration",
		"kingdom_id": a.id,
		"actors":     [],
		"headline":   "%s declares war upon %s" % [a.kingdom_name, b.kingdom_name],
		"body":       "Envoys have crossed the border bearing the formal demand, and returned with nothing. By next season, columns of men will be moving. Every crown nearby is now choosing a side, whether they admit it or not.",
	})


# --- Helpers -----------------------------------------------------------------

func _publish(event: Dictionary) -> void:
	event["abs_day"] = GameClock.absolute_day()
	EventBus.public_event.emit(event)


func _actor_link(a: Actor) -> String:
	if a == null:
		return ""
	return "[url=actor:%s][b]%s[/b][/url]" % [String(a.id), a.display_name()]


func _kingdom_name(id: String) -> String:
	var k: Kingdom = WorldData.get_kingdom(id)
	return k.kingdom_name if k != null else id


# --- Public plot API ---------------------------------------------------------

## Return the plotter in `kingdom_id` with the highest current
## (ambition - loyalty) whose role is among COUP_ROLES. Used by the
## "quiet_plot" action to figure out whom to talk down. Returns null if
## no qualified plotter exists.
func top_plotter_in(kingdom_id: String) -> Actor:
	var best: Actor = null
	var best_score: int = -9999
	for a in Actors.actors_in_kingdom(kingdom_id):
		if not a.is_alive():
			continue
		if not (a.role in COUP_ROLES):
			continue
		if a.ambition < COUP_AMBITION_FLOOR or a.loyalty > COUP_LOYALTY_CEILING:
			continue
		var score: int = a.ambition - a.loyalty
		if score > best_score:
			best_score = score
			best = a
	return best


## Cool a specific plotter off. Pulls ambition down and loyalty up just
## far enough to put them outside the COUP_ROLES bracket, so the monthly
## coup roll will skip them until traits drift back. Also clears any
## active warning cooldown, so if they do drift back a fresh warning
## will fire instead of being suppressed.
func cool_plotter(actor_id: StringName) -> void:
	var a: Actor = Actors.get_actor(actor_id)
	if a == null:
		return
	a.ambition = clampi(a.ambition - 15, 0, 100)
	a.loyalty  = clampi(a.loyalty + 15, 0, 100)
	_plot_warning_last_day.erase(a.id)
