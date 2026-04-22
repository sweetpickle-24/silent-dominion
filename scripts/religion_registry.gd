extends Node
## Autoloaded as `Religions`. Religion registry + lifecycle ticks (§25).
##
## Loads the seed pantheons from `data/religions_500bce.json` after
## WorldData is up. Each month every religion drifts on its phase-
## specific curves: emergence claws upward, consolidation hardens
## institutions, dominance breeds reform pressure, fracture either
## resolves or turns into decline. Religions that fall below survival
## thresholds slip out of provinces but are not deleted — a faded
## pantheon may still see a revival a century later.
##
## Public events fire on phase transitions and on schism. Day-to-day
## drift is silent — these systems are visible to the player only
## through their effects on actor traits and on what gets announced.

signal religion_added(id: StringName)
signal religion_phase_changed(id: StringName, prev_phase: int, new_phase: int)
signal religion_share_changed(religion_id: StringName, province_id: String)

const RELIGION_DATA_PATH: String = "res://data/religions_500bce.json"

# Phase transition thresholds.
const EMERGE_TO_CONS_DEPTH:       int = 25
const CONS_TO_DOM_INSTITUTION:    int = 60
const CONS_TO_DOM_DEPTH:          int = 50
const DOM_TO_FRACTURE_REFORM:     int = 75
const FRACTURE_RESOLVE_REFORM:    int = 35    # below this, fracture heals
const FRACTURE_TO_DECLINE_INST:   int = 25
const DECLINE_TO_REVIVAL_DEPTH:   int = 60    # rare; below this in DECLINE we stay there
const EXTINCTION_DEPTH:           int = 4

# Spread mechanics.
const NEIGHBOUR_SPREAD_CHANCE:    float = 0.04   # per faith / per neighbour province / month
const SPREAD_BASE_PERCENT:        int   = 1
const FRINGE_DECAY_THRESHOLD:     int   = 8     # presence below this can decay away in DECLINE

# Pacing of attribute drift. All ranges are per-month.
const DRIFT_INSTITUTION_CONSOLIDATING: int = 1
const DRIFT_INSTITUTION_DOMINANCE:     int = 0
const DRIFT_DEPTH_EMERGENCE:           int = 1
const DRIFT_DEPTH_DOMINANCE:           int = 0
const DRIFT_REFORM_DOMINANCE_HIGH_RIGIDITY: int = 1
const DRIFT_REFORM_FRACTURE:           int = -2
const DRIFT_DEPTH_DECLINE:             int = -1
const DRIFT_INSTITUTION_DECLINE:       int = -1

# id -> Religion
var religions: Dictionary = {}

# Cached neighbour map: province_id -> Array[String] of adjacent ids.
# Lazy-built from MapData if available.
var _neighbours: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Months a religion has been in fracture, indexed by id. Lets us
# delay the resolve/decline branch so a single bad reform reading
# doesn't immediately break a faith.
var _fracture_months: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	if not WorldData.is_loaded():
		WorldData.world_loaded.connect(_seed)
	else:
		_seed()
	GameClock.month_passed.connect(_on_month_passed)


# --- Public API --------------------------------------------------------------

func get_religion(id: StringName) -> Religion:
	return religions.get(id, null)


func all_religions() -> Array[Religion]:
	var out: Array[Religion] = []
	for r in religions.values():
		out.append(r)
	return out


## Religion holding the largest share of a given province, or null
## if none has any presence.
func dominant_in(province_id: String) -> Religion:
	var best: Religion = null
	var best_share: int = 0
	for r in religions.values():
		var s: int = r.share_in(province_id)
		if s > best_share:
			best_share = s
			best = r
	return best


## All religions with any presence in a province, sorted descending
## by share. Useful for the map detail panel.
func all_in(province_id: String) -> Array:
	var entries: Array = []
	for r in religions.values():
		var s: int = r.share_in(province_id)
		if s > 0:
			entries.append({"religion": r, "share": s})
	entries.sort_custom(func(a, b): return int(a["share"]) > int(b["share"]))
	return entries


## Average piety bias contributed by all religions present in a
## province, weighted by share. Used by ActorRegistry's regional
## weighting to nudge piety in newly generated minor characters.
func piety_bias_for(province_id: String) -> int:
	var bias: float = 0.0
	for r in religions.values():
		var s: int = r.share_in(province_id)
		if s <= 0:
			continue
		# A deep faith with a popular_depth of 80 contributes more than
		# a thin one with 30, weighted by how much of the province
		# follows it.
		bias += float(r.popular_depth) * float(s) / 100.0
	return int(round(bias / 100.0 * 30.0))   # bounded to ~±30 in practice


# --- Seeding -----------------------------------------------------------------

func _seed() -> void:
	if not religions.is_empty():
		return
	var f: FileAccess = FileAccess.open(RELIGION_DATA_PATH, FileAccess.READ)
	if f == null:
		push_warning("Religions: could not open %s" % RELIGION_DATA_PATH)
		return
	var blob: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(blob) != TYPE_DICTIONARY:
		push_warning("Religions: malformed seed file")
		return
	for entry in blob.get("religions", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var r: Religion = Religion.from_dict(entry)
		if r.id == &"":
			continue
		religions[r.id] = r
		religion_added.emit(r.id)


# --- Monthly tick ------------------------------------------------------------

func _on_month_passed(_y: int, _m: int) -> void:
	if religions.is_empty():
		return
	for r in religions.values():
		_drift_attributes(r)
		_check_phase_transition(r)
		_tick_presence(r)


func _drift_attributes(r: Religion) -> void:
	match r.phase:
		Religion.Phase.EMERGENCE:
			r.popular_depth = clampi(r.popular_depth + DRIFT_DEPTH_EMERGENCE, 0, 100)
			r.institutional_strength = clampi(r.institutional_strength + 1, 0, 100)
		Religion.Phase.CONSOLIDATION:
			r.institutional_strength = clampi(
				r.institutional_strength + DRIFT_INSTITUTION_CONSOLIDATING, 0, 100
			)
			# Doctrinal rigidity hardens slowly during consolidation.
			if _rng.randf() < 0.10:
				r.doctrinal_rigidity = clampi(r.doctrinal_rigidity + 1, 0, 100)
		Religion.Phase.DOMINANCE:
			# Reform pressure builds, faster when the institution has
			# outpaced popular faith — the classic clerical hypocrisy
			# spiral.
			if r.institutional_strength > r.popular_depth + 15:
				r.reform_potential = clampi(r.reform_potential + 1, 0, 100)
			# High-rigidity faiths build reform faster: the brittler
			# the doctrine, the more grievance accumulates.
			if r.doctrinal_rigidity >= 70 and _rng.randf() < 0.20:
				r.reform_potential = clampi(
					r.reform_potential + DRIFT_REFORM_DOMINANCE_HIGH_RIGIDITY, 0, 100
				)
		Religion.Phase.FRACTURE:
			# A schism either burns through and resolves, or it
			# corrodes the institution.
			r.institutional_strength = clampi(r.institutional_strength - 1, 0, 100)
			if _rng.randf() < 0.30:
				r.popular_depth = clampi(r.popular_depth - 1, 0, 100)
			r.reform_potential = clampi(
				r.reform_potential + DRIFT_REFORM_FRACTURE, 0, 100
			)
		Religion.Phase.DECLINE:
			r.popular_depth          = clampi(r.popular_depth + DRIFT_DEPTH_DECLINE, 0, 100)
			r.institutional_strength = clampi(r.institutional_strength + DRIFT_INSTITUTION_DECLINE, 0, 100)


func _check_phase_transition(r: Religion) -> void:
	var prev: Religion.Phase = r.phase
	match r.phase:
		Religion.Phase.EMERGENCE:
			if r.popular_depth >= EMERGE_TO_CONS_DEPTH:
				r.phase = Religion.Phase.CONSOLIDATION
		Religion.Phase.CONSOLIDATION:
			if (
				r.institutional_strength >= CONS_TO_DOM_INSTITUTION
				and r.popular_depth >= CONS_TO_DOM_DEPTH
			):
				r.phase = Religion.Phase.DOMINANCE
		Religion.Phase.DOMINANCE:
			if r.reform_potential >= DOM_TO_FRACTURE_REFORM:
				r.phase = Religion.Phase.FRACTURE
				_fracture_months[r.id] = 0
		Religion.Phase.FRACTURE:
			var months: int = int(_fracture_months.get(r.id, 0)) + 1
			_fracture_months[r.id] = months
			if r.reform_potential <= FRACTURE_RESOLVE_REFORM:
				# Schism died down — back to dominance, lighter on
				# institution, lighter on rigidity.
				r.phase = Religion.Phase.DOMINANCE
				_fracture_months.erase(r.id)
				_split_religion(r)   # the schism still leaves a child
			elif months >= 24 and r.institutional_strength <= FRACTURE_TO_DECLINE_INST:
				r.phase = Religion.Phase.DECLINE
				_fracture_months.erase(r.id)
		Religion.Phase.DECLINE:
			if r.popular_depth >= DECLINE_TO_REVIVAL_DEPTH:
				r.phase = Religion.Phase.CONSOLIDATION
	if r.phase != prev:
		religion_phase_changed.emit(r.id, int(prev), int(r.phase))
		_announce_phase_transition(r, prev)


func _tick_presence(r: Religion) -> void:
	# Spread to neighbouring provinces during emergence, consolidation,
	# and dominance. In fracture/decline we don't spread — we may shed.
	if r.phase == Religion.Phase.DECLINE:
		_decay_fringes(r)
		return
	if r.phase == Religion.Phase.FRACTURE:
		return
	# Pick one or two seed provinces to try spreading from.
	var seeds: Array = r.presence.keys()
	if seeds.is_empty():
		return
	var rolls: int = 1 if seeds.size() < 6 else 2
	for _i in range(rolls):
		var src_pid: String = String(seeds[_rng.randi_range(0, seeds.size() - 1)])
		_try_spread_from(r, src_pid)


func _try_spread_from(r: Religion, src_pid: String) -> void:
	if _rng.randf() >= NEIGHBOUR_SPREAD_CHANCE:
		return
	var neighbours: Array = _neighbours_of(src_pid)
	if neighbours.is_empty():
		return
	var nbr_pid: String = String(neighbours[_rng.randi_range(0, neighbours.size() - 1)])
	# Don't overwrite a faith that is dominant there — that needs a
	# fracture or hostile push, not gentle drift.
	var current: int = r.share_in(nbr_pid)
	var dominant: Religion = dominant_in(nbr_pid)
	if dominant != null and dominant != r and dominant.share_in(nbr_pid) >= 75:
		return
	var bump: int = SPREAD_BASE_PERCENT
	if r.ecumenical_openness >= 60:
		bump += 1
	r.set_share(nbr_pid, current + bump)
	if dominant != null and dominant != r:
		dominant.set_share(nbr_pid, dominant.share_in(nbr_pid) - 1)
		religion_share_changed.emit(dominant.id, nbr_pid)
	religion_share_changed.emit(r.id, nbr_pid)


func _decay_fringes(r: Religion) -> void:
	var doomed: Array = []
	for pid in r.presence.keys():
		if int(r.presence[pid]) <= FRINGE_DECAY_THRESHOLD:
			doomed.append(pid)
	if doomed.is_empty():
		return
	var to_drop: String = String(doomed[_rng.randi_range(0, doomed.size() - 1)])
	r.set_share(to_drop, 0)
	religion_share_changed.emit(r.id, to_drop)


func _split_religion(parent: Religion) -> void:
	# Spawn a child faith carrying the reformer doctrine. It inherits
	# half of the parent's lowest-share provinces and starts in
	# emergence with high reform potential of its own.
	var child_id: StringName = StringName("%s_reform" % String(parent.id))
	if religions.has(child_id):
		return   # don't double-split
	var child: Religion = Religion.new()
	child.id                    = child_id
	child.religion_name         = "Reformed %s" % parent.religion_name
	child.phase                 = Religion.Phase.EMERGENCE
	child.doctrinal_rigidity    = clampi(parent.doctrinal_rigidity - 15, 5, 95)
	child.institutional_strength = 15
	child.popular_depth         = 20
	child.reform_potential      = 10
	child.ecumenical_openness   = clampi(parent.ecumenical_openness + 10, 5, 95)
	child.founded_year          = -GameClock.year
	child.parent_religion_id    = parent.id
	# Inherit seed presence from the lowest-share provinces of the
	# parent — the periphery is where reformers find purchase.
	var parent_keys: Array = parent.presence.keys()
	parent_keys.sort_custom(func(a, b):
		return int(parent.presence[a]) < int(parent.presence[b]))
	for i in range(min(3, parent_keys.size())):
		var pid: String = String(parent_keys[i])
		var take: int = int(round(float(parent.presence[pid]) * 0.4))
		if take <= 0:
			continue
		child.set_share(pid, take)
		parent.set_share(pid, parent.share_in(pid) - take)
		religion_share_changed.emit(parent.id, pid)
		religion_share_changed.emit(child.id, pid)
	religions[child.id] = child
	religion_added.emit(child.id)
	EventBus.public_event.emit({
		"kind":     &"religion_schism",
		"channel":  "neutral",
		"headline": "Schism in the %s" % parent.religion_name,
		"body":     "Word from preachers and pilgrims alike: the reformers within the %s have broken with the central hierarchy. The new movement, calling itself the %s, is gathering in the provinces. The old institution dismisses them; the markets have stopped dismissing them." % [
			parent.religion_name, child.religion_name,
		],
	})


func _announce_phase_transition(r: Religion, prev_phase: Religion.Phase) -> void:
	var headline: String
	var body: String
	match r.phase:
		Religion.Phase.CONSOLIDATION:
			if prev_phase == Religion.Phase.EMERGENCE:
				headline = "%s coheres into a faith" % r.religion_name
				body = "What was a movement is now a church. The %s has produced its first canon, its first quarrels about the canon, and its first heretics." % r.religion_name
			else:
				return
		Religion.Phase.DOMINANCE:
			headline = "%s now reigns" % r.religion_name
			body = "The %s is established. Its priests sit at courts; its festivals fix the calendar; its silences are louder than other faiths' arguments." % r.religion_name
		Religion.Phase.FRACTURE:
			headline = "Cracks in the %s" % r.religion_name
			body = "Reformers, heretics, dissenters — the names differ from province to province. The substance is the same: the %s is no longer one church." % r.religion_name
		Religion.Phase.DECLINE:
			headline = "The %s loses its grip" % r.religion_name
			body = "Empty temples in the old strongholds. Festivals attended by the elderly. Whatever the %s once compelled, it now only requests." % r.religion_name
		_:
			return
	EventBus.public_event.emit({
		"kind":     &"religion_phase",
		"channel":  "neutral",
		"headline": headline,
		"body":     body,
	})


# --- Neighbour cache ---------------------------------------------------------

func _neighbours_of(pid: String) -> Array:
	if _neighbours.has(pid):
		return _neighbours[pid]
	# Geographic adjacency would be ideal but the map layer doesn't
	# expose it yet. Same-kingdom provinces stand in for now: faiths
	# spread through the realms that already host them. Cross-kingdom
	# bleed happens through the seed presence rather than drift.
	var result: Array = []
	var p: Province = WorldData.get_province(pid)
	if p != null:
		var k: Kingdom = WorldData.get_kingdom(p.owning_kingdom)
		if k != null:
			for other in k.owned_provinces:
				if other != pid:
					result.append(other)
	_neighbours[pid] = result
	return result


# --- Save / load -------------------------------------------------------------

func snapshot() -> Dictionary:
	var arr: Array = []
	for r in religions.values():
		arr.append(r.to_dict())
	return {
		"religions":         arr,
		"_fracture_months":  _fracture_months.duplicate(true),
	}


func restore(d: Dictionary) -> void:
	religions.clear()
	for entry in d.get("religions", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var r: Religion = Religion.from_dict(entry)
		if r.id == &"":
			continue
		religions[r.id] = r
	_fracture_months = (d.get("_fracture_months", {}) as Dictionary).duplicate(true)
