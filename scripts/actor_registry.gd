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


func _ready() -> void:
	_load_from_json(ACTOR_DATA_PATH)
	_rebuild_indices()
	print("[Actors] Loaded %d actors from %s" % [actors.size(), ACTOR_DATA_PATH])


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


func add_actor(a: Actor) -> void:
	actors[a.id] = a
	_rebuild_indices()


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
