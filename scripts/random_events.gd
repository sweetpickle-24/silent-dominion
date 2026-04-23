extends Node
## Autoloaded as `RandomEvents`. Seasonal catastrophe roller.
##
## Once per in-game month, rolls a small chance for one of four
## rare natural events to land on a populated province:
##   - plague      — a sharp unrest bump and a lingering production
##                   cut for six months via a scheduled recovery.
##   - famine      — softer unrest, one year of modest production cut.
##   - earthquake  — immediate treasury blow to the owning crown plus
##                   an unrest bump; no lingering modifier.
##   - comet       — no hard effects; publishes a portent dispatch
##                   and moderately shifts piety-heavy actors.
##
## Production cuts are applied by stashing the pre-event production
## on the Province and multiplying it; the recovery task on the
## Scheduler restores the originals and publishes a short note.
##
## All effects surface as public_event dispatches so the scroll and
## monthly digest pick them up. Saves persist in-flight recoveries
## through the Scheduler's own snapshot/restore (these are just
## descriptors with a known `kind`).

const TASK_KIND: StringName = &"event_recovery"

# Per-month per-province probabilities. Rare on purpose — a world
# that plagues itself every season loses all weight.
const P_PLAGUE_PER_MONTH: float     = 0.004
const P_FAMINE_PER_MONTH: float     = 0.006
const P_EARTHQUAKE_PER_MONTH: float = 0.003
const P_COMET_PER_YEAR: float       = 0.05   # rolled once each January

const UNREST_PLAGUE: int     = 28
const UNREST_FAMINE: int     = 14
const UNREST_EARTHQUAKE: int = 18

const PLAGUE_YIELD: float     = 0.50
const PLAGUE_MONTHS: int      = 6
const FAMINE_YIELD: float     = 0.70
const FAMINE_MONTHS: int      = 12
const EARTHQUAKE_SILVER: float = 18.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	DevLogger.write("RandomEvents: ready")
	_rng.randomize()
	GameClock.month_passed.connect(_on_month_passed)
	Scheduler.task_due.connect(_on_task_due)


# --- Monthly roll ------------------------------------------------------------

func _on_month_passed(_y: int, m: int) -> void:
	if not WorldData.is_loaded():
		return
	for p in WorldData.provinces.values():
		if p.population <= 0:
			continue
		_roll_plague(p)
		_roll_famine(p)
		_roll_earthquake(p)
	# Comets are a yearly affair.
	if m == 1 and _rng.randf() < P_COMET_PER_YEAR:
		_fire_comet()


func _roll_plague(p: Province) -> void:
	if _rng.randf() >= P_PLAGUE_PER_MONTH:
		return
	if _is_modifier_active(p):
		return
	_apply_production_modifier(p, PLAGUE_YIELD, PLAGUE_MONTHS, &"plague")
	# A crown granary doesn't stop pestilence but it softens the panic
	# in the markets — less run on the bakers, less unrest.
	var bump: int = UNREST_PLAGUE
	if p.has_building(&"granary"):
		bump = int(round(float(bump) * 0.7))
	Unrest.bump(p.id, bump)
	_publish_plague(p)


func _roll_famine(p: Province) -> void:
	if _rng.randf() >= P_FAMINE_PER_MONTH:
		return
	if _is_modifier_active(p):
		return
	_apply_production_modifier(p, FAMINE_YIELD, FAMINE_MONTHS, &"famine")
	var bump: int = UNREST_FAMINE
	if p.has_building(&"granary"):
		bump = int(round(float(bump) * 0.5))
	Unrest.bump(p.id, bump)
	_publish_famine(p)


func _roll_earthquake(p: Province) -> void:
	if _rng.randf() >= P_EARTHQUAKE_PER_MONTH:
		return
	Unrest.bump(p.id, UNREST_EARTHQUAKE)
	var k: Kingdom = WorldData.get_kingdom(p.owning_kingdom)
	if k != null:
		k.treasury_silver = max(0.0, k.treasury_silver - EARTHQUAKE_SILVER)
	_publish_earthquake(p)


# --- Production modifier lifecycle ------------------------------------------

func _is_modifier_active(p: Province) -> bool:
	return p.has_meta("prod_modifier")


func _apply_production_modifier(p: Province, yield_mult: float, months: int, cause: StringName) -> void:
	# Stash the pristine production numbers so we can restore them
	# cleanly at the end of the recovery period regardless of any
	# other tinkering.
	var originals: Dictionary = {
		"grain":  p.grain_production,
		"silver": p.silver_production,
		"iron":   p.iron_production,
		"timber": p.timber_production,
	}
	p.set_meta("prod_modifier", {
		"originals": originals,
		"cause":     String(cause),
	})
	p.grain_production  *= yield_mult
	p.silver_production *= yield_mult
	p.iron_production   *= yield_mult
	p.timber_production *= yield_mult

	Scheduler.schedule_task_in_days(months * 30, {
		"kind":        String(TASK_KIND),
		"province_id": p.id,
	})


func _on_task_due(descriptor: Dictionary) -> void:
	if String(descriptor.get("kind", "")) != String(TASK_KIND):
		return
	var pid: String = String(descriptor.get("province_id", ""))
	if pid == "":
		return
	var p: Province = WorldData.get_province(pid)
	if p == null or not p.has_meta("prod_modifier"):
		return
	var meta: Dictionary = p.get_meta("prod_modifier")
	var originals: Dictionary = meta.get("originals", {})
	p.grain_production  = float(originals.get("grain",  p.grain_production))
	p.silver_production = float(originals.get("silver", p.silver_production))
	p.iron_production   = float(originals.get("iron",   p.iron_production))
	p.timber_production = float(originals.get("timber", p.timber_production))
	p.remove_meta("prod_modifier")
	_publish_recovery(p, StringName(String(meta.get("cause", "plague"))))


# --- Comet -------------------------------------------------------------------

func _fire_comet() -> void:
	var body: String = "A long-tailed star crossed the winter sky three nights running. The priests and diviners speak of it with one voice from different cities, which is rarer than the star itself."
	EventBus.public_event.emit({
		"kind":     &"portent",
		"headline": "A comet over the world",
		"body":     body,
	})
	# Piety-heavy actors read portents more seriously; nudge paranoia
	# upward just a touch in the very pious.
	for a in Actors.all_actors():
		if not a.is_alive():
			continue
		if a.piety > 70:
			a.paranoia = clampi(a.paranoia + 2, 0, 100)


# --- Dispatches --------------------------------------------------------------

func _publish_plague(p: Province) -> void:
	EventBus.public_event.emit({
		"kind":       &"plague",
		"kingdom_id": p.owning_kingdom,
		"province":   p.id,
		"headline":   "A fever in %s" % p.province_name,
		"body":       "Travellers from %s speak of doors marked with chalk and carts leaving at night. The markets are thin. Whatever grain is pulled from the fields this season will be pulled by fewer hands." % p.province_name,
	})


func _publish_famine(p: Province) -> void:
	EventBus.public_event.emit({
		"kind":       &"famine",
		"kingdom_id": p.owning_kingdom,
		"province":   p.id,
		"headline":   "A thin harvest in %s" % p.province_name,
		"body":       "The granaries of %s did not fill this season. The reasons are the usual ones — a dry month at the wrong time, a river that ran low — and the result is the usual one. The price of bread has doubled. The patience of the poor has not." % p.province_name,
	})


func _publish_earthquake(p: Province) -> void:
	var k: Kingdom = WorldData.get_kingdom(p.owning_kingdom)
	var kname: String = k.kingdom_name if k != null else p.owning_kingdom
	EventBus.public_event.emit({
		"kind":       &"earthquake",
		"kingdom_id": p.owning_kingdom,
		"province":   p.id,
		"headline":   "The ground moves under %s" % p.province_name,
		"body":       "A tremor in the night, then a longer one at dawn. Walls down in the lower quarters of %s; the crown of %s has already opened the treasury to the rebuilders. The priests read it for meaning. The quarrymen do not." % [
			p.province_name, kname,
		],
	})


## Capture every active production modifier so reloads restore the
## reduced values exactly and let the Scheduler's recovery task clear
## them cleanly when its fire day arrives.
func snapshot() -> Array:
	var out: Array = []
	if not WorldData.is_loaded():
		return out
	for p in WorldData.provinces.values():
		if not p.has_meta("prod_modifier"):
			continue
		var meta: Dictionary = p.get_meta("prod_modifier")
		out.append({
			"province_id": p.id,
			"originals":   (meta.get("originals", {}) as Dictionary).duplicate(),
			"cause":       String(meta.get("cause", "plague")),
			"current": {
				"grain":  p.grain_production,
				"silver": p.silver_production,
				"iron":   p.iron_production,
				"timber": p.timber_production,
			},
		})
	return out


func restore(arr: Array) -> void:
	if not WorldData.is_loaded():
		return
	# Clear any stale meta left on provinces from before the restore.
	for p in WorldData.provinces.values():
		if p.has_meta("prod_modifier"):
			p.remove_meta("prod_modifier")
	for entry in arr:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var p: Province = WorldData.get_province(String(entry.get("province_id", "")))
		if p == null:
			continue
		var cur_raw: Variant = entry.get("current", {})
		var current: Dictionary = cur_raw if cur_raw is Dictionary else {}
		p.grain_production  = float(current.get("grain",  p.grain_production))
		p.silver_production = float(current.get("silver", p.silver_production))
		p.iron_production   = float(current.get("iron",   p.iron_production))
		p.timber_production = float(current.get("timber", p.timber_production))
		var orig_raw: Variant = entry.get("originals", {})
		var originals: Dictionary = (orig_raw as Dictionary).duplicate() if orig_raw is Dictionary else {}
		p.set_meta("prod_modifier", {
			"originals": originals,
			"cause":     String(entry.get("cause", "plague")),
		})


func _publish_recovery(p: Province, cause: StringName) -> void:
	var phrase: String = "the season's troubles have passed"
	match cause:
		&"plague":
			phrase = "the fever has broken in %s" % p.province_name
		&"famine":
			phrase = "%s has brought in a fuller harvest" % p.province_name
		_:
			phrase = "%s has recovered" % p.province_name
	EventBus.public_event.emit({
		"kind":       &"recovery",
		"kingdom_id": p.owning_kingdom,
		"province":   p.id,
		"headline":   "Word from %s" % p.province_name,
		"body":       "Travellers bring better news this month: %s. The fields and wharves will not be themselves for some time, but the worst is behind them." % phrase,
	})
