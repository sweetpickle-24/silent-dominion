extends Node
## Autoloaded as `Actors`. Central registry of every living (and dead)
## character in the simulation.
##
## Loaded from `res://data/actors_500bce.json` at startup. Runtime mutations
## (death, recruitment, trait drift) happen in-place; persistence is the
## responsibility of the save system, not this singleton.

const ACTOR_DATA_PATH: String = "res://data/actors_500bce.json"

# id (StringName) -> Actor
var actors: Dictionary = {}

# Convenience indices rebuilt by `_rebuild_indices()` whenever the roster
# changes. Keys are the grouping field; values are Array[StringName] of ids.
var _by_kingdom: Dictionary = {}
var _by_province: Dictionary = {}
var _by_role: Dictionary = {}


## Monthly drift toward 0 applied to every actor's relationship score.
## Without neglect-pressure the player can "bank" cultivated warmth
## forever; one point per month means a full success (+12) buys roughly
## a year of grace before it has fully faded.
const RELATIONSHIP_MONTHLY_DECAY: int = 1

## Scheduler task kind for delayed roster replacements. The delay is
## cosmetic — we don't want a dead general replaced the same day, it
## feels instant. Resolved in `_on_task_due`.
const REPLACE_TASK_KIND: StringName = &"actor_replace"

## How soon a dead or promoted actor's seat is filled, in days. A
## short spread so the player hears about a new face in the next
## public dispatch cycle.
const REPLACE_DELAY_MIN_DAYS: int = 45
const REPLACE_DELAY_MAX_DAYS: int = 150

## Culture-adjacent given-name banks per kingdom. Used when we have
## to generate a fresh actor and there is no same-kingdom exemplar
## to riff on. Short banks on purpose: repetition is fine, the game
## spans centuries.
const NAME_BANKS: Dictionary = {
	"athens":       ["Philon", "Demetrios", "Lysander", "Kleon", "Theron", "Nikias", "Iphikrates"],
	"sparta":       ["Leotychidas", "Pausanias", "Archidamos", "Aristodemos", "Kleomenes", "Agesilaos"],
	"corinth":      ["Periander", "Timoleon", "Xenophanes", "Kypselos", "Diokles"],
	"macedon":      ["Amyntas", "Perdikkas", "Alketas", "Philippos", "Menelaos"],
	"persia":       ["Hystaspes", "Artabanus", "Megabyzus", "Masistes", "Ariabignes"],
	"egypt":        ["Nekhtnebef", "Psamtik", "Amasis", "Wahibre", "Udjahorresnet"],
	"carthage":     ["Hanno", "Mago", "Bomilcar", "Hasdrubal", "Gisco", "Himilco"],
	"rome":         ["Lucius", "Marcus", "Titus", "Quintus", "Servius", "Aulus", "Gnaeus"],
	"etruria":      ["Vel", "Arnth", "Larth", "Aule", "Avle", "Thanchvil"],
}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_load_from_json(ACTOR_DATA_PATH)
	_rebuild_indices()
	print("[Actors] Loaded %d actors from %s" % [actors.size(), ACTOR_DATA_PATH])

	GameClock.month_passed.connect(_on_month_passed)
	EventBus.actor_died.connect(_on_actor_died)
	Scheduler.task_due.connect(_on_task_due)


## Emitted elsewhere (WorldAI). If the deceased was above the host
## threshold we owe the player a letter explaining that the network
## has lost a hand, because `_announce_host_lost` is otherwise only
## triggered by relationship drift.
func _on_actor_died(actor_id: StringName, was_host: bool, _cause: StringName) -> void:
	var a: Actor = get_actor(actor_id)
	if a == null:
		return
	if was_host:
		_announce_host_lost_by_death(a)
	# Rulers get replaced through the explicit succession machinery in
	# WorldAI. Every other role — advisor, general, heir, priest,
	# merchant, philosopher — leaves a seat the court will quietly fill.
	# Schedule a replacement instead of spawning instantly so the new
	# face arrives a season or two later, not the same day.
	if a.role != Actor.Role.RULER:
		_schedule_replacement(a.kingdom_id, int(a.role))


func _on_month_passed(_y: int, _m: int) -> void:
	# Pull every relationship one step closer to 0. Neutral actors are
	# untouched. This is the "out of sight, out of mind" drift.
	for a in actors.values():
		if a.relationship > 0:
			a.relationship = maxi(0, a.relationship - RELATIONSHIP_MONTHLY_DECAY)
		elif a.relationship < 0:
			a.relationship = mini(0, a.relationship + RELATIONSHIP_MONTHLY_DECAY)


# --- Public API --------------------------------------------------------------

func get_actor(id: StringName) -> Actor:
	return actors.get(id, null)


func all_actors() -> Array[Actor]:
	var out: Array[Actor] = []
	for a in actors.values():
		out.append(a)
	return out


func actors_in_kingdom(kingdom_id: String) -> Array[Actor]:
	return _collect(_by_kingdom.get(kingdom_id, []))


func actors_in_province(province_id: String) -> Array[Actor]:
	return _collect(_by_province.get(province_id, []))


func actors_by_role(role: Actor.Role) -> Array[Actor]:
	return _collect(_by_role.get(role, []))


func ruler_of(kingdom_id: String) -> Actor:
	for a in actors_in_kingdom(kingdom_id):
		if a.role == Actor.Role.RULER and a.is_alive():
			return a
	return null


## Every living non-ruler actor whose relationship has crossed the
## HOST_THRESHOLD. The §5 "stable of hosts" for the player — the only
## actors through whom high-intervention actions can currently travel.
func hosts() -> Array[Actor]:
	var out: Array[Actor] = []
	for a in actors.values():
		if a.is_host():
			out.append(a)
	return out


## Loyal hosts currently at the court of a given kingdom. Empty if the
## player has no one placed there. Used by WorldAI to route private
## early warnings (plots, intrigues) through the host channel before
## they break in public.
func hosts_in(kingdom_id: String) -> Array[Actor]:
	var out: Array[Actor] = []
	for a in actors.values():
		if a.kingdom_id == kingdom_id and a.is_host():
			out.append(a)
	return out


func add_actor(a: Actor) -> void:
	actors[a.id] = a
	_rebuild_indices()


## Shift an actor's relationship toward the player by `delta`, clamped
## to [-100, +100]. Returns the new value (or 0 if the actor is unknown).
##
## When the shift crosses the HOST_THRESHOLD upward (or back under it
## downward) this also publishes an inbox letter and a public-dispatch
## note, so the player gets explicit feedback on the §5 transition.
func adjust_relationship(id: StringName, delta: int) -> int:
	var a: Actor = get_actor(id)
	if a == null:
		return 0
	var was_host: bool = a.is_host()
	a.relationship = clampi(a.relationship + delta, -100, 100)
	var now_host: bool = a.is_host()
	if now_host and not was_host:
		a.ever_host = true
		_announce_host_won(a)
	elif was_host and not now_host:
		_announce_host_lost(a)
	return a.relationship


func _announce_host_won(a: Actor) -> void:
	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var letter_id: StringName = StringName("host_won_%s_%d" % [String(a.id), Time.get_ticks_msec()])
	var body: String = (
		"I write this once, and not again. What passed between us these last months was not business; it was a choice, and I have made it. When you send word, I will act. Do not make me regret it.\n\nYours in the work,\n%s"
	) % a.display_name()
	var letter: Letter = Letter.create(
		letter_id,
		a.display_name(),
		date,
		"A letter, in their own hand",
		body,
		&"host"
	)
	EventBus.letter_delivered.emit(letter)
	# Soft public trace too — most hosts don't advertise, but the
	# scroll is the player's second memory.
	EventBus.public_event.emit({
		"kind":       &"host_won",
		"kingdom_id": a.kingdom_id,
		"actors":     [String(a.id)],
		"headline":   "A friend won in %s" % _kingdom_name_for(a.kingdom_id),
		"body":       "Not a matter for the markets. Noted here only so you do not forget the season in which [url=actor:%s][b]%s[/b][/url] first said yes." % [String(a.id), a.display_name()],
	})


func _announce_host_lost_by_death(a: Actor) -> void:
	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var letter_id: StringName = StringName("host_dead_%s_%d" % [String(a.id), Time.get_ticks_msec()])
	var body: String = (
		"%s is gone. Whatever %s was arranging for you goes with them. I have quietly taken the ledger page on that name out of our working papers. The arrangement is at its end; not by a falling out, but by a falling. Treat it as such." 
	) % [a.display_name(), "they"]
	var letter: Letter = Letter.create(
		letter_id,
		"Your go-between",
		date,
		"A name falls from the list",
		body,
		&"host"
	)
	EventBus.letter_delivered.emit(letter)


func _announce_host_lost(a: Actor) -> void:
	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var letter_id: StringName = StringName("host_lost_%s_%d" % [String(a.id), Time.get_ticks_msec()])
	var body: String = (
		"%s can no longer be counted among your hands. They have cooled, or been cooled, and what was arranged with them is arranged no longer. Treat them as any other name on the table now — not an enemy, but not yours." 
	) % a.display_name()
	var letter: Letter = Letter.create(
		letter_id,
		"Your go-between",
		date,
		"A name falls from the list",
		body,
		&"host"
	)
	EventBus.letter_delivered.emit(letter)


func _kingdom_name_for(kid: String) -> String:
	var k: Kingdom = WorldData.get_kingdom(kid)
	return k.kingdom_name if k != null else kid


# --- Roster replenishment ----------------------------------------------------

## Schedule a same-role replacement for a given kingdom. Called by
## _on_actor_died for non-rulers and by WorldAI whenever a promotion
## empties a lower seat (heir -> ruler, advisor -> ruler, etc.).
## Delay is randomised so a noisy month of court deaths does not all
## fill on the same calendar day.
func schedule_replacement(kingdom_id: String, role: int) -> void:
	_schedule_replacement(kingdom_id, role)


func _schedule_replacement(kingdom_id: String, role: int) -> void:
	if kingdom_id.is_empty():
		return
	if role == int(Actor.Role.RULER) or role == int(Actor.Role.AGENT):
		return
	var delay: int = _rng.randi_range(REPLACE_DELAY_MIN_DAYS, REPLACE_DELAY_MAX_DAYS)
	Scheduler.schedule_task_in_days(delay, {
		"kind":        String(REPLACE_TASK_KIND),
		"kingdom_id":  kingdom_id,
		"role":        role,
	})


func _on_task_due(descriptor: Dictionary) -> void:
	if String(descriptor.get("kind", "")) != String(REPLACE_TASK_KIND):
		return
	var kid: String = String(descriptor.get("kingdom_id", ""))
	var role: int = int(descriptor.get("role", Actor.Role.COMMONER))
	# If someone already filled the seat since the death — say the
	# regency threw up a new advisor or the player cultivated someone
	# into the role — don't stack another one.
	if _role_already_filled(kid, role):
		return
	spawn_actor(kid, role, &"replacement")


## Fill an arbitrary kingdom+role with a freshly generated actor and
## return them. Traits centre on 50 with ±20 noise; age is drawn
## from a plausible band per role. The actor is indexed immediately
## so downstream queries (ruler_of, hosts_in, actors_by_role) pick
## them up this tick.
func spawn_actor(kingdom_id: String, role: int, _reason: StringName = &"generated") -> Actor:
	var a: Actor = Actor.new()
	var now_year: int = -GameClock.year
	a.id          = StringName(_generate_id(kingdom_id, role))
	a.given_name  = _generate_given_name(kingdom_id)
	a.epithet     = ""
	a.birth_year  = now_year - _generate_age_for_role(role)
	a.death_year  = 0
	a.role        = role as Actor.Role
	a.kingdom_id  = kingdom_id
	a.province_id = _default_province(kingdom_id)
	_randomise_traits(a, role)
	a.relationship = 0
	add_actor(a)
	return a


func _role_already_filled(kingdom_id: String, role: int) -> bool:
	# For roles the simulation cares about (HEIR, ADVISOR, GENERAL),
	# a single fresh occupant is enough to mark the seat filled. For
	# ambient roles (PRIEST, MERCHANT, PHILOSOPHER, COMMONER) we want
	# a small bench, so never consider them "full" — the timer fires
	# a replacement regardless.
	var structural: Array[int] = [
		int(Actor.Role.HEIR), int(Actor.Role.ADVISOR), int(Actor.Role.GENERAL),
	]
	if not structural.has(role):
		return false
	for a in actors_in_kingdom(kingdom_id):
		if a.is_alive() and int(a.role) == role:
			return true
	return false


func _generate_id(kingdom_id: String, role: int) -> String:
	var role_tag: String = Actor.Role.keys()[role].to_lower()
	return "%s_%s_%d" % [kingdom_id, role_tag, Time.get_ticks_msec()]


func _generate_given_name(kingdom_id: String) -> String:
	var bank: Array = NAME_BANKS.get(kingdom_id, [])
	if bank.is_empty():
		return "Eunomos"
	return String(bank[_rng.randi_range(0, bank.size() - 1)])


func _generate_age_for_role(role: int) -> int:
	# Ranges chosen to feel like a court: heirs young, rulers never
	# generated here (RULER is short-circuited upstream), priests and
	# philosophers skew older.
	match role:
		int(Actor.Role.HEIR):        return _rng.randi_range(12, 25)
		int(Actor.Role.GENERAL):     return _rng.randi_range(32, 55)
		int(Actor.Role.ADVISOR):     return _rng.randi_range(35, 60)
		int(Actor.Role.PRIEST):      return _rng.randi_range(40, 65)
		int(Actor.Role.MERCHANT):    return _rng.randi_range(28, 55)
		int(Actor.Role.PHILOSOPHER): return _rng.randi_range(35, 65)
		_:                           return _rng.randi_range(25, 55)


func _default_province(kingdom_id: String) -> String:
	var k: Kingdom = WorldData.get_kingdom(kingdom_id)
	if k == null:
		return ""
	for pid in k.owned_provinces:
		var p: Province = WorldData.get_province(pid)
		if p != null and p.population > 0:
			return p.id
	return ""


## Centre each trait on 50 and add ±20 noise; add a small role-shaped
## bias (heirs score a touch more ambitious, generals more ruthless,
## priests more pious). The ranges stay inside [10, 90] so no actor
## is generated with an extreme trait on day one — extremes are for
## handcrafted actors and for drift over time.
func _randomise_traits(a: Actor, role: int) -> void:
	for k in Actor.TRAIT_KEYS:
		a.set(k, clampi(50 + _rng.randi_range(-20, 20), 10, 90))
	match role:
		int(Actor.Role.HEIR):
			a.ambition = clampi(a.ambition + 10, 10, 90)
		int(Actor.Role.GENERAL):
			a.ruthlessness = clampi(a.ruthlessness + 10, 10, 90)
		int(Actor.Role.ADVISOR):
			a.intellect = clampi(a.intellect + 8, 10, 90)
		int(Actor.Role.PRIEST):
			a.piety = clampi(a.piety + 15, 10, 90)
		int(Actor.Role.MERCHANT):
			a.greed = clampi(a.greed + 10, 10, 90)
		int(Actor.Role.PHILOSOPHER):
			a.intellect = clampi(a.intellect + 12, 10, 90)
			a.curiosity = clampi(a.curiosity + 10, 10, 90)
		_:
			pass


# --- Debug -------------------------------------------------------------------

func print_debug_dump() -> void:
	print("=== Actors (%d) ===" % actors.size())
	for a in all_actors():
		print(" - [%s] %s (%s, %s) birth=%d kingdom=%s province=%s  A%d P%d L%d I%d G%d" % [
			a.id, a.display_name(), a.role_name(),
			("alive" if a.is_alive() else "dead"),
			a.birth_year, a.kingdom_id, a.province_id,
			a.ambition, a.paranoia, a.loyalty, a.intellect, a.greed,
		])


# --- Internals ---------------------------------------------------------------

func _load_from_json(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("[Actors] Data file not found: %s" % path)
		return

	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[Actors] Malformed actor data: %s" % path)
		return

	var list: Array = parsed.get("actors", [])
	for d in list:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var a: Actor = Actor.from_dict(d)
		if a.id == &"":
			continue
		actors[a.id] = a


func _rebuild_indices() -> void:
	_by_kingdom.clear()
	_by_province.clear()
	_by_role.clear()
	for a in actors.values():
		_index_add(_by_kingdom,  a.kingdom_id,  a.id)
		_index_add(_by_province, a.province_id, a.id)
		_index_add(_by_role,     a.role,        a.id)


func _index_add(idx: Dictionary, key: Variant, id: StringName) -> void:
	if not idx.has(key):
		idx[key] = []
	(idx[key] as Array).append(id)


func _collect(ids: Array) -> Array[Actor]:
	var out: Array[Actor] = []
	for id in ids:
		var a: Actor = actors.get(id, null)
		if a != null:
			out.append(a)
	return out
