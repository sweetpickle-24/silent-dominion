extends Node
## Autoloaded as `Base`. Player's base of operations (§22).
##
## What lives here:
##   - the province/kingdom the player's table is currently in
##   - the pre-move checklist that must clear before the player can
##     uproot (§22.2)
##   - the in-transit state while the pin animates from old to new
##   - the transition window (§22.4) after arrival, during which
##     Memoirs, Automations, and action dispatch to the new base
##     are all throttled
##
## Design notes:
##   - The base is purely a player concept; the world doesn't know
##     which city the immortal is sitting in. So moving is local
##     state plus a handful of side-effects on Memoirs, Automations,
##     scheduling, and the picture.
##   - Travel time is era-scaled. In antiquity a Mediterranean-scale
##     move is measured in months; in the modern era it's weeks.
##   - Other modules that care about the transition window read
##     `is_in_transition_for(kingdom_id)` — true iff the player is
##     still settling into that kingdom. Nothing queries transition
##     state by province; kingdom granularity is enough.

signal base_changed(old_province: String, new_province: String)
signal checklist_updated
signal move_prepared(destination_province: String)
signal move_started(destination_province: String, travel_days: int)
signal move_completed(arrival_province: String)
signal transition_ended(kingdom_id: String)

# Checklist item keys.
const K_SAFEHOUSE: StringName     = &"safehouse"
const K_COURIER: StringName       = &"courier"
const K_COORDINATOR: StringName   = &"coordinator"
const K_OLD_BASE: StringName      = &"old_base"

# Default starting base. 500 BCE Athens is the canonical opening —
# the province id in `data/world_500bce.json` is "attica" (Athens
# is the owning kingdom).
const DEFAULT_PROVINCE_ID: String = "attica"

# Travel tuning. Ancient-world baseline; era multiplier is applied
# on top via Eras.communication_multiplier().
const BASE_TRAVEL_DAYS_ANCIENT: int = 90
# Transition window — days after arrival during which the new base
# runs at reduced effectiveness.
const TRANSITION_DAYS_ANCIENT: int = 45

# Memoirs match quality penalty during transition (0.0 – 1.0; higher
# is worse).
const MEMOIRS_TRANSITION_PENALTY: float = 0.25
# Extra dispatch-delay days tacked onto actions into the new base's
# kingdom during transition.
const DISPATCH_EXTRA_DAYS: int = 7

var province_id: String = DEFAULT_PROVINCE_ID
var kingdom_id: String = ""

# Move lifecycle state.
# "idle" | "prepared" | "traveling" | "transition"
var state: StringName = &"idle"
var destination_province_id: String = ""
var destination_kingdom_id: String = ""
var travel_days_remaining: int = 0
var travel_days_total: int = 0  # set at begin_move; used to draw travel progress
var transition_days_remaining: int = 0
var origin_province_id: String = ""

# Pre-move checklist map — each entry is a Dictionary of
# { ok: bool, note: String }. The checklist is lazy — it re-evaluates
# each time the player opens the pre-move panel or the org changes.
var checklist: Dictionary = {}


func _ready() -> void:
	DevLogger.write("Base: ready")
	if WorldData.is_loaded():
		_resolve_initial_base()
	else:
		WorldData.world_loaded.connect(_resolve_initial_base)
	GameClock.day_passed.connect(_on_day_passed)


func _resolve_initial_base() -> void:
	if province_id == "" or WorldData.get_province(province_id) == null:
		province_id = DEFAULT_PROVINCE_ID
	var p: Province = WorldData.get_province(province_id)
	kingdom_id = p.owning_kingdom if p != null else ""


# --- Queries ----------------------------------------------------------------

func is_idle() -> bool:
	return state == &"idle"


func is_preparing() -> bool:
	return state == &"prepared"


func is_traveling() -> bool:
	return state == &"traveling"


func is_in_transition() -> bool:
	return state == &"transition" and transition_days_remaining > 0


func is_in_transition_for(target_kingdom_id: String) -> bool:
	if not is_in_transition():
		return false
	return target_kingdom_id == kingdom_id


## 0.0 at the origin, 1.0 at the destination. Callers should only
## trust the value when `is_traveling()` is true; otherwise 0.
func travel_progress() -> float:
	if not is_traveling() or travel_days_total <= 0:
		return 0.0
	var done: int = travel_days_total - travel_days_remaining
	return clampf(float(done) / float(travel_days_total), 0.0, 1.0)


## Qualitative headline for the UI — one sentence the Table or the
## map panel can render without branching on the state enum.
func headline() -> String:
	match String(state):
		"idle":
			return "At your table in %s.%s" % [_province_name(province_id), _cell_suffix()]
		"prepared":
			return "Preparations complete for %s. Awaiting the order to move." % _province_name(destination_province_id)
		"traveling":
			return "On the road to %s — some %d days yet." % [_province_name(destination_province_id), travel_days_remaining]
		"transition":
			return "Settling into %s — %d days before the table runs true." % [_province_name(province_id), transition_days_remaining]
	return ""


## §28.1 — the time-dial tooltip on day one should read:
## "Athens — one host cultivated, one coordinator holding the city".
## Counts hosts and coordinators in the local kingdom so the line
## stays true as the player grows or loses the cell.
func _cell_suffix() -> String:
	if Actors == null or Org == null or kingdom_id.is_empty():
		return ""
	var hosts: int = Actors.hosts_in(kingdom_id).size()
	var coords: int = 0
	for m in Org.all_members():
		if not m.burned and m.layer == OrgMember.Layer.COORDINATOR and m.region_id == kingdom_id:
			coords += 1
	if hosts == 0 and coords == 0:
		return ""
	var host_part: String = ("%d hosts cultivated" % hosts) if hosts != 1 else "One host cultivated"
	var coord_part: String
	if coords == 0:
		coord_part = "no coordinator"
	elif coords == 1:
		coord_part = "one coordinator holding the city"
	else:
		coord_part = "%d coordinators holding the city" % coords
	return " %s, %s." % [host_part, coord_part]


# --- Pre-move checklist (§22.2) ---------------------------------------------

## Compute or refresh the checklist against the given destination.
## Returns the checklist dict so callers can display it without a
## second accessor call.
func recompute_checklist(dst_province_id: String) -> Dictionary:
	checklist.clear()
	var dst: Province = WorldData.get_province(dst_province_id)
	if dst == null:
		return checklist
	var dst_kingdom: String = dst.owning_kingdom

	# 1. Safe house — a coordinator in the destination kingdom can
	#    arrange one quietly. Without a coordinator the player has
	#    no way to arrive safely; this is the hard-block.
	var coord: OrgMember = _coordinator_in(dst_kingdom)
	checklist[K_SAFEHOUSE] = {
		"ok":   coord != null,
		"note": ("A safe house is prepared by %s." % coord.display_name) if coord != null \
				else "No coordinator in %s. A safe house cannot be arranged." % _kingdom_name(dst_kingdom),
	}

	# 2. Courier routes — any operative or coordinator in the
	#    destination region can carry reroutes.
	var carrier: OrgMember = _carrier_in(dst_kingdom)
	checklist[K_COURIER] = {
		"ok":   carrier != null,
		"note": ("Correspondence will reroute through %s." % carrier.display_name) if carrier != null \
				else "No operative on the ground to handle courier reroutes.",
	}

	# 3. Local coordinator briefed — same person as safe house, but
	#    it's a separate task: one is logistics, one is intelligence.
	checklist[K_COORDINATOR] = {
		"ok":   coord != null,
		"note": ("%s will prepare a current picture on arrival." % coord.display_name) if coord != null \
				else "No coordinator to prepare a picture — the first weeks will be blind.",
	}

	# 4. Old base wound down — this is an intent the player
	#    acknowledges. It's always "ok" because the player is the
	#    one winding down; it's displayed as a confirmation, not a
	#    prerequisite.
	checklist[K_OLD_BASE] = {
		"ok":   true,
		"note": "The %s house will be closed without announcement." % _province_name(province_id),
	}

	checklist_updated.emit()
	return checklist


## True when every checklist item flagged as a prerequisite is ok.
## K_OLD_BASE is acknowledged rather than prerequisite.
func checklist_cleared() -> bool:
	if checklist.is_empty():
		return false
	for key in [K_SAFEHOUSE, K_COURIER, K_COORDINATOR]:
		if not bool((checklist.get(key, {}) as Dictionary).get("ok", false)):
			return false
	return true


# --- Move lifecycle ---------------------------------------------------------

## Mark the base move as prepared against a destination. The player
## must clear the checklist first. Does not consume any silver — the
## cost model for travel is time, not money.
func prepare_move(dst_province_id: String) -> bool:
	if not is_idle():
		return false
	var dst: Province = WorldData.get_province(dst_province_id)
	if dst == null or dst_province_id == province_id:
		return false
	recompute_checklist(dst_province_id)
	if not checklist_cleared():
		return false
	destination_province_id = dst_province_id
	destination_kingdom_id  = dst.owning_kingdom
	state = &"prepared"
	move_prepared.emit(dst_province_id)
	return true


## Commit to the move and start travel. Travel time is era-scaled;
## covered-route (coordinator presence through the destination
## kingdom) trims 20% off the travel days.
func begin_move() -> bool:
	if state != &"prepared":
		return false
	var era_mult: float = 1.0
	if Eras != null:
		era_mult = Eras.communication_multiplier()
	var days: int = int(round(float(BASE_TRAVEL_DAYS_ANCIENT) * era_mult))
	if _coordinator_in(destination_kingdom_id) != null:
		# Established coverage trims the journey; this is also the
		# path that delivers intel-along-the-way per the doc.
		days = int(round(float(days) * 0.8))
	travel_days_remaining = max(1, days)
	travel_days_total = travel_days_remaining
	origin_province_id = province_id
	state = &"traveling"
	_announce_departure(travel_days_remaining)
	move_started.emit(destination_province_id, travel_days_remaining)
	return true


## Debug / cheat-console helper. Skips the checklist and travel time
## outright. Not called by UI.
func force_move(dst_province_id: String) -> void:
	var dst: Province = WorldData.get_province(dst_province_id)
	if dst == null:
		return
	destination_province_id = dst_province_id
	destination_kingdom_id  = dst.owning_kingdom
	origin_province_id = province_id
	_complete_travel()


# --- Day tick ---------------------------------------------------------------

func _on_day_passed(_y: int, _m: int, _d: int) -> void:
	match String(state):
		"traveling":
			travel_days_remaining -= 1
			if travel_days_remaining <= 0:
				_complete_travel()
		"transition":
			transition_days_remaining -= 1
			if transition_days_remaining <= 0:
				_complete_transition()
		_:
			pass


func _complete_travel() -> void:
	var old_province: String = province_id
	province_id = destination_province_id
	var old_kingdom: String = kingdom_id
	kingdom_id = destination_kingdom_id

	# Transition window (§22.4).
	var era_mult: float = 1.0
	if Eras != null:
		era_mult = Eras.communication_multiplier()
	transition_days_remaining = max(5, int(round(float(TRANSITION_DAYS_ANCIENT) * era_mult)))
	state = &"transition"

	# Coordinator briefing — the new kingdom's picture freshens
	# immediately on arrival. A coordinator's summary is not the
	# same as the player's direct engagement, so we don't peg it to
	# 100; floor at 60 so the first dossiers aren't blank.
	if Picture != null and kingdom_id != "":
		var cur: int = Picture.score_for(kingdom_id)
		if cur < 60:
			Picture.set_visibility(kingdom_id, 60)

	move_completed.emit(province_id)
	base_changed.emit(old_province, province_id)
	_announce_arrival(old_kingdom)


func _complete_transition() -> void:
	transition_days_remaining = 0
	state = &"idle"
	destination_province_id = ""
	destination_kingdom_id = ""
	transition_ended.emit(kingdom_id)
	_announce_transition_ended()


# --- Modifiers other modules read ------------------------------------------

## Memoirs applies this as a penalty on match quality for patterns
## being tested against targets in the transition kingdom. Returns 0
## when not in transition.
func memoirs_quality_penalty_for(target_kingdom: String) -> float:
	if not is_in_transition_for(target_kingdom):
		return 0.0
	return MEMOIRS_TRANSITION_PENALTY


## ActionRunner adds this many days to dispatch delay when the
## target is in the transition kingdom. Otherwise 0.
func dispatch_extra_days_for(target_kingdom: String) -> int:
	if not is_in_transition_for(target_kingdom):
		return 0
	return DISPATCH_EXTRA_DAYS


# --- Announcements ----------------------------------------------------------

func _announce_departure(days: int) -> void:
	var date: GameDate = _today()
	var letter_id: StringName = StringName("base_depart_%s_%d" % [province_id, -GameClock.year])
	var body: String = (
		"The %s house is quietly closed. No announcement, no forwarding address that anyone in the neighbourhood would notice. The road to %s is some %d days. Correspondence routes are rerouting in your wake — expect the first weeks to arrive out of order."
	) % [_province_name(province_id), _province_name(destination_province_id), days]
	var letter: Letter = Letter.create(
		letter_id,
		OrgRoles.sender_line(OrgRoles.COORDINATOR_AT_DEPARTURE, kingdom_id),
		date,
		"On the road to %s" % _province_name(destination_province_id),
		body,
		&"operative"
	)
	EventBus.letter_delivered.emit(letter)


func _announce_arrival(_old_kingdom: String) -> void:
	var date: GameDate = _today()
	var letter_id: StringName = StringName("base_arrive_%s_%d" % [province_id, -GameClock.year])
	var local_coord = _coordinator_in(kingdom_id)
	var hand_name: String = (
		local_coord.display_name if local_coord != null
		else OrgRoles.neutral_title(OrgRoles.COORDINATOR)
	)
	var body: String = (
		"You sit down in %s. The rooms are clean, the neighbours unbothered. %s has left a brief on the desk — what has happened here in the months you were on the road. A transition window of perhaps %d days applies before the table runs at full reliability."
	) % [
		_province_name(province_id),
		hand_name,
		transition_days_remaining,
	]
	var letter: Letter = Letter.create(
		letter_id,
		OrgRoles.sender_line(OrgRoles.COORDINATOR, kingdom_id),
		date,
		"Arrived in %s" % _province_name(province_id),
		body,
		&"operative"
	)
	EventBus.letter_delivered.emit(letter)


func _announce_transition_ended() -> void:
	var date: GameDate = _today()
	var letter_id: StringName = StringName("base_settled_%s_%d" % [province_id, -GameClock.year])
	var body: String = (
		"The %s base is fully operational. Sources are current, patterns match at full reliability, and dispatch runs at era speed. The move is behind you."
	) % _province_name(province_id)
	var letter: Letter = Letter.create(
		letter_id,
		OrgRoles.sender_line(OrgRoles.COORDINATOR, kingdom_id),
		date,
		"%s runs true" % _province_name(province_id),
		body,
		&"operative"
	)
	EventBus.letter_delivered.emit(letter)


# --- Internals --------------------------------------------------------------

func _today() -> GameDate:
	return GameDate.today()


func _province_name(pid: String) -> String:
	var p: Province = WorldData.get_province(pid)
	return p.province_name if p != null else pid


func _kingdom_name(kid: String) -> String:
	var k: Kingdom = WorldData.get_kingdom(kid)
	return k.kingdom_name if k != null else kid


func _coordinator_in(kid: String) -> OrgMember:
	if Org == null or kid == "":
		return null
	for m in Org.all_members():
		if m.burned:
			continue
		if m.layer == OrgMember.Layer.COORDINATOR and m.region_id == kid:
			return m
	return null


func _carrier_in(kid: String) -> OrgMember:
	if Org == null or kid == "":
		return null
	for m in Org.all_members():
		if m.burned:
			continue
		if m.region_id == kid:
			return m
	return null


# --- Save / load ------------------------------------------------------------

func snapshot() -> Dictionary:
	return {
		"province_id":              province_id,
		"kingdom_id":                kingdom_id,
		"state":                     String(state),
		"destination_province_id":   destination_province_id,
		"destination_kingdom_id":    destination_kingdom_id,
		"travel_days_remaining":     travel_days_remaining,
		"travel_days_total":         travel_days_total,
		"transition_days_remaining": transition_days_remaining,
		"origin_province_id":        origin_province_id,
	}


func restore(d: Dictionary) -> void:
	province_id = String(d.get("province_id", DEFAULT_PROVINCE_ID))
	kingdom_id  = String(d.get("kingdom_id", ""))
	if kingdom_id == "":
		var p: Province = WorldData.get_province(province_id)
		kingdom_id = p.owning_kingdom if p != null else ""
	state = StringName(String(d.get("state", "idle")))
	destination_province_id   = String(d.get("destination_province_id", ""))
	destination_kingdom_id    = String(d.get("destination_kingdom_id", ""))
	travel_days_remaining     = int(d.get("travel_days_remaining", 0))
	travel_days_total         = int(d.get("travel_days_total", travel_days_remaining))
	transition_days_remaining = int(d.get("transition_days_remaining", 0))
	origin_province_id        = String(d.get("origin_province_id", ""))
