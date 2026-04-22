extends Node
## Autoloaded as `SaveManager`. JSON save/load of the simulation state.
##
## The persistent world state is assembled from each subsystem's own
## snapshot function. This avoids a "god object" WorldState while still
## producing a single serialisable blob.
##
## Not in scope (yet):
##  - Encryption / obfuscation.
##  - Save slot metadata / screenshots.
##  - Ironman rules (§29.1) — one autosave path, overwritten.
##
## Hotkeys:
##   F5  = quicksave to DEFAULT_SLOT
##   F9  = quickload from DEFAULT_SLOT

const SAVE_DIR: String       = "user://saves"
const DEFAULT_SLOT: String   = "quicksave"
const SAVE_VERSION: int      = 1

## Slot used for silent autosaves (year rollover, window close).
## Kept separate from the named slots so an autosave never overwrites
## a player's deliberate fold.
const AUTOSAVE_SLOT: String  = "autosave"


func _ready() -> void:
	GameClock.year_passed.connect(_on_year_passed)
	# Intercept the window close so we can autosave before quitting.
	get_tree().set_auto_accept_quit(false)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST:
			_autosave_on_exit()
			get_tree().quit()


func _on_year_passed(_year: int) -> void:
	if not Session.in_game:
		return
	save_to_slot(AUTOSAVE_SLOT)


func _autosave_on_exit() -> void:
	if not Session.in_game:
		return
	save_to_slot(AUTOSAVE_SLOT)


# --- Public API --------------------------------------------------------------

func save_to_slot(slot: String = DEFAULT_SLOT) -> bool:
	_ensure_dir()
	var path: String = _path_for(slot)
	EventBus.save_requested.emit(path)

	var blob: Dictionary = _collect_state()
	var json: String = JSON.stringify(blob, "\t")

	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[Save] Could not open %s for writing" % path)
		return false
	f.store_string(json)
	f.close()

	print("[Save] Wrote %s (%d bytes)" % [path, json.length()])
	EventBus.save_completed.emit(path)
	return true


func load_from_slot(slot: String = DEFAULT_SLOT) -> bool:
	var path: String = _path_for(slot)
	if not FileAccess.file_exists(path):
		push_warning("[Save] No save at %s" % path)
		return false

	EventBus.load_requested.emit(path)

	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[Save] Could not open %s" % path)
		return false
	var text: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[Save] Save file corrupt: %s" % path)
		return false

	var blob: Dictionary = parsed
	if int(blob.get("version", 0)) != SAVE_VERSION:
		push_warning("[Save] Save version mismatch (got %s, expected %d); attempting to load anyway"
			% [blob.get("version", "?"), SAVE_VERSION])

	_apply_state(blob)
	print("[Save] Loaded %s" % path)
	EventBus.load_completed.emit(path)
	return true


func slot_exists(slot: String = DEFAULT_SLOT) -> bool:
	return FileAccess.file_exists(_path_for(slot))


## Read the header (saved_at, in-game date) of an existing slot without
## applying it. Returns an empty Dictionary if the file is missing or
## malformed. Used by the Archive UI to render slot rows.
func slot_info(slot: String) -> Dictionary:
	var path: String = _path_for(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var clock: Dictionary = parsed.get("clock", {})
	return {
		"slot":      slot,
		"path":      path,
		"saved_at":  String(parsed.get("saved_at", "")),
		"year":      int(clock.get("year",  0)),
		"month":     int(clock.get("month", 1)),
		"day":       int(clock.get("day",   1)),
	}


## Delete a slot file. Returns true if the slot existed and was removed.
func delete_slot(slot: String) -> bool:
	var path: String = _path_for(slot)
	if not FileAccess.file_exists(path):
		return false
	var d: DirAccess = DirAccess.open(SAVE_DIR)
	if d == null:
		return false
	var err: int = d.remove(path.get_file())
	return err == OK


# --- State assembly ----------------------------------------------------------

func _collect_state() -> Dictionary:
	return {
		"version":   SAVE_VERSION,
		"saved_at":  Time.get_datetime_string_from_system(),
		"clock":     _clock_snapshot(),
		"actors":    _actors_snapshot(),
		"inbox":     _inbox_snapshot(),
		"scheduler": Scheduler.snapshot(),
		"exposure":  Exposure.snapshot(),
		"kingdoms":  KingdomEconomy.snapshot(),
		"relations": Relations.snapshot(),
		"news":      PublicNews.snapshot(),
		"purse":     Purse.snapshot(),
		"unrest":    Unrest.snapshot(),
		"population": Population.snapshot(),
		"armies":    Armies.snapshot(),
		"infrastructure": Infrastructure.snapshot(),
		"events":    RandomEvents.snapshot(),
		"whispers":  Whispers.snapshot(),
		"org":       Org.snapshot(),
		"finance":   Finance.snapshot(),
		"picture":      Picture.snapshot(),
		"rivals":       Rivals.snapshot(),
		"fingerprints": Fingerprints.snapshot(),
		"shadow":       Shadow.snapshot(),
		"immortals":    Immortals.snapshot(),
		"beats":        Beats.snapshot(),
	}


func _apply_state(blob: Dictionary) -> void:
	if blob.has("clock"):
		_clock_restore(blob["clock"])
	if blob.has("actors"):
		_actors_restore(blob["actors"])
	if blob.has("inbox"):
		_inbox_restore(blob["inbox"])
	if blob.has("scheduler"):
		Scheduler.restore(blob["scheduler"])
	if blob.has("exposure"):
		Exposure.restore(blob["exposure"])
	if blob.has("kingdoms"):
		KingdomEconomy.restore(blob["kingdoms"])
	if blob.has("relations"):
		Relations.restore(blob["relations"])
	if blob.has("news"):
		PublicNews.restore(blob["news"])
	if blob.has("purse"):
		Purse.restore(blob["purse"])
	if blob.has("unrest"):
		Unrest.restore(blob["unrest"])
	if blob.has("population"):
		Population.restore(blob["population"])
	if blob.has("armies"):
		Armies.restore(blob["armies"])
	if blob.has("infrastructure"):
		Infrastructure.restore(blob["infrastructure"])
	if blob.has("events"):
		RandomEvents.restore(blob["events"])
	if blob.has("whispers"):
		Whispers.restore(blob["whispers"])
	if blob.has("org"):
		Org.restore(blob["org"])
	if blob.has("finance"):
		Finance.restore(blob["finance"])
	if blob.has("picture"):
		Picture.restore(blob["picture"])
	if blob.has("rivals"):
		Rivals.restore(blob["rivals"])
	if blob.has("fingerprints"):
		Fingerprints.restore(blob["fingerprints"])
	if blob.has("shadow"):
		Shadow.restore(blob["shadow"])
	if blob.has("immortals"):
		Immortals.restore(blob["immortals"])
	if blob.has("beats"):
		Beats.restore(blob["beats"])


# --- Clock -------------------------------------------------------------------

func _clock_snapshot() -> Dictionary:
	return {
		"year":  GameClock.year,
		"month": GameClock.month,
		"day":   GameClock.day,
		"speed": int(GameClock.speed),
	}


func _clock_restore(d: Dictionary) -> void:
	GameClock.year  = int(d.get("year",  GameClock.year))
	GameClock.month = int(d.get("month", GameClock.month))
	GameClock.day   = int(d.get("day",   GameClock.day))
	# set_speed is the public setter that emits speed_changed so the UI
	# dial refreshes its pressed state. The caller is responsible for
	# refreshing the date label directly after load finishes.
	GameClock.set_speed(int(d.get("speed", int(GameClock.Speed.PAUSED))))


# --- Actors ------------------------------------------------------------------

func _actors_snapshot() -> Array:
	var out: Array = []
	for a in Actors.all_actors():
		out.append(a.to_dict())
	return out


func _actors_restore(arr: Array) -> void:
	var fresh: Dictionary = {}
	for d in arr:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var a: Actor = Actor.from_dict(d)
		if a.id == &"":
			continue
		fresh[a.id] = a
	# Swap the registry contents wholesale so stale ids from the JSON
	# baseline don't linger after loading a more-recent save.
	Actors.actors = fresh
	Actors._rebuild_indices()


# --- Inbox -------------------------------------------------------------------

func _inbox_snapshot() -> Array:
	var out: Array = []
	for l in Inbox.letters:
		out.append(_letter_to_dict(l))
	return out


func _inbox_restore(arr: Array) -> void:
	Inbox.letters.clear()
	for d in arr:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		Inbox.letters.append(_letter_from_dict(d))
	Inbox.letters_changed.emit()


func _letter_to_dict(l: Letter) -> Dictionary:
	return {
		"id":      String(l.id),
		"sender":  l.sender,
		"year":    l.date.year if l.date != null else 0,
		"month":   l.date.month if l.date != null else 1,
		"day":     l.date.day if l.date != null else 1,
		"subject": l.subject,
		"body":    l.body,
		"is_read": l.is_read,
		"kind":    String(l.kind),
	}


func _letter_from_dict(d: Dictionary) -> Letter:
	var date: GameDate = GameDate.make(
		int(d.get("year", 500)),
		int(d.get("month", 1)),
		int(d.get("day", 1))
	)
	var l: Letter = Letter.create(
		StringName(String(d.get("id", ""))),
		String(d.get("sender", "")),
		date,
		String(d.get("subject", "")),
		String(d.get("body", "")),
		StringName(String(d.get("kind", "misc"))),
	)
	l.is_read = bool(d.get("is_read", false))
	return l


# --- Filesystem --------------------------------------------------------------

func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _path_for(slot: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, slot]
