extends Node
## Autoloaded as `Relations`. Tracks pairwise relations between kingdoms.
##
## The data model is deliberately small: an undirected graph of
## kingdom_id pairs, each pair holding a single RelationState. The
## world starts at NEUTRAL for every pair. WorldAI flips pairs to
## AT_WAR when it rolls a declaration; monthly drift slowly nudges
## pairs back toward NEUTRAL and sometimes toward FRIENDLY, and a
## small monthly roll can end a war in peace.
##
## Nothing in this module mutates Kingdom resources. Kingdoms keep
## their own treasury/tax state; Relations is strictly about the
## edges of the graph.

signal relation_changed(a_id: String, b_id: String, state: int)

enum RelationState {
	AT_WAR,
	HOSTILE,
	NEUTRAL,
	FRIENDLY,
	ALLIED,
}

# Flat keyed dict: "alpha|beta" (sorted) -> int (RelationState). Missing
# keys are treated as NEUTRAL.
var _edges: Dictionary = {}


func _ready() -> void:
	GameClock.month_passed.connect(_on_month_passed)


# --- Public API --------------------------------------------------------------

func state_between(a_id: String, b_id: String) -> int:
	if a_id == b_id:
		return int(RelationState.NEUTRAL)
	return int(_edges.get(_key(a_id, b_id), int(RelationState.NEUTRAL)))


func state_name(s: int) -> String:
	match s:
		int(RelationState.AT_WAR):   return "at war"
		int(RelationState.HOSTILE):  return "hostile"
		int(RelationState.NEUTRAL):  return "neutral"
		int(RelationState.FRIENDLY): return "friendly"
		int(RelationState.ALLIED):   return "allied"
		_:                           return "unknown"


func set_state(a_id: String, b_id: String, state: int) -> void:
	if a_id == b_id:
		return
	var key: String = _key(a_id, b_id)
	var old: int = int(_edges.get(key, int(RelationState.NEUTRAL)))
	if old == state:
		return
	_edges[key] = state
	relation_changed.emit(a_id, b_id, state)


func set_at_war(a_id: String, b_id: String) -> void:
	set_state(a_id, b_id, int(RelationState.AT_WAR))
	_cascade_coalition(a_id, b_id)


func set_peace(a_id: String, b_id: String) -> void:
	# Peace lands at HOSTILE, not NEUTRAL: the scars take time.
	set_state(a_id, b_id, int(RelationState.HOSTILE))


## Move a single pair one step toward war on the ladder
## ALLIED -> FRIENDLY -> NEUTRAL -> HOSTILE -> AT_WAR. No-op if
## already at AT_WAR. Used by player actions that inflame relations
## without immediately starting a war.
func step_worse(a_id: String, b_id: String) -> void:
	var s: int = state_between(a_id, b_id)
	if s == int(RelationState.AT_WAR):
		return
	var worse: int = s - 1
	if worse < int(RelationState.AT_WAR):
		return
	if worse == int(RelationState.AT_WAR):
		set_at_war(a_id, b_id)
	else:
		set_state(a_id, b_id, worse)


## The neighbour of `kingdom_id` whose relation is already closest to
## war (lowest RelationState). Ties broken by map order. Returns "" if
## the kingdom has no strained relations yet.
func worst_neighbour_of(kingdom_id: String) -> String:
	var best: String = ""
	var best_state: int = int(RelationState.ALLIED) + 1
	for other in WorldData.kingdoms.keys():
		var id: String = String(other)
		if id == kingdom_id:
			continue
		var s: int = state_between(kingdom_id, id)
		if s == int(RelationState.AT_WAR):
			continue
		if s < best_state:
			best_state = s
			best = id
	return best


## All kingdom ids the given id currently has a given relation with.
func ids_in_state(a_id: String, state: int) -> Array[String]:
	var out: Array[String] = []
	for other_id in WorldData.kingdoms.keys():
		var other: String = String(other_id)
		if other == a_id:
			continue
		if state_between(a_id, other) == state:
			out.append(other)
	return out


## Every pair currently at war.
func warring_pairs() -> Array:
	var out: Array = []
	for key in _edges.keys():
		if int(_edges[key]) == int(RelationState.AT_WAR):
			out.append(String(key).split("|"))
	return out


# --- Monthly drift -----------------------------------------------------------

func _on_month_passed(_y: int, _m: int) -> void:
	if not WorldData.is_loaded():
		return
	# Copy keys first; we may mutate _edges while iterating (peace).
	var keys: Array = _edges.keys().duplicate()
	for key in keys:
		var state: int = int(_edges[key])
		match state:
			int(RelationState.AT_WAR):
				_tick_war(String(key))
			int(RelationState.HOSTILE):
				if randf() < 0.12:
					_edges[key] = int(RelationState.NEUTRAL)
					_emit_changed(String(key), int(RelationState.NEUTRAL))
			int(RelationState.FRIENDLY):
				if randf() < 0.05:
					_edges[key] = int(RelationState.NEUTRAL)
					_emit_changed(String(key), int(RelationState.NEUTRAL))


func _tick_war(key: String) -> void:
	# ~4% per month → war usually lasts roughly two to three years.
	if randf() < 0.045:
		_edges[key] = int(RelationState.HOSTILE)
		var pair: PackedStringArray = key.split("|")
		if pair.size() == 2:
			_emit_peace(pair[0], pair[1])
			_emit_changed(key, int(RelationState.HOSTILE))


# --- Internal ----------------------------------------------------------------

func _cascade_coalition(a_id: String, b_id: String) -> void:
	# Friends of A become HOSTILE to B, and vice versa. Allies become
	# AT_WAR with the other side on entry. Kept modest so wars don't
	# snowball into world-ending alliance dominoes.
	for side_a in [a_id, b_id]:
		var other: String = b_id if side_a == a_id else a_id
		for friend_id in ids_in_state(side_a, int(RelationState.FRIENDLY)):
			if state_between(friend_id, other) < int(RelationState.HOSTILE):
				continue
			set_state(friend_id, other, int(RelationState.HOSTILE))
		for ally_id in ids_in_state(side_a, int(RelationState.ALLIED)):
			if state_between(ally_id, other) == int(RelationState.AT_WAR):
				continue
			set_state(ally_id, other, int(RelationState.AT_WAR))


func _emit_peace(a_id: String, b_id: String) -> void:
	var a: Kingdom = WorldData.get_kingdom(a_id)
	var b: Kingdom = WorldData.get_kingdom(b_id)
	if a == null or b == null:
		return
	EventBus.public_event.emit({
		"kind":       &"peace_declaration",
		"kingdom_id": a.id,
		"headline":   "Peace between %s and %s" % [a.kingdom_name, b.kingdom_name],
		"body":       "The war between %s and %s is ended. Neither side calls it victory; both sides call it prudent. The treaties mean what treaties usually mean." % [
			a.kingdom_name, b.kingdom_name,
		],
	})


func _emit_changed(key: String, state: int) -> void:
	var pair: PackedStringArray = key.split("|")
	if pair.size() == 2:
		relation_changed.emit(pair[0], pair[1], state)


func _key(a_id: String, b_id: String) -> String:
	if a_id < b_id:
		return "%s|%s" % [a_id, b_id]
	return "%s|%s" % [b_id, a_id]


# --- Save/load hooks ---------------------------------------------------------

func snapshot() -> Dictionary:
	return { "edges": _edges.duplicate() }


func restore(d: Dictionary) -> void:
	_edges.clear()
	var edges: Dictionary = d.get("edges", {})
	for k in edges.keys():
		_edges[String(k)] = int(edges[k])
