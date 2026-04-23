extends Node
## Autoloaded as `Unrest`. Province-level unrest field.
##
## Each province carries a 0–100 unrest scalar. The number is never
## shown — the Map panel reads Province.unrest_phrase() / unrest_band()
## instead. The scalar moves in response to:
##   - successful covert actions targeting actors in the province
##     (rumour, plant_idea, host_agitate)
##   - heavy or ruinous tax benches in the owning kingdom (monthly)
##   - active war in the owning kingdom (monthly)
##   - natural decay toward zero
## When unrest crosses into 'seething' or 'in revolt', a public news
## dispatch is issued so the player can see the shift without opening
## every province.

signal province_unrest_changed(province_id: String)

const DECAY_PER_MONTH: int = 2

const BURDENED_TICK: int    = 2
const RUINOUS_TICK: int     = 5
const WAR_TICK: int         = 3

const RUMOUR_BUMP: int        = 6
const IDEA_BUMP: int          = 5
const AGITATE_BUMP: int       = 10
const BROKE_TREASURY_TICK: int = 3

var _last_band: Dictionary = {}   # province_id -> StringName
var _revolt_streak: Dictionary = {}   # province_id -> consecutive months in revolt

const PROLONGED_REVOLT_MONTHS: int = 6


func _ready() -> void:
	DevLogger.write("Unrest: ready")
	GameClock.month_passed.connect(_on_month_passed)
	EventBus.action_resolved.connect(_on_action_resolved)


# --- Public API --------------------------------------------------------------

func get_unrest(province_id: String) -> int:
	var p: Province = WorldData.get_province(province_id)
	return 0 if p == null else p.unrest


func bump(province_id: String, delta: int) -> void:
	var p: Province = WorldData.get_province(province_id)
	if p == null:
		return
	var old_band: StringName = p.unrest_band()
	p.unrest = clampi(p.unrest + delta, 0, 100)
	province_unrest_changed.emit(province_id)
	var new_band: StringName = p.unrest_band()
	if new_band != old_band:
		_maybe_announce(p, old_band, new_band)
		_last_band[province_id] = new_band


func snapshot() -> Array:
	var out: Array = []
	for p in WorldData.provinces.values():
		out.append({
			"id":            p.id,
			"unrest":        p.unrest,
			"revolt_streak": int(_revolt_streak.get(p.id, 0)),
		})
	return out


func restore(arr: Array) -> void:
	_revolt_streak.clear()
	for d in arr:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var p: Province = WorldData.get_province(String(d.get("id", "")))
		if p == null:
			continue
		p.unrest = int(d.get("unrest", 0))
		_last_band[p.id] = p.unrest_band()
		_revolt_streak[p.id] = int(d.get("revolt_streak", 0))


# --- Monthly tick ------------------------------------------------------------

func _on_month_passed(_y: int, _m: int) -> void:
	if not WorldData.is_loaded():
		return
	for p in WorldData.provinces.values():
		if p.population <= 0:
			continue   # sea / empty provinces
		var delta: int = -DECAY_PER_MONTH

		var k: Kingdom = WorldData.get_kingdom(p.owning_kingdom)
		if k != null:
			match k.tax_level:
				Kingdom.TaxLevel.BURDENED: delta += BURDENED_TICK
				Kingdom.TaxLevel.RUINOUS:  delta += RUINOUS_TICK
				_: pass
			if k.treasury_condition == Kingdom.TreasuryCondition.BROKE:
				delta += BROKE_TREASURY_TICK
			if _kingdom_is_at_war(k.id):
				delta += WAR_TICK

		if delta != 0:
			bump(p.id, delta)

		_track_revolt_streak(p)


func _track_revolt_streak(p: Province) -> void:
	var in_revolt: bool = p.unrest_band() == &"in revolt"
	var streak: int = int(_revolt_streak.get(p.id, 0))
	if in_revolt:
		streak += 1
		_revolt_streak[p.id] = streak
		if streak == PROLONGED_REVOLT_MONTHS:
			_emit_prolonged_revolt(p)
	else:
		if streak > 0:
			_revolt_streak[p.id] = 0


func _emit_prolonged_revolt(p: Province) -> void:
	var k: Kingdom = WorldData.get_kingdom(p.owning_kingdom)
	var kname: String = k.kingdom_name if k != null else p.owning_kingdom
	EventBus.public_event.emit({
		"kind":       &"unrest",
		"kingdom_id": p.owning_kingdom,
		"headline":   "%s is lost to its crown" % p.province_name,
		"body":       "Half a year of open revolt in %s. The crown of %s still names the province on its maps, but no silver comes out of it, no soldiers answer from it, and the priests have stopped pretending the magistrates are in charge." % [
			p.province_name, kname,
		],
	})


func _kingdom_is_at_war(kingdom_id: String) -> bool:
	return not Relations.ids_in_state(kingdom_id, int(Relations.RelationState.AT_WAR)).is_empty()


# --- Action-driven bumps -----------------------------------------------------

func _on_action_resolved(action_id: StringName, result: Dictionary) -> void:
	if not bool(result.get("success", false)):
		return
	var target_id: String = String(result.get("target_id", ""))
	if target_id == "":
		return
	var actor: Actor = Actors.get_actor(StringName(target_id))
	if actor == null:
		return
	var province_id: String = _province_for_actor(actor)
	if province_id == "":
		return

	match action_id:
		&"seed_rumour":  bump(province_id, RUMOUR_BUMP)
		&"plant_idea":   bump(province_id, IDEA_BUMP)
		&"host_agitate": bump(province_id, AGITATE_BUMP)


## The province an actor lives in. Actors live in a kingdom; we pick
## the first province owned by that kingdom with any population, which
## is a fair stand-in for 'the capital'.
func _province_for_actor(actor: Actor) -> String:
	var k: Kingdom = WorldData.get_kingdom(actor.kingdom_id)
	if k == null:
		return ""
	for pid in k.owned_provinces:
		var p: Province = WorldData.get_province(pid)
		if p != null and p.population > 0:
			return p.id
	return ""


# --- Announcements -----------------------------------------------------------

func _maybe_announce(p: Province, old_band: StringName, new_band: StringName) -> void:
	# Only surface meaningful crossings. Crossing downward is just noise.
	if not _is_worse(new_band, old_band):
		return
	if new_band != &"seething" and new_band != &"in revolt":
		return

	var k: Kingdom = WorldData.get_kingdom(p.owning_kingdom)
	var kname: String = k.kingdom_name if k != null else p.owning_kingdom
	var headline: String
	var body: String
	if new_band == &"seething":
		headline = "%s grows restless" % p.province_name
		body = "From %s in %s: broadsides on the walls, raised voices in the agora. The crown's name is being said in the wrong tones." % [
			p.province_name, kname,
		]
	else:
		headline = "%s is in open revolt" % p.province_name
		body = "The province of %s (%s) is past orderly. Stones in the square, doors barred, names shouted. The guard is thin on the ground." % [
			p.province_name, kname,
		]

	EventBus.public_event.emit({
		"kind":       &"unrest",
		"kingdom_id": p.owning_kingdom,
		"headline":   headline,
		"body":       body,
	})


func _is_worse(a: StringName, b: StringName) -> bool:
	var order: Array[StringName] = [&"quiet", &"uneasy", &"restless", &"seething", &"in revolt"]
	return order.find(a) > order.find(b)
