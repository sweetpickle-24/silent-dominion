extends Node
## Autoloaded as `Org`. The registry of every Lieutenant, Coordinator,
## and named Operative the player has cultivated.
##
## The game starts empty (§14.3). The first generations run on direct
## contact. Once the player promotes their first Coordinator, actions
## targeting actors in that Coordinator's kingdom start routing through
## the cell: smaller exposure footprint, higher success odds, but with
## a short dispatch delay and the risk of burning a subordinate on
## botched jobs.
##
## Compartmentalisation (§14.2) is implemented by the routing path in
## `action_runner`: when an action fails badly, the *operative* eats
## heat and can be burned; when heat cascades, the *coordinator* is
## burned. The player's own `Exposure` meter is only hit directly for
## work done without coverage.

signal member_added(member: OrgMember)
signal member_updated(member: OrgMember)
signal member_burned(member: OrgMember, reason: StringName)
signal roster_changed

# id (StringName) -> OrgMember
var members: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Monthly trust drift is small on purpose. Loyal members drift up,
# greedy/corruptible ones drift down. Across a decade this accumulates
# into a decision point: audit them, replace them, or trust them with
# more. See §19.
const MONTHLY_TRUST_DRIFT_BASE: int = 1
# Skill drift is mild too — a good Coordinator gets better with tenure
# but not infinitely. Capped by `SKILL_SOFT_CAP`.
const MONTHLY_SKILL_GAIN_MAX: int = 1
const SKILL_SOFT_CAP: int = 85

# When heat on a member crosses this threshold, they're burned.
# Chosen so that a single failure doesn't kill a cell but a sustained
# bad season will.
const HEAT_BURN_THRESHOLD: int = 75

# Span-of-control soft limits (§14.1). These are advisory: the player
# can exceed them, but each excess coordinator/operative past the
# threshold earns a "strain" status that docks effective skill a few
# points and slowly lifts heat. UI surfaces this as a warning on the
# roster row rather than a hard block.
## §C1 the actual caps live in the per-layer Ops modules now; the
## constants here are thin aliases kept for callers that historically
## read them off the registry.
const MAX_COORDINATORS_PER_LIEUTENANT: int = LieutenantOps.MAX_COORDINATORS
const MAX_OPERATIVES_PER_COORDINATOR: int = CoordinatorOps.MAX_OPERATIVES
const STRAIN_SKILL_PENALTY_PER_EXCESS: int = 4
const STRAIN_MONTHLY_HEAT_BUMP: int = 1

## §C1 cover bank lives in `OperativeOps` now so the operative layer
## owns its own content. Alias retained for old tooling that greps for
## the constant name.
const OP_COVER_BANK: Array[String] = OperativeOps.OP_COVER_BANK


## §28.1 canonical starting cell: one named coordinator in Athens.
## Actor `starter_coordinator_athens` is preloaded by Actors; we turn
## them into an OrgMember here so turn-1 code that asks "does the
## player have coverage in athens?" answers truthfully.
const STARTER_COORDINATOR_ACTOR_ID: StringName = &"starter_coordinator_athens"
const STARTER_HOST_ACTOR_ID: StringName = &"starter_host_athens"
var _starter_seeded: bool = false


func _ready() -> void:
	DevLogger.write("Org: ready")
	_rng.randomize()
	GameClock.month_passed.connect(_on_month_passed)
	GameClock.day_passed.connect(_on_day_passed)
	# Seed the starter cell once the world + actor registries are up.
	if WorldData.is_loaded():
		_seed_starter_cell()
	else:
		WorldData.world_loaded.connect(_seed_starter_cell, CONNECT_ONE_SHOT)
	print("[Org] Registry ready. %d members." % members.size())


## §28.1. Promote the preloaded starter coordinator actor into a
## real OrgMember, COORDINATOR layer, region = athens. No operatives
## are spawned — §14.3 "generations 2–3 build operative layer".
## Idempotent: safe to re-run.
func _seed_starter_cell() -> void:
	if _starter_seeded:
		return
	_starter_seeded = true
	# Respect save-load: if the roster already holds the starter
	# coordinator, do nothing. `restore()` ran before us.
	if is_actor_member(STARTER_COORDINATOR_ACTOR_ID):
		return
	var a: Actor = Actors.get_actor(STARTER_COORDINATOR_ACTOR_ID)
	if a == null:
		push_warning("[Org] starter coordinator actor missing; cell not seeded.")
		return
	var m: OrgMember = OrgMember.new()
	m.id              = StringName("org_coord_starter_athens")
	m.source_actor_id = a.id
	m.display_name    = a.display_name()
	m.layer           = OrgMember.Layer.COORDINATOR
	m.region_id       = a.kingdom_id
	m.superior_id     = &""
	m.trust           = 70
	m.skill           = 55
	m.heat            = 0
	m.tenure_days     = 0
	m.cover           = "scribe at the Kerameikos"
	m.origin_blurb    = "Inherited from your predecessor. Held the Athens cell through the quiet years."
	_add(m)
	# Ensure the source actor is flagged AGENT so the dossier view
	# does not offer "promote" on someone already serving.
	a.role = Actor.Role.AGENT


# --- Public: queries ---------------------------------------------------------

func get_member(id: StringName) -> OrgMember:
	return members.get(id, null)


func all_members() -> Array[OrgMember]:
	var out: Array[OrgMember] = []
	for m in members.values():
		out.append(m)
	return out


func by_layer(layer: OrgMember.Layer) -> Array[OrgMember]:
	var out: Array[OrgMember] = []
	for m in members.values():
		if m.layer == layer and not m.burned:
			out.append(m)
	return out


func coordinators_in(kingdom_id: String) -> Array[OrgMember]:
	var out: Array[OrgMember] = []
	for m in members.values():
		if m.layer == OrgMember.Layer.COORDINATOR and not m.burned and m.region_id == kingdom_id:
			out.append(m)
	return out


## First non-burned coordinator covering `kingdom_id`, or null if none.
## The single point of truth for "does the player have coverage here?".
func coverage_for(kingdom_id: String) -> OrgMember:
	var list: Array[OrgMember] = coordinators_in(kingdom_id)
	# §C1 delegate the "best coordinator" heuristic to CoordinatorOps.
	return CoordinatorOps.pick_best_coverage(list)


## True if an actor is currently an OrgMember (any layer).
func is_actor_member(actor_id: StringName) -> bool:
	for m in members.values():
		if not m.burned and m.source_actor_id == actor_id:
			return true
	return false


func member_for_actor(actor_id: StringName) -> OrgMember:
	for m in members.values():
		if not m.burned and m.source_actor_id == actor_id:
			return m
	return null


func size_active() -> int:
	var n: int = 0
	for m in members.values():
		if not m.burned:
			n += 1
	return n


## How many active subordinates currently report to `boss_id`.
func reports_to(boss_id: StringName) -> int:
	var n: int = 0
	for m in members.values():
		if m.burned:
			continue
		if m.superior_id == boss_id:
			n += 1
	return n


## Excess headcount above the soft cap for a given member. Returns 0
## when inside the cap. UI and drift use this to paint "strained" rows.
## §C1 Delegates to the per-layer Ops module so the caps are owned by
## the layer they belong to.
func strain_of(id: StringName) -> int:
	var m: OrgMember = get_member(id)
	if m == null or m.burned:
		return 0
	var n: int = reports_to(id)
	match m.layer:
		OrgMember.Layer.LIEUTENANT:
			return LieutenantOps.strain_excess(m, n)
		OrgMember.Layer.COORDINATOR:
			return CoordinatorOps.strain_excess(m, n)
		_:
			return OperativeOps.strain_excess(m)


## Qualitative status used in the Roster view — keeps numbers out of
## UI strings. Returns "comfortable", "stretched" or "over".
func strain_label(id: StringName) -> StringName:
	var over: int = strain_of(id)
	if over <= 0:
		return &"comfortable"
	if over == 1:
		return &"stretched"
	return &"over"


## Effective skill after strain penalty. Callers that want "the usable
## skill right now" (e.g. action routing) should read this, not the
## raw `skill` field.
func effective_skill(id: StringName) -> int:
	var m: OrgMember = get_member(id)
	if m == null or m.burned:
		return 0
	var penalty: int = strain_of(id) * STRAIN_SKILL_PENALTY_PER_EXCESS
	return maxi(0, m.skill - penalty)


# --- Public: mutations -------------------------------------------------------

## Create a Coordinator from a cultivated Actor. Auto-spawns two abstract
## operatives under them so there's something to route work through on
## day one. Returns the new OrgMember.
func promote_actor_to_coordinator(actor_id: StringName) -> OrgMember:
	var a: Actor = Actors.get_actor(actor_id)
	if a == null:
		push_warning("[Org] promote_coordinator: unknown actor %s" % actor_id)
		return null
	if is_actor_member(actor_id):
		push_warning("[Org] %s is already in the organisation." % actor_id)
		return member_for_actor(actor_id)

	var m: OrgMember = OrgMember.new()
	m.id              = StringName("org_coord_%s_%d" % [actor_id, Time.get_ticks_msec()])
	m.source_actor_id = actor_id
	m.display_name    = a.display_name()
	m.layer           = OrgMember.Layer.COORDINATOR
	m.region_id       = a.kingdom_id
	m.superior_id     = _find_lieutenant_over(a.kingdom_id)
	@warning_ignore("integer_division")
	m.trust           = clampi(40 + a.loyalty / 3 + a.relationship / 4, 10, 85)
	@warning_ignore("integer_division")
	m.skill           = clampi(30 + a.intellect / 3 + a.charisma / 5 + _rng.randi_range(-5, 10), 15, 80)
	m.heat            = 0
	m.tenure_days     = 0
	m.cover           = CoordinatorOps.cover_for_role(a.role)
	m.origin_blurb    = "Formerly %s, %s" % [_role_phrase(a.role), _kingdom_name(a.kingdom_id)]
	_add(m)

	# Seed the cell with two abstract operatives so the Coordinator can
	# actually dispatch work the day after their promotion.
	_spawn_abstract_operative(m)
	_spawn_abstract_operative(m)

	# Their Actor gets re-classed to AGENT so the dossier view
	# stops offering "promote" on someone already promoted.
	a.role = Actor.Role.AGENT

	return m


## Promote an existing Coordinator to Lieutenant. Reassigns every
## coordinator currently in their region to report to the new Lieutenant
## instead of the player.
func promote_coordinator_to_lieutenant(coord_id: StringName) -> OrgMember:
	var m: OrgMember = get_member(coord_id)
	if m == null or m.layer != OrgMember.Layer.COORDINATOR:
		push_warning("[Org] promote_lieutenant: %s is not a coordinator" % coord_id)
		return null

	m.layer       = OrgMember.Layer.LIEUTENANT
	m.superior_id = &""
	m.trust       = clampi(m.trust + 5, 0, 100)
	m.skill       = clampi(m.skill + 5, 0, 100)
	m.origin_blurb = "Raised to Lieutenant from the " + _kingdom_name(m.region_id) + " cell."

	# If this lieutenant comes from a tracked family, derive their
	# natural §21.5 specialisation — a scholarly line goes ideological,
	# a banking line financial, etc. The player can override later.
	if m.source_actor_id != &"":
		var src: Actor = Actors.get_actor(m.source_actor_id)
		if src != null:
			var fam: Family = Dynasties.family_of(src)
			if fam != null:
				m.specialisation = m.recommended_specialisation_from_family(fam)
				# A lieutenant drawn from the "right" dynasty walks in
				# with authority the outsider would spend years to
				# earn — reflected as a modest skill bump.
				if m.specialisation != OrgMember.Specialisation.NONE:
					m.skill = clampi(m.skill + 8, 0, 100)

	# Reassign peers: every coordinator in the same region now reports
	# to the fresh Lieutenant.
	for other in members.values():
		if other.id == m.id:
			continue
		if other.burned:
			continue
		if other.layer == OrgMember.Layer.COORDINATOR and other.region_id == m.region_id:
			other.superior_id = m.id
			member_updated.emit(other)

	member_updated.emit(m)
	roster_changed.emit()
	return m


## Mark a member burned. Cascades upward: a burned Operative bumps the
## heat on its Coordinator; a burned Coordinator bumps the Lieutenant.
## The player is only reached if the Lieutenant burns — handled by the
## action_runner hitting the global Exposure meter directly in that
## case.
func burn_member(id: StringName, reason: StringName = &"botched") -> void:
	var m: OrgMember = get_member(id)
	if m == null or m.burned:
		return
	m.burned = true
	member_burned.emit(m, reason)
	roster_changed.emit()

	if m.superior_id != &"":
		bump_heat(m.superior_id, 20, reason)


## Add heat to a specific member. Burns them if they cross the
## threshold. No-op if unknown or already burned.
func bump_heat(id: StringName, delta: int, reason: StringName = &"") -> void:
	var m: OrgMember = get_member(id)
	if m == null or m.burned:
		return
	m.heat = clampi(m.heat + delta, 0, 100)
	member_updated.emit(m)
	if m.heat >= HEAT_BURN_THRESHOLD:
		burn_member(id, reason)


## Adjust trust by `delta`, clamped to [0,100]. Used by action_runner
## when work routed through a coordinator succeeds or fails.
func adjust_trust(id: StringName, delta: int) -> void:
	var m: OrgMember = get_member(id)
	if m == null or m.burned:
		return
	m.trust = clampi(m.trust + delta, 0, 100)
	member_updated.emit(m)


## Pick a random non-burned operative under `coord_id`. If the cell has
## no operatives left (all burned or none ever spawned), spawns one on
## the fly and returns it. The coordinator always has someone to send.
func operative_for_coordinator(coord_id: StringName) -> OrgMember:
	var pool: Array[OrgMember] = []
	for m in members.values():
		if not m.burned and m.layer == OrgMember.Layer.OPERATIVE and m.superior_id == coord_id:
			pool.append(m)
	if pool.is_empty():
		var coord: OrgMember = get_member(coord_id)
		if coord == null:
			return null
		return _spawn_abstract_operative(coord)
	return pool[_rng.randi_range(0, pool.size() - 1)]


# --- Ticks -------------------------------------------------------------------

func _on_day_passed(_y: int, _m: int, _d: int) -> void:
	for m in members.values():
		if m.burned:
			continue
		m.tenure_days += 1
		# Heat trickles down over time — an operative who did a risky
		# run last month is not forever marked.
		if m.heat > 0:
			m.heat = maxi(0, m.heat - 1)


func _on_month_passed(_y: int, _m: int) -> void:
	# Trust drift per §19.1: loyal + low-greed drift up, greedy + low-
	# loyalty drift down. Non-actor operatives use their own skill as a
	# rough proxy (a skilled abstract op is assumed loyal enough).
	for m in members.values():
		if m.burned:
			continue
		var drift: int = _trust_drift_for(m)
		if drift != 0:
			m.trust = clampi(m.trust + drift, 0, 100)

		# Skill drift: small monthly bump, softly capped. Members cap
		# their own growth; the ceiling lifts only if the player trusts
		# them with more responsibility (future hook).
		if m.skill < SKILL_SOFT_CAP and _rng.randf() < 0.25:
			m.skill = mini(m.skill + MONTHLY_SKILL_GAIN_MAX, SKILL_SOFT_CAP)

		# Strained bosses earn a monthly heat tick — too many hands
		# means too many small mistakes. The bump is modest but across
		# a year an over-stretched lieutenant will be the first to burn.
		var over: int = strain_of(m.id)
		if over > 0:
			m.heat = clampi(m.heat + STRAIN_MONTHLY_HEAT_BUMP * over, 0, 100)
			if m.heat >= HEAT_BURN_THRESHOLD:
				burn_member(m.id, &"strain")
				continue

		# Tenure-without-oversight counter (§19.1). Ticks forward every
		# month; reset by a successful audit_cell. The Roster surfaces
		# this as a "drift" warning past ~12 months, and audit yield
		# scales with this number.
		m.months_since_audit += 1

		# Double-agent maintenance (§18.5). Running a double bleeds
		# exposure every month — feeding curated fiction is real work.
		if m.double_agent:
			Exposure.bump(0.5, "double_agent_upkeep")

		member_updated.emit(m)


func _trust_drift_for(m: OrgMember) -> int:
	if m.source_actor_id != &"":
		var a: Actor = Actors.get_actor(m.source_actor_id)
		if a != null:
			# Loyalty above 60 lifts trust; greed above 60 erodes it.
			# Net +/-1 per month in either direction; stacks across a year.
			var up: int = 0
			var down: int = 0
			if a.loyalty >= 60:
				up += MONTHLY_TRUST_DRIFT_BASE
			if a.greed >= 65 and a.loyalty < 55:
				down += MONTHLY_TRUST_DRIFT_BASE
			if a.loyalty < 35:
				down += MONTHLY_TRUST_DRIFT_BASE
			return up - down
	# Abstract operative: §C1 delegated to OperativeOps for per-layer
	# tuning.
	return OperativeOps.trust_drift_abstract(m, _rng)


# --- Save / load -------------------------------------------------------------

func snapshot() -> Array:
	var out: Array = []
	for m in members.values():
		out.append(m.to_dict())
	return out


func restore(arr: Array) -> void:
	members.clear()
	for d in arr:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var m: OrgMember = OrgMember.from_dict(d)
		if m.id == &"":
			continue
		members[m.id] = m
	roster_changed.emit()


func debug_dump() -> void:
	print("=== Org (%d) ===" % members.size())
	for m in all_members():
		print(" - [%s] %s %s region=%s sup=%s trust=%d skill=%d heat=%d burned=%s" % [
			m.id, m.layer_name(), m.display_name, m.region_id,
			String(m.superior_id), m.trust, m.skill, m.heat, str(m.burned),
		])


# --- Internals ---------------------------------------------------------------

func _add(m: OrgMember) -> void:
	members[m.id] = m
	member_added.emit(m)
	roster_changed.emit()


func _find_lieutenant_over(kingdom_id: String) -> StringName:
	# §C1 delegated to LieutenantOps so the "who covers what region?"
	# rule lives next to the other lieutenant-level rules.
	return LieutenantOps.find_over(all_members(), kingdom_id)


func _spawn_abstract_operative(coord: OrgMember) -> OrgMember:
	# §C1 the operative layer owns its own spawn-shape; we keep the
	# registry role (register the new member and wire signals) here.
	var op: OrgMember = OperativeOps.spawn_abstract(coord, _rng)
	_add(op)
	return op


func _role_phrase(role: int) -> String:
	match role:
		Actor.Role.RULER:       return "sovereign"
		Actor.Role.HEIR:        return "heir at court"
		Actor.Role.GENERAL:     return "general"
		Actor.Role.PRIEST:      return "priest"
		Actor.Role.MERCHANT:    return "merchant"
		Actor.Role.ADVISOR:     return "advisor"
		Actor.Role.PHILOSOPHER: return "philosopher"
		_:                      return "private citizen"


func _kingdom_name(kid: String) -> String:
	var k: Kingdom = WorldData.get_kingdom(kid)
	return k.kingdom_name if k != null else kid
