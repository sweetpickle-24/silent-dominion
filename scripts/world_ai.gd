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
const ASSASSINATION_CHANCE:      float = 0.004  # per ambitious heir per month
const TREASURY_CRISIS_CHANCE_BASE: float = 0.20  # scaled up by condition

const DEATH_BASE_AGE: int = 60                  # before this, no natural death roll
const DEATH_CURVE: float  = 0.0018              # (age - 60) * curve = monthly death chance

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


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
		if a.role != Actor.Role.HEIR:
			continue
		if a.ambition < 75 or a.loyalty > 45:
			continue
		if _rng.randf() < ASSASSINATION_CHANCE:
			var ruler: Actor = Actors.ruler_of(a.kingdom_id)
			if ruler != null and ruler.is_alive():
				_emit_assassination_attempt(a, ruler)


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
	a.death_year = GameClock.year
	var title: String = TraitCues.role_title(a.role).to_lower()
	_publish({
		"kind":       &"death",
		"kingdom_id": a.kingdom_id,
		"actors":     [String(a.id)],
		"headline":   "%s is no more" % a.given_name,
		"body":       "Word has travelled from %s. %s, %s, is dead. The manner of it was, as they say, unremarkable: age, at length, comes for all." % [
			_kingdom_name(a.kingdom_id), _actor_link(a), title,
		],
	})
	if a.role == Actor.Role.RULER:
		_handle_succession(a)


func _emit_assassination_attempt(heir: Actor, ruler: Actor) -> void:
	var success: bool = _rng.randf() < 0.35
	if success:
		ruler.death_year = GameClock.year
		# Self-inflicted succession: the heir takes the throne directly,
		# bypassing the regency/ambition lottery. Promote in place before
		# the dispatch so the roster read in the scroll is already true.
		heir.role = Actor.Role.RULER
		_publish({
			"kind":       &"assassination",
			"kingdom_id": ruler.kingdom_id,
			"actors":     [String(ruler.id), String(heir.id)],
			"headline":   "%s is slain in the palace" % ruler.given_name,
			"body":       "At %s, the ruler %s was found cold this morning. Within a day, %s has claimed the seat. The court denies all coincidence. No one believes them." % [
				_kingdom_name(ruler.kingdom_id), _actor_link(ruler), _actor_link(heir),
			],
		})
	else:
		_publish({
			"kind":       &"assassination_attempt",
			"kingdom_id": ruler.kingdom_id,
			"actors":     [String(ruler.id), String(heir.id)],
			"headline":   "A blade drawn against %s" % ruler.given_name,
			"body":       "A man with a knife was taken in the halls of %s. %s is said to be untouched; suspicion, as always in such matters, reaches toward %s. Nothing is said aloud." % [
				_kingdom_name(ruler.kingdom_id), _actor_link(ruler), _actor_link(heir),
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
		_publish({
			"kind":       &"regency",
			"kingdom_id": kid,
			"actors":     [String(dead_ruler.id)],
			"headline":   "A regency is declared in %s" % k.kingdom_name,
			"body":       "No heir was named or survives. The council of %s governs in its own name while the crown remains empty. This will hold until it does not." % k.kingdom_name,
		})
		return

	var prior_role: String = TraitCues.role_title(successor.role).to_lower()
	successor.role = Actor.Role.RULER
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
