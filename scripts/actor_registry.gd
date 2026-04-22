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
func adjust_relationship(id: StringName, delta: int) -> int:
	var a: Actor = get_actor(id)
	if a == null:
		return 0
	a.relationship = clampi(a.relationship + delta, -100, 100)
	return a.relationship


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
