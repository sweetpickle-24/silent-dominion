extends Node
## Autoloaded as `WorldProfile`. Cross-playthrough persistence for
## §10.8. Prior runs commit a summary + machine footprint into
## `user://world_profile.json`; new games pull legacy entities,
## families, rumours, and pre-revealed fingerprints out of it.
##
## Gated by `Prefs.world_persistence_enabled`. When off, behaves as
## if the profile file does not exist — every new game is a clean
## slate.

signal profile_loaded(runs: int)
signal run_committed(run_id: StringName)

const PROFILE_PATH: String = "user://world_profile.json"
const SCHEMA_VERSION: int = 1

var schema: int = SCHEMA_VERSION
var runs: Array = []                 # list of run summaries
var legacy_entities: Array = []      # list of entity dicts
var legacy_families: Array = []      # list of family dicts
var known_rumours: Array = []        # list of rumour dicts


func _ready() -> void:
	_load_from_disk()
	profile_loaded.emit(runs.size())


# --- Public API --------------------------------------------------------------

func enabled() -> bool:
	if Prefs == null:
		return true
	if not ("world_persistence_enabled" in Prefs):
		return true
	return bool(Prefs.world_persistence_enabled)


func commit_run(summary: Dictionary) -> void:
	if not enabled():
		return
	var s: Dictionary = summary.duplicate(true)
	if not s.has("run_id"):
		s["run_id"] = StringName("run_%d" % Time.get_unix_time_from_system())
	runs.append(s)
	# Append any explicit carry-over objects packaged under the summary.
	if s.has("legacy_entities") and s["legacy_entities"] is Array:
		for e in s["legacy_entities"]:
			legacy_entities.append((e as Dictionary).duplicate(true))
	if s.has("legacy_families") and s["legacy_families"] is Array:
		for fam in s["legacy_families"]:
			legacy_families.append((fam as Dictionary).duplicate(true))
	if s.has("rumours") and s["rumours"] is Array:
		for r in s["rumours"]:
			known_rumours.append((r as Dictionary).duplicate(true))
	_prune()
	_save_to_disk()
	run_committed.emit(StringName(String(s.get("run_id", ""))))


## Called from the new-game path (table.gd `_apply_new_game_difficulty`).
## Folds prior-run echoes into the fresh world: entities seeded in
## kingdoms that still exist, families registered, one rumour letter
## delivered, and a handful of fingerprints pre-revealed so the player
## inherits some of the predecessor's hard-won understanding.
##
## Safe to call on an empty profile — becomes a no-op.
func apply_legacy_imports() -> Dictionary:
	var out: Dictionary = {
		"entities_imported": 0,
		"families_imported": 0,
		"rumour_seeded": false,
		"fingerprints_revealed": 0,
	}
	if not enabled():
		return out
	out["entities_imported"] = _import_legacy_entities()
	out["families_imported"] = _import_legacy_families()
	out["fingerprints_revealed"] = _preseed_fingerprints()
	out["rumour_seeded"] = _seed_rumour_letter()
	return out


func _import_legacy_entities() -> int:
	if Entities == null:
		return 0
	var n: int = 0
	for entry_any in legacy_entities:
		if not (entry_any is Dictionary):
			continue
		var entry: Dictionary = entry_any
		var kingdom_id: String = String(entry.get("kingdom_id", ""))
		if kingdom_id == "" or not _kingdom_exists(kingdom_id):
			continue
		var raw: Dictionary = {
			"id":           String(entry.get("id", "")),
			"kind":         _kind_name_from_int(int(entry.get("kind", 0))),
			"display_name": "Shadow of a former hand",
			"home_kingdom": kingdom_id,
			"home_province": "",
			"founded_year": -int(GameClock.year) if GameClock != null else -500,
			"discretion":   clampi(int(entry.get("discretion", 50)) - 10, 0, 100),
			"corruption":   int(entry.get("corruption", 0)),
		}
		if String(raw["id"]) == "" or Entities.entities.has(StringName(String(raw["id"]))):
			continue
		var oe: OwnedEntity = OwnedEntity.from_dict(raw)
		if oe == null or oe.id == &"":
			continue
		Entities.register(oe)
		n += 1
		if n >= 4:
			break
	return n


func _import_legacy_families() -> int:
	if Dynasties == null:
		return 0
	if not ("families" in Dynasties):
		return 0
	var n: int = 0
	for entry_any in legacy_families:
		if not (entry_any is Dictionary):
			continue
		var entry: Dictionary = entry_any
		var id_s: String = String(entry.get("id", ""))
		if id_s == "":
			continue
		var home: String = String(entry.get("home_kingdom", ""))
		if home != "" and not _kingdom_exists(home):
			continue
		var fid: StringName = StringName(id_s)
		var fams: Dictionary = Dynasties.families
		if fams.has(fid):
			continue
		var fam: Family = Family.new()
		fam.id = fid
		if "culture" in fam:
			fam.set("culture", String(entry.get("culture", "")))
		if "home_kingdom" in fam:
			fam.home_kingdom = home
		if "family_name" in fam and String(fam.family_name) == "":
			fam.family_name = String(entry.get("culture", "Legacy line"))
		if "underdog_focus" in fam:
			fam.underdog_focus = bool(entry.get("underdog_focus", false))
		if "trait_bias" in fam and entry.get("trait_bias", {}) is Dictionary:
			fam.set("trait_bias", (entry.get("trait_bias") as Dictionary).duplicate(true))
		fams[fid] = fam
		n += 1
		if n >= 3:
			break
	return n


func _preseed_fingerprints() -> int:
	if Fingerprints == null:
		return 0
	var pool: Array = []
	for run_any in runs:
		if not (run_any is Dictionary):
			continue
		var run: Dictionary = run_any
		var arr: Variant = run.get("revealed_fingerprints", [])
		if arr is Array:
			for op in (arr as Array):
				var s: String = String(op)
				if s != "" and not pool.has(s):
					pool.append(s)
	if pool.is_empty():
		return 0
	pool.shuffle()
	var pick: int = mini(3, pool.size())
	var n: int = 0
	for i in range(pick):
		Fingerprints.set_level(pool[i], Fingerprints.LEVEL_MECHANISM)
		n += 1
	return n


func _seed_rumour_letter() -> bool:
	if Inbox == null or known_rumours.is_empty():
		return false
	var pick: Dictionary = known_rumours[known_rumours.size() - 1]
	var text: String = String(pick.get("text", "")).strip_edges()
	if text == "":
		return false
	var date: GameDate = GameDate.today()
	var body: String = "Old heads in the wine shops still whisper of it:\n\n\"%s\"\n\nWhether the figure behind it ever drew breath is a matter for tavern wagers." % text
	var l: Letter = Letter.create(
		StringName("rumour_of_legacy_%d" % Time.get_unix_time_from_system()),
		"A traveller",
		date,
		"A rumour that refuses to die",
		body,
		&"rumour",
		&"low"
	)
	Inbox.add_letter(l)
	return true


func _kingdom_exists(kingdom_id: String) -> bool:
	if WorldData == null:
		return false
	if not ("kingdoms" in WorldData):
		return false
	return (WorldData.kingdoms as Dictionary).has(kingdom_id)


func _kind_name_from_int(kind_int: int) -> String:
	var keys: Array = OwnedEntity.Kind.keys()
	if kind_int >= 0 and kind_int < keys.size():
		return String(keys[kind_int])
	return "TRADING_COMPANY"


func clear_profile() -> void:
	runs = []
	legacy_entities = []
	legacy_families = []
	known_rumours = []
	_save_to_disk()


# --- Snapshot / Restore (mirrored into save file too) -----------------------

func snapshot() -> Dictionary:
	return {
		"schema": schema,
		"runs":             runs.duplicate(true),
		"legacy_entities":  legacy_entities.duplicate(true),
		"legacy_families":  legacy_families.duplicate(true),
		"known_rumours":    known_rumours.duplicate(true),
	}


func restore(d: Dictionary) -> void:
	schema = int(d.get("schema", SCHEMA_VERSION))
	runs = (d.get("runs", []) as Array).duplicate(true)
	legacy_entities = (d.get("legacy_entities", []) as Array).duplicate(true)
	legacy_families = (d.get("legacy_families", []) as Array).duplicate(true)
	known_rumours = (d.get("known_rumours", []) as Array).duplicate(true)


# --- Disk I/O ---------------------------------------------------------------

func _save_to_disk() -> void:
	var f: FileAccess = FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[WorldProfile] could not write %s" % PROFILE_PATH)
		return
	f.store_string(JSON.stringify(snapshot(), "\t"))
	f.close()


func _load_from_disk() -> void:
	if not FileAccess.file_exists(PROFILE_PATH):
		return
	var f: FileAccess = FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	restore(parsed)


func _prune() -> void:
	# Keep the profile bounded — arbitrary but generous limits keep
	# new games from paying for every rumour a long-lived profile ever
	# collected.
	if runs.size() > 50: runs = runs.slice(runs.size() - 50)
	if legacy_entities.size() > 500: legacy_entities = legacy_entities.slice(legacy_entities.size() - 500)
	if legacy_families.size() > 500: legacy_families = legacy_families.slice(legacy_families.size() - 500)
	if known_rumours.size() > 400: known_rumours = known_rumours.slice(known_rumours.size() - 400)
