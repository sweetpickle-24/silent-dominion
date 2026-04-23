extends Node
## Autoloaded as `Whispers`. Keeps the player's covert seeds alive for a
## while after the initial dispatch.
##
## When a rumour, planted idea, or host agitation succeeds the ActionRunner
## emits the one-off public trace, then also registers a whisper here.
## Whispers carry a qualitative strength — loud / carried / fading / dead —
## that decays one band per month. While a whisper is still alive there is
## a small monthly chance to fire a follow-up dispatch so the covert seed
## keeps producing visible texture for a few months, not just a single
## headline.
##
## The scalar strength is never shown to the player. Only the band is
## read out in the codebook and in the follow-up dispatch copy.
##
## A whisper moves through:
##   LOUD     — newly seeded, discussed openly
##   CARRIED  — still in circulation but quieter
##   FADING   — half-remembered, mostly absent from the market
##   DEAD     — dropped from the registry; no further dispatches
##
## Each month the strength ticks down by STRENGTH_DECAY_PER_MONTH. A
## whisper stays roughly ~5–7 months before it dies; live ones have a
## P_FOLLOWUP_PER_MONTH chance to emit a small follow-up news dispatch
## and, if the kind is `agitate`, a modest unrest nudge in the target's
## home province (nothing explosive — §30 says player action should
## nudge, not smash).

signal whisper_registered(target_id: StringName, kind: StringName)
signal whisper_faded(target_id: StringName, kind: StringName)

const STRENGTH_INITIAL: int        = 100
const STRENGTH_DECAY_PER_MONTH: int = 18
const BAND_LOUD: int               = 70     # >= LOUD
const BAND_CARRIED: int            = 40     # >= CARRIED
const BAND_FADING: int             = 15     # >= FADING
# Below BAND_FADING the whisper is effectively dead and removed.

const P_FOLLOWUP_PER_MONTH: float = 0.28
const AGITATE_UNREST_TAIL: int    = 2       # small monthly unrest nudge
const LOUD_EXPOSURE_TAIL: float   = 0.8     # per LOUD whisper, per tick


## Each entry keys on a stable composite id so two different kinds
## targeting the same actor coexist. Value is a Dictionary:
##   {
##     kind:       StringName,         # &"rumour", &"idea", &"agitate"
##     target_id:  StringName,         # Actor id OR "host_<id>" for agitate
##     actor_id:   StringName,         # Actor id for display
##     kingdom_id: String,             # cached for follow-up copy
##     strength:   int,                # 0..100 scalar (never shown)
##     born_year:  int,                # GameDate year (positive for BCE)
##     born_month: int,
##   }
var _active: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	DevLogger.write("Whispers: ready")
	_rng.randomize()
	GameClock.month_passed.connect(_on_month_passed)
	EventBus.actor_died.connect(_on_actor_died)


## When an actor the player had whispers attached to dies, every line
## tied to their name goes quiet immediately — the market's memory of
## them will wander off to fresher scandals.
func _on_actor_died(actor_id: StringName, _was_host: bool, cause: StringName) -> void:
	var dropped: Array[String] = []
	for key in _active.keys():
		var w: Dictionary = _active[key]
		if StringName(w.get("actor_id", &"")) == actor_id:
			dropped.append(key)
	for key in dropped:
		var w: Dictionary = _active[key]
		whisper_faded.emit(
			StringName(w.get("target_id", &"")),
			StringName(w.get("kind", &"")),
		)
		_active.erase(key)
	# An assassinated host leaves a louder wake than an age-death;
	# investigators pick up threads while the trail is fresh.
	if cause == &"assassination" and not dropped.is_empty():
		Exposure.bump(3.0, "host_killed")


# --- Public API --------------------------------------------------------------

## Register a freshly-seeded whisper. Called by the ActionRunner the
## first time the action fires, right after the one-off public trace is
## emitted. Safe to call with an unknown actor id — we simply no-op.
func register(kind: StringName, actor_id: StringName) -> void:
	var a: Actor = Actors.get_actor(actor_id)
	if a == null:
		return
	var key: String = "%s:%s" % [String(kind), String(actor_id)]
	# Re-seeding an existing whisper refreshes it to full strength and
	# resets its "born" timestamp — the player pushed on it again.
	_active[key] = {
		"kind":       kind,
		"target_id":  actor_id,
		"actor_id":   actor_id,
		"kingdom_id": a.kingdom_id,
		"strength":   STRENGTH_INITIAL,
		"born_year":  GameClock.year,
		"born_month": GameClock.month,
	}
	whisper_registered.emit(actor_id, kind)


## Number of live whispers currently tracked. Used by the codebook
## preview and potentially by a future "your lines in the world" panel.
func live_count() -> int:
	return _active.size()


## Debug-only dump used by F1.
func debug_dump() -> void:
	print("[Whispers] %d live" % _active.size())
	for key in _active.keys():
		var w: Dictionary = _active[key]
		print("  %s  str=%d  band=%s" % [key, int(w.get("strength", 0)), _band_name(int(w.get("strength", 0)))])


# --- Monthly tick ------------------------------------------------------------

func _on_month_passed(_y: int, _m: int) -> void:
	var expired: Array[String] = []
	var loud_count: int = 0
	for key in _active.keys():
		var w: Dictionary = _active[key]
		var old_band: int = _band_for(int(w.get("strength", 0)))
		var new_strength: int = int(w.get("strength", 0)) - STRENGTH_DECAY_PER_MONTH
		w["strength"] = new_strength
		_active[key] = w
		var new_band: int = _band_for(new_strength)
		# Emit follow-up dispatch & side effects only while alive.
		if new_band >= BAND_FADING:
			if new_band >= BAND_LOUD:
				loud_count += 1
			if _rng.randf() < P_FOLLOWUP_PER_MONTH:
				_emit_followup(w, new_band, old_band)
			if StringName(w.get("kind", &"")) == &"agitate" and new_band >= BAND_CARRIED:
				var a: Actor = Actors.get_actor(StringName(w.get("actor_id", &"")))
				if a != null:
					var home: String = _pick_home_province(a.kingdom_id)
					if home != "":
						Unrest.bump(home, AGITATE_UNREST_TAIL)
		else:
			expired.append(key)

	# Loud whispers pull attention. One loud line is tolerable; several
	# in the same season cumulatively creep up the exposure meter.
	if loud_count > 0:
		Exposure.bump(float(loud_count) * LOUD_EXPOSURE_TAIL, "loud_whispers")
	for key in expired:
		var w: Dictionary = _active[key]
		whisper_faded.emit(
			StringName(w.get("target_id", &"")),
			StringName(w.get("kind", &"")),
		)
		_active.erase(key)


func _emit_followup(w: Dictionary, band: int, old_band: int) -> void:
	var actor: Actor = Actors.get_actor(StringName(w.get("actor_id", &"")))
	if actor == null:
		return
	var k: Kingdom = WorldData.get_kingdom(w.get("kingdom_id", ""))
	var kname: String = k.kingdom_name if k != null else String(w.get("kingdom_id", ""))
	var kind: StringName = StringName(w.get("kind", &""))

	# Don't fire a "now fading" dispatch if we were already fading last
	# month — we'd be telling the same tale twice.
	var newly_faded: bool = (band == BAND_FADING and old_band > BAND_FADING)

	var headline: String = ""
	var body: String = ""
	match kind:
		&"rumour":
			if band >= BAND_LOUD:
				headline = "The rumour about %s thickens" % actor.given_name
				body = "The talk about [url=actor:%s][b]%s[/b][/url] has not cooled. A second market in %s picked it up last week, with additions." % [
					String(actor.id), actor.display_name(), kname,
				]
			elif band >= BAND_CARRIED:
				headline = "%s, still a name in that mouth" % actor.given_name
				body = "The whisper about [url=actor:%s][b]%s[/b][/url] has quieted, but has not gone. It is still carried by the same mouths — and by a few new ones." % [
					String(actor.id), actor.display_name(),
				]
			elif newly_faded:
				headline = "A story about %s fades" % actor.given_name
				body = "What the markets were saying about [url=actor:%s][b]%s[/b][/url] has largely fallen out of use. A few still speak it; most do not." % [
					String(actor.id), actor.display_name(),
				]
			else:
				return
		&"idea":
			if band >= BAND_LOUD:
				headline = "%s presses the argument further" % actor.given_name
				body = "Those close to [url=actor:%s][b]%s[/b][/url] report them elaborating on the argument a second time, in new company. The thought has taken." % [
					String(actor.id), actor.display_name(),
				]
			elif band >= BAND_CARRIED:
				headline = "%s's new thought has company" % actor.given_name
				body = "Two others in the court of %s now echo what [url=actor:%s][b]%s[/b][/url] were first to voice. Whether the line holds is another matter." % [
					kname, String(actor.id), actor.display_name(),
				]
			elif newly_faded:
				headline = "A new argument loses its colour"
				body = "The line [url=actor:%s][b]%s[/b][/url] took up with such heat is mostly dropped now. These things happen." % [
					String(actor.id), actor.display_name(),
				]
			else:
				return
		&"agitate":
			if band >= BAND_LOUD:
				headline = "%s remains on edge" % kname
				body = "Another night of raised voices in %s. The watch is thin; the streets, thick." % kname
			elif band >= BAND_CARRIED:
				headline = "The mood in %s has not cooled" % kname
				body = "The disturbance in %s has settled into something quieter — but not yet into nothing." % kname
			elif newly_faded:
				headline = "%s, quieter at last" % kname
				body = "The markets of %s have largely returned to their ordinary grumble. The incident is folded away; the watch, less pale." % kname
			else:
				return
		_:
			return

	EventBus.public_event.emit({
		"kind":       _followup_event_kind(kind),
		"kingdom_id": w.get("kingdom_id", ""),
		"actors":     [String(actor.id)],
		"headline":   headline,
		"body":       body,
	})


static func _followup_event_kind(kind: StringName) -> StringName:
	match kind:
		&"rumour":  return &"rumour"
		&"idea":    return &"idea_planted"
		&"agitate": return &"unrest"
		_:          return &"rumour"


func _pick_home_province(kingdom_id: String) -> String:
	var k: Kingdom = WorldData.get_kingdom(kingdom_id)
	if k == null or k.owned_provinces.is_empty():
		return ""
	# Pick the first owned province with any population. Falls back to
	# the first listed province if none are populated (e.g. sea-only).
	for pid in k.owned_provinces:
		var p: Province = WorldData.get_province(pid)
		if p != null and p.population > 0:
			return pid
	return String(k.owned_provinces[0])


# --- Bands -------------------------------------------------------------------

func _band_for(strength: int) -> int:
	if strength >= BAND_LOUD:    return BAND_LOUD
	if strength >= BAND_CARRIED: return BAND_CARRIED
	if strength >= BAND_FADING:  return BAND_FADING
	return 0


func _band_name(strength: int) -> String:
	match _band_for(strength):
		BAND_LOUD:    return "loud"
		BAND_CARRIED: return "carried"
		BAND_FADING:  return "fading"
		_:            return "dead"


# --- Save/load ---------------------------------------------------------------

func snapshot() -> Array:
	var out: Array = []
	for key in _active.keys():
		var w: Dictionary = _active[key]
		out.append({
			"key":        key,
			"kind":       String(w.get("kind", "")),
			"target_id":  String(w.get("target_id", "")),
			"actor_id":   String(w.get("actor_id", "")),
			"kingdom_id": String(w.get("kingdom_id", "")),
			"strength":   int(w.get("strength", 0)),
			"born_year":  int(w.get("born_year", 0)),
			"born_month": int(w.get("born_month", 0)),
		})
	return out


func restore(arr: Array) -> void:
	_active.clear()
	for d in arr:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var key: String = String(d.get("key", ""))
		if key == "":
			continue
		_active[key] = {
			"kind":       StringName(String(d.get("kind", ""))),
			"target_id":  StringName(String(d.get("target_id", ""))),
			"actor_id":   StringName(String(d.get("actor_id", ""))),
			"kingdom_id": String(d.get("kingdom_id", "")),
			"strength":   int(d.get("strength", 0)),
			"born_year":  int(d.get("born_year", 0)),
			"born_month": int(d.get("born_month", 0)),
		}
