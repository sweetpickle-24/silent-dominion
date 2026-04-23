extends Node
## Autoloaded as `Failures`. §12 — failure states.
##
## There is no *game over screen* except physical death in ironman
## conditions, but there are degraded states that end a playthrough's
## momentum. This manager watches the usual signals and flips on the
## matching state(s) when their entry conditions are met, along with
## the recovery path each one documents.
##
## States are sticky until their recovery criteria are met. The UI
## layer reads `is_active(state)` / `active_states()` to decide what
## to surface (a red bar across the table, say, or a terminal chrome
## change for EXPOSED).

signal state_entered(state: int, context: Dictionary)
signal state_recovered(state: int)
signal physical_death_triggered(context: Dictionary)


enum State {
	NETWORK_COLLAPSE,
	RIVAL_DOMINATION,
	IDEOLOGICAL_CAPTURE,
	EXPOSED_STATE,
	PHYSICAL_DEATH,
}


const STATE_NAMES: Dictionary = {
	State.NETWORK_COLLAPSE:    "Network collapse",
	State.RIVAL_DOMINATION:    "Rival domination",
	State.IDEOLOGICAL_CAPTURE: "Ideological capture",
	State.EXPOSED_STATE:       "The Exposed state",
	State.PHYSICAL_DEATH:      "Physical death",
}


const STATE_BLURBS: Dictionary = {
	State.NETWORK_COLLAPSE:    "Too many hosts burned in quick succession. The network will not carry another tier-2 operation for years. Go dark; rebuild slow.",
	State.RIVAL_DOMINATION:    "A rival society has achieved an objective while your attention was elsewhere. Their position is consolidating. Disrupt before it locks in.",
	State.IDEOLOGICAL_CAPTURE: "The dominant idea of the age has turned hostile to shadow work. Wait for the cycle; back the movement that will challenge it.",
	State.EXPOSED_STATE:       "Paid eyes have your scent. Burn your own hosts to break the trail. Accept the decades of impotence that follow.",
	State.PHYSICAL_DEATH:      "A ruler has named you. An inquisitor has your face. There is no recovery from this one.",
}


## Rolling window for "too many hosts burned in quick succession".
## Burn events outside this window are not counted toward collapse.
const BURN_WINDOW_DAYS: int = 540
## Count of burns inside the window that tips into network collapse.
const BURN_COLLAPSE_THRESHOLD: int = 3

## Exposure value at or above which EXPOSED_STATE latches.
const EXPOSED_FLOOR: float = 86.0

## When EXPOSED_STATE is on and the player's host count drops to zero
## (a self-burn or a chain of losses), they are considered off the
## grid enough to "outrun" the hunt — recovery.
## This manager doesn't force it; it checks these conditions monthly.

var _active: Dictionary = {}     # State(int) -> context Dict
var _burn_log: Array = []        # absolute days of recent host burns


func _ready() -> void:
	Org.member_burned.connect(_on_member_burned)
	Exposure.level_changed.connect(_on_exposure_level_changed)
	GameClock.month_passed.connect(_on_month_passed)


# --- Public API --------------------------------------------------------------

func is_active(s: int) -> bool:
	return _active.has(s)


func active_states() -> Array:
	return _active.keys()


func state_name(s: int) -> String:
	return String(STATE_NAMES.get(s, ""))


func state_blurb(s: int) -> String:
	return String(STATE_BLURBS.get(s, ""))


func context_for(s: int) -> Dictionary:
	return _active.get(s, {})


## External trigger — RivalRegistry can call this when an objective
## has locked in and we owe the player the acknowledgement.
func trigger_rival_domination(society_id: StringName, headline: String) -> void:
	if is_active(State.RIVAL_DOMINATION):
		return
	_enter(State.RIVAL_DOMINATION, {
		"society_id": String(society_id),
		"headline":   headline,
	})


## External trigger — ReligionRegistry / ambient ideology monitor can
## call this when a dominant faith or ideology crosses into active
## hostility toward shadow work (the §25 rigidity-as-weapon case).
func trigger_ideological_capture(faith_id: StringName, headline: String) -> void:
	if is_active(State.IDEOLOGICAL_CAPTURE):
		return
	_enter(State.IDEOLOGICAL_CAPTURE, {
		"faith_id": String(faith_id),
		"headline": headline,
	})


## Ironman-style physical death. One-way. The caller is responsible
## for having already checked the conditions doc §12 describes (max
## exposure and hostile locale). Emits a signal the session layer
## turns into a chronicle seal.
func trigger_physical_death(ctx: Dictionary) -> void:
	_enter(State.PHYSICAL_DEATH, ctx)
	physical_death_triggered.emit(ctx)
	# §10.8 Cross-playthrough persistence: commit the run summary
	# before the session tears down. The next new game will pull
	# legacy entities, families, and rumours out of this profile.
	if WorldProfile != null:
		WorldProfile.commit_run(_build_run_summary(&"physical_death", ctx))


func _build_run_summary(cause: StringName, _ctx: Dictionary) -> Dictionary:
	# Produces a compact snapshot of the run: who we were, where the
	# machine reached, and which shapes outlived us. Called from the
	# death path and also from Chronicle.save_to_markdown when that
	# lands on a run end.
	var era_id: StringName = &""
	if Eras != null and Eras.has_method("current_id"):
		era_id = Eras.current_id()
	var start_year: int = 0
	if Chronicle != null and "_started_year" in Chronicle:
		start_year = int(Chronicle.get("_started_year"))
	var end_year: int = -GameClock.year if GameClock != null else 0
	var summary: Dictionary = {
		"run_id":           StringName("run_%d" % Time.get_unix_time_from_system()),
		"start_year":       start_year,
		"end_year":         end_year,
		"cause_of_end":     cause,
		"era_at_end":       String(era_id),
		"major_patterns":   _snapshot_patterns(),
		"revealed_fingerprints": _snapshot_revealed_fingerprints(),
		"machine_footprint": _snapshot_machine_footprint(),
		"legacy_entities":  _snapshot_legacy_entities(),
		"legacy_families":  _snapshot_legacy_families(),
		"rumours":          _snapshot_rumours(),
	}
	return summary


func _snapshot_patterns() -> Array:
	var out: Array = []
	if Memoirs == null:
		return out
	if "patterns" in Memoirs:
		var arr: Variant = Memoirs.get("patterns")
		if arr is Array:
			for p in (arr as Array):
				if p is Dictionary:
					var label: String = String((p as Dictionary).get("label", ""))
					if label != "":
						out.append(label)
	return out


func _snapshot_revealed_fingerprints() -> Array:
	var out: Array = []
	if Fingerprints == null:
		return out
	if Fingerprints.has_method("snapshot"):
		var snap: Dictionary = Fingerprints.snapshot()
		var levels: Variant = snap.get("op_levels", {})
		if levels is Dictionary:
			for k in (levels as Dictionary).keys():
				if int((levels as Dictionary)[k]) >= 1:
					out.append(String(k))
	return out


func _snapshot_machine_footprint() -> Dictionary:
	var kingdoms: Array = []
	var entities: Array = []
	if Org != null and Org.has_method("kingdoms_with_coverage"):
		kingdoms = Org.kingdoms_with_coverage()
	elif Org != null and "coverage" in Org:
		var cov: Variant = Org.get("coverage")
		if cov is Dictionary:
			kingdoms = (cov as Dictionary).keys()
	if Entities != null and "entities" in Entities:
		var v: Variant = Entities.get("entities")
		if v is Dictionary:
			entities = (v as Dictionary).keys().map(func(k): return String(k))
	return {
		"kingdoms_touched": kingdoms,
		"entities_founded": entities,
	}


func _snapshot_legacy_entities() -> Array:
	var out: Array = []
	if Entities == null:
		return out
	if not ("entities" in Entities):
		return out
	var es: Variant = Entities.get("entities")
	if not (es is Dictionary):
		return out
	var era_id: StringName = &""
	if Eras != null and Eras.has_method("current_id"):
		era_id = Eras.current_id()
	for id in (es as Dictionary).keys():
		var e: OwnedEntity = (es as Dictionary)[id]
		if e == null:
			continue
		var corruption: int = 0
		if "corruption" in e:
			corruption = int(e.corruption)
		var discretion: int = 0
		if "discretion" in e:
			discretion = int(e.get("discretion"))
		out.append({
			"id":          String(e.id),
			"kind":        int(e.kind),
			"kingdom_id":  String(e.home_kingdom),
			"era_founded": String(era_id),
			"founder_run_id": "",
			"discretion":  discretion,
			"corruption":  corruption,
		})
	return out


func _snapshot_legacy_families() -> Array:
	var out: Array = []
	if Dynasties == null:
		return out
	if not ("families" in Dynasties):
		return out
	var fams: Variant = Dynasties.get("families")
	if not (fams is Dictionary):
		return out
	for id in (fams as Dictionary).keys():
		var fam: Family = (fams as Dictionary)[id]
		if fam == null:
			continue
		var tb: Dictionary = {}
		if "trait_bias" in fam:
			var tv: Variant = fam.get("trait_bias")
			if tv is Dictionary:
				tb = (tv as Dictionary).duplicate(true)
		var under: bool = false
		if "underdog_focus" in fam:
			under = bool(fam.underdog_focus)
		var home: String = ""
		if "home_kingdom" in fam:
			home = String(fam.home_kingdom)
		var culture: String = ""
		if "family_name" in fam:
			culture = String(fam.family_name)
		out.append({
			"id":             String(fam.id),
			"culture":        culture,
			"trait_bias":     tb,
			"underdog_focus": under,
			"home_kingdom":   home,
		})
	return out


func _snapshot_rumours() -> Array:
	var out: Array = []
	if PublicNews == null:
		return out
	var events: Array = PublicNews.events.duplicate() if "events" in PublicNews else []
	# Keep only the most striking / legendary headlines.
	events.reverse()
	var pick: int = mini(6, events.size())
	for i in range(pick):
		var e: Dictionary = events[i]
		var tier: int = int(e.get("tier", 3))
		out.append({
			"text":   String(e.get("headline", "")),
			"anchor": String(e.get("kind", "misc")),
			"tier":   tier,
		})
	return out


# --- Signal handlers ---------------------------------------------------------

func _on_member_burned(_m, _reason: StringName) -> void:
	var today: int = GameClock.absolute_day()
	_burn_log.append(today)
	_prune_burn_log(today)
	if _burn_log.size() >= BURN_COLLAPSE_THRESHOLD and not is_active(State.NETWORK_COLLAPSE):
		_enter(State.NETWORK_COLLAPSE, {
			"burns_in_window": _burn_log.size(),
			"window_days":     BURN_WINDOW_DAYS,
		})


func _on_exposure_level_changed(_lvl: int) -> void:
	if Exposure.value >= EXPOSED_FLOOR and not is_active(State.EXPOSED_STATE):
		_enter(State.EXPOSED_STATE, {
			"exposure": Exposure.value,
		})


func _on_month_passed(_y: int, _m: int) -> void:
	var today: int = GameClock.absolute_day()
	_prune_burn_log(today)

	# Network collapse recovery: a full year with no new burns and
	# no host loss pressure.
	if is_active(State.NETWORK_COLLAPSE) and _burn_log.is_empty():
		if Actors.hosts().size() > 0:
			_recover(State.NETWORK_COLLAPSE)

	# Exposed-state recovery: zero active hosts AND exposure has
	# drifted back to KNOWN or below. The player has burned their
	# trail and lived in the cold long enough for the meter to cool.
	if is_active(State.EXPOSED_STATE):
		if Actors.hosts().size() == 0 and Exposure.value < 60.0:
			_recover(State.EXPOSED_STATE)


# --- Internal ----------------------------------------------------------------

func _prune_burn_log(today: int) -> void:
	var cutoff: int = today - BURN_WINDOW_DAYS
	while not _burn_log.is_empty() and int(_burn_log[0]) < cutoff:
		_burn_log.pop_front()


func _enter(s: int, ctx: Dictionary) -> void:
	if _active.has(s):
		return
	_active[s] = ctx
	state_entered.emit(s, ctx)
	_announce_state(s, ctx)


func _recover(s: int) -> void:
	if not _active.has(s):
		return
	_active.erase(s)
	state_recovered.emit(s)
	_announce_recovery(s)


func _announce_state(s: int, _ctx: Dictionary) -> void:
	var date: GameDate = GameDate.today()
	var title: String = state_name(s)
	var body: String = state_blurb(s)
	var letter_id: StringName = StringName("failure_%d_%d" % [s, Time.get_ticks_msec()])
	var letter: Letter = Letter.create(
		letter_id,
		"The table, turning",
		date,
		"A degraded state: %s" % title,
		body,
		&"system",
		&"high"
	)
	EventBus.letter_delivered.emit(letter)


func _announce_recovery(s: int) -> void:
	var date: GameDate = GameDate.today()
	var title: String = state_name(s)
	var body: String = (
		"The worst has passed. %s is no longer the shape of your playthrough. Do not assume you are clean — only that you are no longer on fire."
	) % title
	var letter_id: StringName = StringName("failure_recover_%d_%d" % [s, Time.get_ticks_msec()])
	var letter: Letter = Letter.create(
		letter_id,
		"The table, turning",
		date,
		"A degraded state eases: %s" % title,
		body,
		&"system"
	)
	EventBus.letter_delivered.emit(letter)


# --- Save / load -------------------------------------------------------------

func snapshot() -> Dictionary:
	var actives: Dictionary = {}
	for k in _active.keys():
		actives[str(int(k))] = _active[k]
	return {
		"active":   actives,
		"burn_log": _burn_log.duplicate(),
	}


func restore(d: Dictionary) -> void:
	_active.clear()
	var src_active: Dictionary = d.get("active", {})
	for k in src_active.keys():
		_active[int(k)] = src_active[k]
	_burn_log = []
	for v in d.get("burn_log", []):
		_burn_log.append(int(v))
