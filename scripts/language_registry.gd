extends Node
## Autoloaded as `Languages`. Minimal language layer for §23.
##
## What lives here:
##   - a small dictionary of language ids to display names
##   - per-kingdom native + secondary language mappings
##   - a helper that seeds a newborn actor's `languages` dict from
##     their kingdom context, biased by role (scholars and priests
##     pick up scholarly languages; merchants and port dwellers pick
##     up trade lingua francas; soldiers pick up one neighbour).
##
## Fluency levels use the ints declared on Actor:
##   0 none, 1 basic, 2 functional, 3 fluent.

const DATA_PATH: String = "res://data/languages_500bce.json"
const EVOLUTION_PATH: String = "res://data/language_evolution.json"

# id -> display name
var languages: Dictionary = {}

# kingdom_id -> native language id (StringName)
var _native: Dictionary = {}

# kingdom_id -> Array[StringName] of common non-native languages
var _secondary: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	DevLogger.write("Languages: ready")
	_rng.randomize()
	_load()
	_load_evolution()
	# Actors are loaded ahead of Languages in the autoload order.
	# Seed any pre-existing actor that doesn't yet carry a language
	# dict so the first game-session population speaks the right
	# tongues. Newer spawns come through ActorRegistry.spawn_actor
	# directly.
	call_deferred("_backfill_existing_actors")
	GameClock.month_passed.connect(_on_month_passed)
	# Eras autoload exists by the time _ready runs thanks to the
	# autoload order in project.godot.
	if Eras != null:
		Eras.era_changed.connect(_on_era_changed)


func _backfill_existing_actors() -> void:
	if Actors == null:
		return
	for a in Actors.all_actors():
		if a.languages.is_empty():
			seed_for(a)


func _load() -> void:
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_warning("Languages: could not open %s" % DATA_PATH)
		return
	var blob: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(blob) != TYPE_DICTIONARY:
		return
	for entry in blob.get("languages", []):
		var lid: StringName = StringName(String(entry.get("id", "")))
		languages[lid] = String(entry.get("name", String(lid)))
	for k in blob.get("kingdom_native", {}).keys():
		_native[String(k)] = StringName(String(blob["kingdom_native"][k]))
	for k in blob.get("kingdom_secondary", {}).keys():
		var arr: Array = []
		for v in blob["kingdom_secondary"][k]:
			arr.append(StringName(String(v)))
		_secondary[String(k)] = arr


# --- Evolution (§23.5) -------------------------------------------------------
#
# An era transition may:
#   * introduce new language ids with display names.
#   * split a parent vernacular into a daughter in a set of kingdoms
#     (the kingdom's native shifts to the daughter; institutional
#     roles in the doc — priests, philosophers — retain fluency in
#     the parent for church / academic use).
#   * retire a language from the "native" roster entirely — speakers
#     keep their fluency, but the language no longer seeds newborn
#     actors or defines a kingdom's cultural envelope.

# era_id -> evolution dict loaded from language_evolution.json
var _evolution: Dictionary = {}

# Languages the player has "seen go live" already — used to make
# save/load idempotent. Without this a save from mid-1201 that's
# restored in the same session would re-apply Medieval Consolidation.
var _applied_eras: Dictionary = {}


func _load_evolution() -> void:
	if not FileAccess.file_exists(EVOLUTION_PATH):
		return
	var f: FileAccess = FileAccess.open(EVOLUTION_PATH, FileAccess.READ)
	if f == null:
		return
	var blob: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(blob) != TYPE_DICTIONARY:
		return
	_evolution = blob.get("transitions", {})


func _on_era_changed(_prev: StringName, new_id: StringName) -> void:
	_apply_era_evolution(new_id)


func _apply_era_evolution(era_id: StringName) -> void:
	if era_id == &"" or _evolution.is_empty():
		return
	if _applied_eras.get(String(era_id), false):
		return
	var entry: Dictionary = _evolution.get(String(era_id), {})
	if entry.is_empty():
		_applied_eras[String(era_id)] = true
		return

	# 1) Introduce new language ids first so splits can reference them.
	for new_lang in entry.get("introduce", []):
		var lid: StringName = StringName(String(new_lang.get("id", "")))
		if lid == &"":
			continue
		if not languages.has(lid):
			languages[lid] = String(new_lang.get("name", String(lid)))

	# 2) Apply vernacular splits.
	var summaries: Array[String] = []
	for raw_split in entry.get("vernacular_splits", []):
		var summary: String = _apply_split(raw_split)
		if summary != "":
			summaries.append(summary)

	# 3) Retire languages from native roster. Speakers keep their
	#    fluency; this only removes them as a kingdom's native tongue.
	for retired in entry.get("retired_as_native", []):
		_retire_native_language(StringName(String(retired)))

	_applied_eras[String(era_id)] = true
	_announce_evolution(era_id, summaries)


func _apply_split(split: Dictionary) -> String:
	var parent: StringName = StringName(String(split.get("parent", "")))
	var daughter: StringName = StringName(String(split.get("daughter", "")))
	if parent == &"" or daughter == &"":
		return ""
	var kingdoms: Array = split.get("kingdoms", [])
	var institutional_roles: Array = split.get("institutional_roles", [])

	# Update the kingdom native map — this is what newborn actors
	# inherit from this era on.
	for k in kingdoms:
		var kid: String = String(k)
		if _native.get(kid, &"") == parent:
			_native[kid] = daughter

	# Rebuild secondary arrays so newly-seeded actors pick up the
	# daughter as a trade language in neighbouring kingdoms.
	for kid in _secondary.keys():
		var arr: Array = _secondary[kid]
		var mutated: bool = false
		for i in range(arr.size()):
			if StringName(String(arr[i])) == parent and _native.get(String(kid), &"") != parent:
				# Only swap to daughter if this kingdom isn't still
				# an institutional holdout for the parent.
				arr[i] = daughter
				mutated = true
		if mutated:
			_secondary[kid] = arr

	# Migrate fluency on existing actors in the affected kingdoms.
	# Institutional roles retain their parent fluency; others have
	# their parent-language slot converted to the daughter.
	var _migrated: int = 0
	if Actors != null:
		for a in Actors.all_actors():
			if a == null or not a.is_alive():
				continue
			if not (String(a.kingdom_id) in kingdoms):
				continue
			var parent_level: int = a.language_level(parent)
			if parent_level == 0:
				continue
			var keeps_parent: bool = _role_is_institutional(a, institutional_roles)
			if keeps_parent:
				# Institutional speaker: daughter comes in at one step
				# below parent, parent stays put.
				_bump(a, daughter, max(Actor.LANG_BASIC, parent_level - 1))
			else:
				# Vernacular speaker: the spoken tongue drifts. They
				# keep functional reading of the old at best, and the
				# daughter at the level they had in the parent.
				a.languages[daughter] = parent_level
				a.languages[parent] = min(int(a.languages.get(parent, 0)), Actor.LANG_BASIC)
			_migrated += 1

	var region_list: String = ""
	for k in kingdoms:
		region_list += (", " if region_list != "" else "") + _kingdom_name_of(String(k))
	if region_list == "":
		region_list = "the wider world"
	return "%s gives way to %s in %s" % [display_name(parent), display_name(daughter), region_list]


func _retire_native_language(lid: StringName) -> void:
	if lid == &"":
		return
	for kid in _native.keys():
		if _native[kid] == lid:
			# Fall back to whatever secondary the kingdom has first, or
			# latin as a generic scholarly default, so the kingdom
			# isn't left nativeless.
			var secs: Array = _secondary.get(String(kid), [])
			if not secs.is_empty():
				_native[kid] = StringName(String(secs[0]))
			else:
				_native[kid] = &"latin"


func _role_is_institutional(a: Actor, role_names: Array) -> bool:
	if role_names.is_empty():
		return false
	var rn: String = a.role_name() if a != null else ""
	for r in role_names:
		if String(r) == rn:
			return true
	return false


func _announce_evolution(era_id: StringName, summaries: Array[String]) -> void:
	if summaries.is_empty():
		return
	var date: GameDate = GameDate.today()
	var era_label: String = ""
	if Eras != null:
		var e: Era = Eras.get_era(era_id)
		if e != null:
			era_label = e.display_name
	if era_label == "":
		era_label = String(era_id)
	var body: String = (
		"Languages do what languages do: they move. What was a handful of regional tongues a generation ago is, quietly, already something else.\n\n"
	)
	for s in summaries:
		body += "• " + s + ".\n"
	body += "\nOperatives whose working languages have drifted will lose edge in street-level work until they retrain. Scholarly and liturgical fluency remains intact."
	var letter: Letter = Letter.create(
		StringName("lang_evolution_%s" % String(era_id)),
		OrgRoles.sender_line(OrgRoles.SECRETARY),
		date,
		"The working tongues have shifted — %s" % era_label,
		body,
		&"news"
	)
	EventBus.letter_delivered.emit(letter)


# --- Public API --------------------------------------------------------------

func display_name(id: StringName) -> String:
	return String(languages.get(id, String(id)))


func native_of(kingdom_id: String) -> StringName:
	return _native.get(kingdom_id, &"")


func secondary_of(kingdom_id: String) -> Array:
	return _secondary.get(kingdom_id, [])


## Populate an actor's language dict based on their kingdom and role.
## Call after the actor's kingdom_id and role are set. Returns the
## same actor for chaining convenience.
func seed_for(a: Actor) -> Actor:
	if a == null:
		return a
	var kid: String = a.kingdom_id
	if kid == "":
		return a
	var native: StringName = native_of(kid)
	if native != &"":
		a.languages[native] = Actor.LANG_FLUENT
	var secondaries: Array = secondary_of(kid)

	# Everyone picks up basic competence in half of the kingdom's
	# secondary languages (random half, so actors are varied).
	for lid in secondaries:
		if _rng.randf() < 0.5:
			_bump(a, StringName(lid), Actor.LANG_BASIC)

	# Role flavour.
	match a.role:
		Actor.Role.PHILOSOPHER, Actor.Role.PRIEST:
			# Scholars and priests often read a scholarly language.
			# Koine Greek covers the Mediterranean; Aramaic / Old
			# Persian cover the east.
			var scholarly: StringName = _scholarly_for(kid)
			if scholarly != &"" and scholarly != native:
				_bump(a, scholarly, Actor.LANG_FUNCTIONAL)
		Actor.Role.MERCHANT:
			# Merchants reach functional in the nearest trade lingua
			# franca. Prefer a kingdom secondary already listed.
			if not secondaries.is_empty():
				var pick: StringName = StringName(secondaries[_rng.randi_range(0, secondaries.size() - 1)])
				_bump(a, pick, Actor.LANG_FUNCTIONAL)
			else:
				_bump(a, &"koine_greek", Actor.LANG_BASIC)
		Actor.Role.ADVISOR, Actor.Role.RULER, Actor.Role.HEIR, Actor.Role.GENERAL:
			# Courtiers, generals, and royal children pick up one
			# secondary to functional — usually a neighbour.
			if not secondaries.is_empty():
				var pick2: StringName = StringName(secondaries[_rng.randi_range(0, secondaries.size() - 1)])
				_bump(a, pick2, Actor.LANG_FUNCTIONAL)
		_:
			pass

	# Port-and-road cosmopolitan bonus: if the home province has a
	# harbour or roads, roll a chance to lift the strongest secondary
	# from basic to functional. Overseas trade creates bridge people.
	var p: Province = WorldData.get_province(a.province_id) if a.province_id != "" else null
	if p != null and (p.has_building(&"harbour") or p.has_building(&"road_network")):
		if not secondaries.is_empty() and _rng.randf() < 0.25:
			var pick3: StringName = StringName(secondaries[_rng.randi_range(0, secondaries.size() - 1)])
			_bump(a, pick3, Actor.LANG_FUNCTIONAL)
	return a


# Return the scholarly lingua franca a priest or philosopher from the
# given kingdom would most likely have trained in.
func _scholarly_for(kingdom_id: String) -> StringName:
	var native: StringName = native_of(kingdom_id)
	# Eastern empires use Aramaic or Old Persian; everyone else uses
	# Koine Greek.
	match String(native):
		"persian":  return &"aramaic"
		"egyptian": return &"aramaic"
		"aramaic":  return &"koine_greek"
		_:           return &"koine_greek"


func _bump(a: Actor, lid: StringName, floor_level: int) -> void:
	if lid == &"":
		return
	var current: int = int(a.languages.get(lid, 0))
	if current < floor_level:
		a.languages[lid] = floor_level


## Effectiveness multiplier for an actor attempting to operate on a
## target whose native language is X. 1.0 when fluent; lower when
## functional/basic; bottom for none.
func effectiveness(operator: Actor, target: Actor) -> float:
	if operator == null or target == null:
		return 1.0
	var target_native: StringName = native_of(target.kingdom_id)
	if target_native == &"":
		return 1.0
	var lvl: int = operator.language_level(target_native)
	match lvl:
		Actor.LANG_FLUENT:     return 1.0
		Actor.LANG_FUNCTIONAL: return 0.9
		Actor.LANG_BASIC:      return 0.7
		_:                      return 0.5


# --- Acquisition paths (§23.x) -----------------------------------------------
#
# Immersion. An operative posted in a region that does not speak their
# native tongue builds language over time. One progress point per
# month on post; thresholds at 6 / 24 / 60 months lift them through
# basic / functional / fluent in the region's native language.
# Training is a cheaper alternative — a paid action via the roster
# that skips a threshold at silver cost.

const IMMERSION_MONTHS_TO_BASIC:      int = 6
const IMMERSION_MONTHS_TO_FUNCTIONAL: int = 24
const IMMERSION_MONTHS_TO_FLUENT:     int = 60

# org_member_id -> { "lang": StringName, "months": int }
var _immersion_progress: Dictionary = {}


func _on_month_passed(_y: int, _m: int) -> void:
	_tick_immersion()


func _tick_immersion() -> void:
	if Org == null:
		return
	var seen: Dictionary = {}
	for m in Org.members.values():
		seen[m.id] = true
		if m.burned:
			continue
		_tick_member_immersion(m)
	# Drop immersion entries for members that no longer exist
	# (§6.5 long-run compression: don't keep booking progress for
	# ghosts of agents long gone).
	if _immersion_progress.size() > seen.size():
		var stale: Array = []
		for k in _immersion_progress.keys():
			if not seen.has(k):
				stale.append(k)
		for k in stale:
			_immersion_progress.erase(k)


func _tick_member_immersion(m: OrgMember) -> void:
	if m.source_actor_id == &"":
		return
	var src: Actor = Actors.get_actor(m.source_actor_id)
	if src == null or not src.is_alive():
		return
	if m.region_id == "":
		return
	# Posted in their own home region — no immersion.
	if m.region_id == src.kingdom_id:
		return
	var lang: StringName = native_of(m.region_id)
	if lang == &"":
		return
	var have: int = src.language_level(lang)
	if have >= Actor.LANG_FLUENT:
		return

	var entry: Dictionary = _immersion_progress.get(m.id, {})
	# If the member has been reposted elsewhere, reset progress.
	if entry.is_empty() or StringName(String(entry.get("lang", ""))) != lang:
		entry = {"lang": String(lang), "months": 0}
	entry["months"] = int(entry.get("months", 0)) + 1
	_immersion_progress[m.id] = entry

	var months: int = int(entry["months"])
	var new_level: int = have
	if have < Actor.LANG_BASIC and months >= IMMERSION_MONTHS_TO_BASIC:
		new_level = Actor.LANG_BASIC
	if have < Actor.LANG_FUNCTIONAL and months >= IMMERSION_MONTHS_TO_FUNCTIONAL:
		new_level = Actor.LANG_FUNCTIONAL
	if have < Actor.LANG_FLUENT and months >= IMMERSION_MONTHS_TO_FLUENT:
		new_level = Actor.LANG_FLUENT
	if new_level > have:
		src.languages[lang] = new_level
		_announce_acquisition(m, src, lang, new_level)


func _announce_acquisition(m: OrgMember, src: Actor, lang: StringName, level: int) -> void:
	var phrase: String = "makes themselves understood in"
	match level:
		Actor.LANG_FUNCTIONAL: phrase = "conducts business in"
		Actor.LANG_FLUENT:     phrase = "now thinks in"
	var date: GameDate = GameDate.today()
	var letter_id: StringName = StringName("lang_acquire_%s_%d" % [String(m.id), Time.get_ticks_msec()])
	var body: String = (
		"After enough winters in %s to lose count, %s %s %s. A small advantage that will show up in every conversation from here forward."
	) % [
		_kingdom_name_of(m.region_id),
		src.display_name(),
		phrase,
		display_name(lang),
	]
	var letter: Letter = Letter.create(
		letter_id,
		OrgRoles.sender_line(OrgRoles.HANDLER, (src.kingdom_id if src != null else "")),
		date,
		"%s has picked up %s" % [src.display_name(), display_name(lang)],
		body,
		&"operative"
	)
	EventBus.letter_delivered.emit(letter)


## Explicit training action — the roster UI calls this when the
## player commits silver to sending an operative to a tutor. Lifts
## their level in `lang` by one step and returns true on success.
## Caller handles the silver cost; this only does the knowledge
## change and the inbox letter.
func train_actor(actor_id: StringName, lang: StringName) -> bool:
	var a: Actor = Actors.get_actor(actor_id)
	if a == null or not a.is_alive() or lang == &"":
		return false
	var have: int = a.language_level(lang)
	if have >= Actor.LANG_FLUENT:
		return false
	a.languages[lang] = have + 1
	var date: GameDate = GameDate.today()
	var letter_id: StringName = StringName("lang_train_%s_%d" % [String(actor_id), Time.get_ticks_msec()])
	var body: String = (
		"The tutor reports %s now reads %s at %s. Whether any of it stays in their head depends on what they do with it."
	) % [
		a.display_name(),
		display_name(lang),
		_level_phrase(have + 1),
	]
	var letter: Letter = Letter.create(
		letter_id,
		OrgRoles.sender_line(OrgRoles.TUTOR, (a.kingdom_id if a != null else "")),
		date,
		"Tuition paid for %s" % a.display_name(),
		body,
		&"operative"
	)
	EventBus.letter_delivered.emit(letter)
	return true


func _level_phrase(level: int) -> String:
	match level:
		Actor.LANG_BASIC:      return "a basic level"
		Actor.LANG_FUNCTIONAL: return "a functional level"
		Actor.LANG_FLUENT:     return "a fluent level"
		_:                     return "no appreciable level"


func _kingdom_name_of(kid: String) -> String:
	var k: Kingdom = WorldData.get_kingdom(kid)
	return k.kingdom_name if k != null else kid


# --- Save / load -------------------------------------------------------------

func snapshot() -> Dictionary:
	return {
		"immersion_progress": _immersion_progress.duplicate(true),
		"applied_eras":       _applied_eras.duplicate(true),
	}


func restore(d: Dictionary) -> void:
	var raw: Dictionary = d.get("immersion_progress", {})
	_immersion_progress.clear()
	for k in raw.keys():
		var entry: Dictionary = raw[k]
		_immersion_progress[StringName(String(k))] = {
			"lang":   String(entry.get("lang", "")),
			"months": int(entry.get("months", 0)),
		}
	# Catch Languages up to whatever era the save restored the
	# GameClock into — without this, loading a save from 900 CE would
	# still have native_of("rome") == "latin".
	_applied_eras = d.get("applied_eras", {}).duplicate(true)
	_replay_evolution_up_to(GameClock.year)


func _replay_evolution_up_to(year: int) -> void:
	if Eras == null or _evolution.is_empty():
		return
	for e in Eras.eras:
		if e.year_start <= year and not _applied_eras.get(String(e.id), false):
			# Silent replay — we don't re-send inbox letters for eras
			# the player lived through before saving.
			_apply_era_evolution_silent(e.id)


func _apply_era_evolution_silent(era_id: StringName) -> void:
	# Same as _apply_era_evolution but skips the inbox letter.
	var entry: Dictionary = _evolution.get(String(era_id), {})
	if entry.is_empty():
		_applied_eras[String(era_id)] = true
		return
	for new_lang in entry.get("introduce", []):
		var lid: StringName = StringName(String(new_lang.get("id", "")))
		if lid != &"" and not languages.has(lid):
			languages[lid] = String(new_lang.get("name", String(lid)))
	for raw_split in entry.get("vernacular_splits", []):
		_apply_split(raw_split)
	for retired in entry.get("retired_as_native", []):
		_retire_native_language(StringName(String(retired)))
	_applied_eras[String(era_id)] = true


## Quick qualitative tag used by the dossier / compose view to warn
## the player about language gaps.
func gap_phrase(operator: Actor, target: Actor) -> String:
	if operator == null or target == null:
		return ""
	var target_native: StringName = native_of(target.kingdom_id)
	if target_native == &"":
		return ""
	if operator.language_level(target_native) >= Actor.LANG_FUNCTIONAL:
		return ""
	if operator.language_level(target_native) == Actor.LANG_BASIC:
		return "Your hand's %s is rudimentary. Nuance will be lost." % display_name(target_native)
	return "Your hand does not speak %s. An interpreter will carry the weight — and the risk." % display_name(target_native)
