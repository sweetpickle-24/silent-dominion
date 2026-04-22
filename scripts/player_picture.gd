extends Node
## Autoloaded as `Picture`. The player's model of the world — the half of
## the two-reality system (§7.6, §15) that the UI draws from. Ground
## truth lives in Actors / WorldData / etc.; everything the player *sees*
## in dossiers, on the map, and in the memoirs panel is supposed to
## flow through here.
##
## Phase 2.1 scope:
##  - per-kingdom visibility score 0-100 (§15.1)
##  - monthly decay + floor from coordinator presence (§15.2)
##  - cached actor snapshots captured when intel refreshes the region,
##    with a "last seen" stamp so stale dossiers can label themselves
##  - save / load of both

signal visibility_changed(kingdom_id: String, score: int)
signal actor_snapshot_taken(actor_id: StringName)

# Per-kingdom visibility score. Default 0 (unseen). The player lifts a
# kingdom above ~20 just by having one operative drop a letter from it;
# after that, active coverage keeps it topped up.
var visibility: Dictionary = {}       # String kingdom_id -> int 0..100

# Per-actor cached picture. Keyed by actor_id (String). Each entry is a
# Dictionary shaped like Actor.to_dict() plus "_seen_year" / "_seen_month"
# and "_seen_day". The UI reads these instead of the live Actor when
# intel on their home kingdom has gone cold.
var actor_snapshots: Dictionary = {}  # String actor_id -> Dictionary

# Tuning knobs — kept as consts rather than exports because they are
# part of the game's balance rather than per-save data.
const MONTHLY_DECAY: int = 6          # base drop per month if no refresh
const DECAY_WHEN_OPERATIVE: int = 3   # softened drop if an op lives there
const DECAY_WHEN_COORDINATOR: int = 0 # a full coordinator halts decay
const OBSERVE_REFRESH: int = 25
const CULTIVATE_REFRESH: int = 15
const BRIBE_REFRESH: int = 10
const STALE_THRESHOLD: int = 50       # below this = "stale" label
const COLD_THRESHOLD: int = 20        # below this = "no useful data"
const COORDINATOR_FLOOR: int = 70     # coordinator presence holds to this


func _ready() -> void:
	GameClock.month_passed.connect(_on_month_passed)
	EventBus.action_resolved.connect(_on_action_resolved)


# --- Public: visibility queries ---------------------------------------------

func score_for(kingdom_id: String) -> int:
	return int(visibility.get(kingdom_id, 0))


## Three-tier label for the fog-of-war overlay. Used by the map and
## the dossier header.
func state_for(kingdom_id: String) -> StringName:
	var s: int = score_for(kingdom_id)
	if s >= 75: return &"current"
	if s >= 50: return &"aging"
	if s >= 20: return &"stale"
	return &"cold"


func is_cold(kingdom_id: String) -> bool:
	return score_for(kingdom_id) < COLD_THRESHOLD


func is_stale(kingdom_id: String) -> bool:
	return score_for(kingdom_id) < STALE_THRESHOLD


## Human-readable phrase for the intelligence layer label ("current",
## "two months old", "from last year", ...). Uses the most recently
## stamped snapshot in the kingdom, if any; otherwise falls back to
## the state label.
func freshness_phrase(kingdom_id: String) -> String:
	var newest_year: int = -999
	var newest_month: int = 0
	var have_any: bool = false
	for snap in actor_snapshots.values():
		if String(snap.get("kingdom_id", "")) != kingdom_id:
			continue
		var y: int = int(snap.get("_seen_year", -999))
		var m: int = int(snap.get("_seen_month", 0))
		if y > newest_year or (y == newest_year and m > newest_month):
			newest_year = y
			newest_month = m
			have_any = true
	if not have_any:
		return "no useful data"
	var months: int = _months_between(newest_year, newest_month, GameClock.year, GameClock.month)
	if months <= 1:
		return "current"
	if months < 12:
		return "%d months old" % months
	var years: int = months / 12
	if years == 1:
		return "a year old"
	return "%d years old" % years


# --- Public: actor snapshot ------------------------------------------------

func snapshot_of(actor_id: StringName) -> Dictionary:
	return actor_snapshots.get(String(actor_id), {})


## Returns a best-effort picture of the actor for UI consumption. When
## we have a fresh actor on the live registry we use that; when the
## kingdom is cold and we have a cached snapshot, we return that with
## a `_stale: true` marker so the dossier knows to say so.
func actor_picture(actor_id: StringName) -> Dictionary:
	var a: Actor = Actors.get_actor(actor_id)
	var kid: String = a.kingdom_id if a != null else ""
	var live: Dictionary = a.to_dict() if a != null else {}
	var cold: bool = kid == "" or is_cold(kid)
	if not cold:
		live["_stale"] = false
		live["_seen_phrase"] = freshness_phrase(kid)
		return live
	var cached: Dictionary = actor_snapshots.get(String(actor_id), {})
	if cached.is_empty():
		live["_stale"] = true
		live["_seen_phrase"] = "no reports in months"
		return live
	cached["_stale"] = true
	cached["_seen_phrase"] = freshness_phrase(kid)
	return cached


## Take a fresh snapshot of an actor. Called whenever a report refreshes
## the region. Stored data mirrors Actor.to_dict() plus the stamp.
func snapshot_actor(actor_id: StringName) -> void:
	var a: Actor = Actors.get_actor(actor_id)
	if a == null:
		return
	var d: Dictionary = a.to_dict()
	d["_seen_year"] = GameClock.year
	d["_seen_month"] = GameClock.month
	d["_seen_day"] = GameClock.day
	actor_snapshots[String(actor_id)] = d
	actor_snapshot_taken.emit(actor_id)


## Take snapshots for every named actor who lives in this kingdom. Cheap
## because there are rarely more than a few dozen named actors per
## kingdom; called on every successful intel-producing action.
func snapshot_kingdom(kingdom_id: String) -> void:
	if kingdom_id.is_empty():
		return
	for a in Actors.all_actors():
		if a.kingdom_id == kingdom_id and a.is_alive():
			snapshot_actor(a.id)


# --- Public: mutation ------------------------------------------------------

func bump_visibility(kingdom_id: String, amount: int, _reason: StringName = &"") -> void:
	if kingdom_id.is_empty() or amount == 0:
		return
	var prev: int = score_for(kingdom_id)
	var next: int = clampi(prev + amount, 0, 100)
	if next == prev:
		return
	visibility[kingdom_id] = next
	visibility_changed.emit(kingdom_id, next)


func set_visibility(kingdom_id: String, value: int) -> void:
	if kingdom_id.is_empty():
		return
	var prev: int = score_for(kingdom_id)
	var next: int = clampi(value, 0, 100)
	if next == prev:
		return
	visibility[kingdom_id] = next
	visibility_changed.emit(kingdom_id, next)


# --- Ticks -----------------------------------------------------------------

func _on_month_passed(_y: int, _m: int) -> void:
	# Every kingdom known to WorldData loses a bit of fidelity each month,
	# softened by anyone we have on the ground. Coordinators halt the
	# drop outright (§15.2: active coverage keeps the page fresh).
	for kid in WorldData.kingdoms.keys():
		var kid_s: String = String(kid)
		var decay: int = _decay_for(kid_s)
		if decay <= 0:
			# Coordinator present: soft-lift to the floor rather than decay.
			var floor: int = COORDINATOR_FLOOR if _coordinator_in(kid_s) else 0
			if floor > 0 and score_for(kid_s) < floor:
				set_visibility(kid_s, floor)
			continue
		var prev: int = score_for(kid_s)
		if prev <= 0:
			continue
		set_visibility(kid_s, prev - decay)


func _on_action_resolved(action_id: StringName, result: Dictionary) -> void:
	# Only successful, target-bound actions refresh the picture — failed
	# ones still teach us nothing we can trust. `result.target_id` is an
	# Actor id for most actions, a kingdom id for a few.
	if not bool(result.get("success", false)):
		return
	var target_id: String = String(result.get("target_id", ""))
	if target_id.is_empty():
		return

	var kid: String = ""
	# Fall back to the target itself if we can't resolve it as an actor
	# (that handles kingdom-targeted actions cleanly).
	var a: Actor = Actors.get_actor(StringName(target_id))
	if a != null:
		kid = a.kingdom_id
	elif WorldData.get_kingdom(target_id) != null:
		kid = target_id

	if kid.is_empty():
		return

	var bump: int = 10
	match action_id:
		&"observe":             bump = OBSERVE_REFRESH
		&"cultivate":           bump = CULTIVATE_REFRESH
		&"bribe_direct", &"bribe_retainer", &"bribe_career", \
		&"bribe_info", &"bribe_gift":
			bump = BRIBE_REFRESH
		&"seed_rumour", &"plant_idea":
			bump = 8
		&"host_sway_court", &"host_agitate":
			bump = 12
		&"quiet_plot":
			bump = 14
		&"intel_cross_reference", &"intel_source_audit":
			bump = 6
		&"intel_reinvestigate":
			bump = 30  # independent walk is the biggest single refresh
		&"audit_cell":
			bump = 4
		_:
			bump = 6

	bump_visibility(kid, bump, action_id)
	# Refresh the named actors in the kingdom — next time the player
	# opens a dossier there, it is not stale.
	snapshot_kingdom(kid)


# --- Internals -------------------------------------------------------------

func _decay_for(kingdom_id: String) -> int:
	if _coordinator_in(kingdom_id):
		return DECAY_WHEN_COORDINATOR
	if _operative_in(kingdom_id):
		return DECAY_WHEN_OPERATIVE
	return MONTHLY_DECAY


func _coordinator_in(kingdom_id: String) -> bool:
	for m in Org.all_members():
		if m.burned:
			continue
		if m.layer == OrgMember.Layer.COORDINATOR and m.region_id == kingdom_id:
			return true
	return false


func _operative_in(kingdom_id: String) -> bool:
	for m in Org.all_members():
		if m.burned:
			continue
		if m.region_id == kingdom_id:
			return true
	return false


func _months_between(y1: int, m1: int, y2: int, m2: int) -> int:
	# GameClock years are negative BCE — direction-agnostic arithmetic.
	return (y2 - y1) * 12 + (m2 - m1)


# --- Save / load -----------------------------------------------------------

func snapshot() -> Dictionary:
	return {
		"visibility":      visibility.duplicate(true),
		"actor_snapshots": actor_snapshots.duplicate(true),
	}


func restore(d: Dictionary) -> void:
	visibility.clear()
	actor_snapshots.clear()
	var v: Variant = d.get("visibility", {})
	if v is Dictionary:
		for k in v:
			visibility[String(k)] = clampi(int(v[k]), 0, 100)
	var snaps: Variant = d.get("actor_snapshots", {})
	if snaps is Dictionary:
		for k in snaps:
			actor_snapshots[String(k)] = snaps[k]
