extends Node
## Autoloaded as `InstRelations`. §B9 — relationships the state-table
## in [scripts/kingdom_relations.gd](scripts/kingdom_relations.gd) does
## not cover: kingdom↔institution and institution↔institution.
##
## Two data structures:
##
##   _state_inst: { "kingdom_id|institution_id" -> StateEdge }
##     StateEdge fields: dependency (0..100), trust (0..100),
##     debt (int silver owed by kingdom to institution), alignment
##     (FRIENDLY / NEUTRAL / HOSTILE), last_veto_year (bank veto
##     rate-limit).
##
##   _inst_inst: { "a|b" (sorted) -> InstEdge }
##     InstEdge fields: state (RIVAL / NEUTRAL / ALLIED), blocks
##     (Dictionary province_id -> absolute_day_until).
##
## "Institution" is any StringName identifier from the three
## populations we currently have: banking houses (`bh_*`), rival
## societies (`rival_*`), religions (`rel_*`). The module doesn't
## care which — it just stores edges.
##
## This autoload intentionally does NOT fire periodic drift. Values
## are moved by the systems that understand them (FinanceManager
## bumps debt, RivalRegistry bumps alignment after clashes, etc).
## That keeps save state small and behaviour debuggable.

signal state_institution_changed(kingdom_id: String, institution_id: String, field: StringName, value: Variant)
signal institution_institution_changed(a_id: String, b_id: String, state: int)
signal bank_vetoed_default(kingdom_id: String, house_id: String, amount: int)
signal institution_blocked(a_id: String, b_id: String, province_id: String, until_day: int)

enum Alignment { FRIENDLY, NEUTRAL, HOSTILE }
enum InstState { RIVAL, NEUTRAL, ALLIED }

# --- Tuning ------------------------------------------------------------------

## Above this silver debt, the creditor bank gets a "veto" window once
## per year on the debtor kingdom's attempts to default. Tuned so a
## single large wartime loan trips it but routine tax-smoothing does
## not.
const BANK_VETO_DEBT_THRESHOLD: int = 2_000

## Default block duration when one institution blocks another in a
## province (§B9: rival societies jostling recruitment). 18 months.
const DEFAULT_BLOCK_DAYS: int = 18 * 30

# --- State -------------------------------------------------------------------

var _state_inst: Dictionary = {}   # "kingdom|inst" -> Dictionary
var _inst_inst: Dictionary = {}    # "a|b" sorted  -> Dictionary


func _ready() -> void:
	DevLogger.write("InstRelations: ready")


# --- Public: kingdom ↔ institution ------------------------------------------

func _si_key(kingdom_id: String, institution_id: String) -> String:
	return "%s|%s" % [kingdom_id, institution_id]


func _ensure_si(kingdom_id: String, institution_id: String) -> Dictionary:
	var key: String = _si_key(kingdom_id, institution_id)
	if not _state_inst.has(key):
		_state_inst[key] = {
			"dependency":      0,
			"trust":           50,
			"debt":            0,
			"alignment":       int(Alignment.NEUTRAL),
			"last_veto_year": -1,
		}
	return _state_inst[key]


## Read the whole edge as a plain dict. Returns a copy; callers should
## go through setters to mutate.
func state_institution_edge(kingdom_id: String, institution_id: String) -> Dictionary:
	var key: String = _si_key(kingdom_id, institution_id)
	if not _state_inst.has(key):
		return {
			"dependency":      0,
			"trust":           50,
			"debt":            0,
			"alignment":       int(Alignment.NEUTRAL),
			"last_veto_year": -1,
		}
	return (_state_inst[key] as Dictionary).duplicate()


func set_dependency(kingdom_id: String, institution_id: String, value: int) -> void:
	var e: Dictionary = _ensure_si(kingdom_id, institution_id)
	var v: int = clampi(value, 0, 100)
	if int(e["dependency"]) == v:
		return
	e["dependency"] = v
	state_institution_changed.emit(kingdom_id, institution_id, &"dependency", v)


func bump_dependency(kingdom_id: String, institution_id: String, delta: int) -> void:
	var e: Dictionary = _ensure_si(kingdom_id, institution_id)
	set_dependency(kingdom_id, institution_id, int(e["dependency"]) + delta)


func set_trust(kingdom_id: String, institution_id: String, value: int) -> void:
	var e: Dictionary = _ensure_si(kingdom_id, institution_id)
	var v: int = clampi(value, 0, 100)
	if int(e["trust"]) == v:
		return
	e["trust"] = v
	state_institution_changed.emit(kingdom_id, institution_id, &"trust", v)


func bump_trust(kingdom_id: String, institution_id: String, delta: int) -> void:
	var e: Dictionary = _ensure_si(kingdom_id, institution_id)
	set_trust(kingdom_id, institution_id, int(e["trust"]) + delta)


func set_debt(kingdom_id: String, institution_id: String, value: int) -> void:
	var e: Dictionary = _ensure_si(kingdom_id, institution_id)
	var v: int = max(0, value)
	if int(e["debt"]) == v:
		return
	e["debt"] = v
	state_institution_changed.emit(kingdom_id, institution_id, &"debt", v)


func bump_debt(kingdom_id: String, institution_id: String, delta: int) -> void:
	var e: Dictionary = _ensure_si(kingdom_id, institution_id)
	set_debt(kingdom_id, institution_id, int(e["debt"]) + delta)


func set_alignment(kingdom_id: String, institution_id: String, alignment: int) -> void:
	var e: Dictionary = _ensure_si(kingdom_id, institution_id)
	if int(e["alignment"]) == alignment:
		return
	e["alignment"] = alignment
	state_institution_changed.emit(kingdom_id, institution_id, &"alignment", alignment)


## Every (kingdom_id, institution_id) pair the module knows about.
## Useful for audit UI and iteration.
func all_state_institution_pairs() -> Array:
	var out: Array = []
	for key in _state_inst.keys():
		var parts: PackedStringArray = String(key).split("|")
		if parts.size() == 2:
			out.append([parts[0], parts[1]])
	return out


# --- Public: debt-driven veto (§B9 acceptance case) -------------------------

## Returns true if the bank currently has leverage over the kingdom:
## open debt exceeds the threshold AND they haven't used their veto
## this year yet. Call this from the kingdom's default / aggressive-
## fiscal code path before actually executing the action; if true,
## the caller should stand down and surface the veto letter.
func can_bank_veto(kingdom_id: String, house_id: String) -> bool:
	var e: Dictionary = _ensure_si(kingdom_id, house_id)
	if int(e["debt"]) < BANK_VETO_DEBT_THRESHOLD:
		return false
	return int(e["last_veto_year"]) != GameClock.year


## Consume the annual veto and emit the signal + a public event.
## Returns true if the veto fired, false if it was already spent or
## the debt threshold was not met (caller should not have asked, but
## we check anyway to avoid silent waste).
func consume_bank_veto(kingdom_id: String, house_id: String, attempted_amount: int = 0) -> bool:
	if not can_bank_veto(kingdom_id, house_id):
		return false
	var e: Dictionary = _ensure_si(kingdom_id, house_id)
	e["last_veto_year"] = GameClock.year
	bank_vetoed_default.emit(kingdom_id, house_id, attempted_amount)
	var k: Kingdom = WorldData.get_kingdom(kingdom_id)
	var house: BankingHouse = Finance.get_house(StringName(house_id))
	var k_name: String = k.kingdom_name if k != null else kingdom_id
	var house_name: String = house.display_name if house != null else house_id
	EventBus.public_event.emit({
		"kind":       &"bank_veto",
		"kingdom_id": kingdom_id,
		"institution_id": house_id,
		"headline":   "%s leans on %s" % [house_name, k_name],
		"body":       "Your man in the treasury has been told to say no. The ledger is not balanced, and the house has made it plain that balancing it is not a service to be interrupted.",
	})
	return true


# --- Public: institution ↔ institution --------------------------------------

func _ii_key(a_id: String, b_id: String) -> String:
	if a_id < b_id:
		return "%s|%s" % [a_id, b_id]
	return "%s|%s" % [b_id, a_id]


func _ensure_ii(a_id: String, b_id: String) -> Dictionary:
	var key: String = _ii_key(a_id, b_id)
	if not _inst_inst.has(key):
		_inst_inst[key] = {
			"state":  int(InstState.NEUTRAL),
			"blocks": {},   # province_id -> absolute_day_until
		}
	return _inst_inst[key]


func institution_state(a_id: String, b_id: String) -> int:
	var key: String = _ii_key(a_id, b_id)
	if not _inst_inst.has(key):
		return int(InstState.NEUTRAL)
	return int((_inst_inst[key] as Dictionary).get("state", int(InstState.NEUTRAL)))


func set_institution_state(a_id: String, b_id: String, state: int) -> void:
	if a_id == b_id:
		return
	var e: Dictionary = _ensure_ii(a_id, b_id)
	if int(e["state"]) == state:
		return
	e["state"] = state
	institution_institution_changed.emit(a_id, b_id, state)


## Institution `a_id` blocks `b_id` from operating in `province_id`
## until `until_abs_day`. If the pair state isn't already RIVAL it
## bumps to RIVAL on the first block.
func block_in_province(a_id: String, b_id: String, province_id: String, days: int = DEFAULT_BLOCK_DAYS) -> void:
	if a_id == b_id or province_id == "":
		return
	var e: Dictionary = _ensure_ii(a_id, b_id)
	var until: int = GameClock.absolute_day() + max(1, days)
	(e["blocks"] as Dictionary)[province_id] = until
	if int(e["state"]) != int(InstState.RIVAL):
		e["state"] = int(InstState.RIVAL)
		institution_institution_changed.emit(a_id, b_id, int(InstState.RIVAL))
	institution_blocked.emit(a_id, b_id, province_id, until)


## True if either institution blocks the other in `province_id` at
## time `abs_day` (defaults to today). Order-independent since we
## store sorted. Used by RivalRegistry / Org recruitment checks.
func is_blocked_in_province(a_id: String, b_id: String, province_id: String) -> bool:
	var key: String = _ii_key(a_id, b_id)
	if not _inst_inst.has(key):
		return false
	var blocks: Dictionary = (_inst_inst[key] as Dictionary).get("blocks", {})
	var until: int = int(blocks.get(province_id, 0))
	return until > GameClock.absolute_day()


## Returns every institution id that blocks `me_id` in `province_id`
## right now. Useful for surfacing the reason to the player.
func blockers_of(me_id: String, province_id: String) -> Array[String]:
	var out: Array[String] = []
	for key in _inst_inst.keys():
		var parts: PackedStringArray = String(key).split("|")
		if parts.size() != 2:
			continue
		if parts[0] != me_id and parts[1] != me_id:
			continue
		var other: String = parts[1] if parts[0] == me_id else parts[0]
		var blocks: Dictionary = (_inst_inst[key] as Dictionary).get("blocks", {})
		if int(blocks.get(province_id, 0)) > GameClock.absolute_day():
			out.append(other)
	return out


# --- Save/load --------------------------------------------------------------

func snapshot() -> Dictionary:
	var state_inst_out: Dictionary = {}
	for k in _state_inst.keys():
		state_inst_out[String(k)] = (_state_inst[k] as Dictionary).duplicate()
	var inst_inst_out: Dictionary = {}
	for k in _inst_inst.keys():
		var e: Dictionary = _inst_inst[k]
		inst_inst_out[String(k)] = {
			"state":  int(e.get("state", int(InstState.NEUTRAL))),
			"blocks": (e.get("blocks", {}) as Dictionary).duplicate(),
		}
	return {
		"state_inst": state_inst_out,
		"inst_inst":  inst_inst_out,
	}


func restore(d: Dictionary) -> void:
	_state_inst.clear()
	_inst_inst.clear()
	var si_raw: Variant = d.get("state_inst", {})
	if si_raw is Dictionary:
		for k in (si_raw as Dictionary).keys():
			var raw_v: Variant = si_raw[k]
			var raw: Dictionary = raw_v if raw_v is Dictionary else {}
			_state_inst[String(k)] = {
				"dependency":     int(raw.get("dependency", 0)),
				"trust":          int(raw.get("trust", 50)),
				"debt":           int(raw.get("debt", 0)),
				"alignment":      int(raw.get("alignment", int(Alignment.NEUTRAL))),
				"last_veto_year": int(raw.get("last_veto_year", -1)),
			}
	var ii_raw: Variant = d.get("inst_inst", {})
	if ii_raw is Dictionary:
		for k in (ii_raw as Dictionary).keys():
			var raw2_v: Variant = ii_raw[k]
			var raw2: Dictionary = raw2_v if raw2_v is Dictionary else {}
			var blocks_v: Variant = raw2.get("blocks", {})
			var blocks_raw: Dictionary = blocks_v if blocks_v is Dictionary else {}
			var blocks_norm: Dictionary = {}
			for pid in blocks_raw.keys():
				blocks_norm[String(pid)] = int(blocks_raw[pid])
			_inst_inst[String(k)] = {
				"state":  int(raw2.get("state", int(InstState.NEUTRAL))),
				"blocks": blocks_norm,
			}
