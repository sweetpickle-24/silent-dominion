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


func _ready() -> void:
	_load_from_json(ACTOR_DATA_PATH)
	_rebuild_indices()
	print("[Actors] Loaded %d actors from %s" % [actors.size(), ACTOR_DATA_PATH])

	GameClock.month_passed.connect(_on_month_passed)
	EventBus.actor_died.connect(_on_actor_died)


## Emitted elsewhere (WorldAI). If the deceased was above the host
## threshold we owe the player a letter explaining that the network
## has lost a hand, because `_announce_host_lost` is otherwise only
## triggered by relationship drift.
func _on_actor_died(actor_id: StringName, was_host: bool, _cause: StringName) -> void:
	if not was_host:
		return
	var a: Actor = get_actor(actor_id)
	if a == null:
		return
	_announce_host_lost_by_death(a)


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
