extends Node
## Autoloaded as `Chronicle`. Listens to a handful of
## "these will matter to the player a year from now" signals and
## captures a brief line for each, with the in-game date attached.
## On demand (hotkey or session end) the chronicle is dumped to a
## markdown file under `user://chronicles/`, which the player can
## open with any text editor.
##
## Intentional scope: this is not a full event log. It is the
## "what happened in my playthrough" retrospective — the one a
## human wants to read later. Keep the signal surface tight.
##
## Persists through save/load via snapshot()/restore() so reloads
## don't amnesia the first 200 years of your run.

const DIR: String = "user://chronicles"

## Emitted when the chronicle is written to disk. Signals the
## audio director for a seal SFX and any other observers that a
## milestone drafting happened.
signal chronicle_sealed(path: String)

# Array of Dictionaries: {year:int, month:int, day:int, date:String, kind:StringName, text:String}
var _entries: Array = []

# Ids we only want to log the first time we notice them.
var _seen_religions: Dictionary = {}
var _seen_societies: Dictionary = {}

# Start-of-session marker, set on first connect (or first restore).
var _started_year: int = 0
var _started_ingame_date: String = ""


func _ready() -> void:
	DevLogger.write("Chronicle: ready")
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)

	# Record the starting date once we know the clock has caught up
	# with whatever save we booted from. Deferred so autoload order
	# doesn't race us.
	call_deferred("_maybe_record_start")

	if Eras != null and Eras.has_signal("era_changed"):
		Eras.era_changed.connect(_on_era_changed)
	if Base != null and Base.has_signal("move_completed"):
		Base.move_completed.connect(_on_base_move_completed)
	if Religions != null and Religions.has_signal("religion_added"):
		Religions.religion_added.connect(_on_religion_added)
	if EventBus != null and EventBus.has_signal("actor_died"):
		EventBus.actor_died.connect(_on_actor_died)
	if Failures != null:
		if Failures.has_signal("state_entered"):
			Failures.state_entered.connect(_on_failure_entered)
		if Failures.has_signal("state_recovered"):
			Failures.state_recovered.connect(_on_failure_recovered)
	if Fingerprints != null and Fingerprints.has_signal("society_identified"):
		Fingerprints.society_identified.connect(_on_society_identified)


func _maybe_record_start() -> void:
	if _started_ingame_date != "":
		return
	if GameClock == null:
		return
	_started_year = GameClock.year
	_started_ingame_date = GameClock.format_date()
	_push(&"session_start", "The chronicle opens. %s." % _started_ingame_date)


# --- Public API -------------------------------------------------------------

func add_entry(kind: StringName, text: String) -> void:
	_push(kind, text)


## Write the chronicle to disk. If `path` is empty, a timestamped
## file under `user://chronicles/` is created. Returns the absolute
## path (or "" on failure).
func save_to_markdown(path: String = "") -> String:
	if path.is_empty():
		var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
		path = "%s/chronicle_%s.md" % [DIR, stamp]

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[Chronicle] cannot open %s for write: %s" % [path, FileAccess.get_open_error()])
		return ""

	file.store_line("# Silent Dominion — a chronicle")
	file.store_line("")
	file.store_line("*Drafted at %s by the keeper of the table.*" % Time.get_datetime_string_from_system())
	file.store_line("")
	var closing_date: String = ""
	if GameClock != null:
		closing_date = GameClock.format_date()
	if _started_ingame_date != "" and closing_date != "":
		file.store_line("From **%s** to **%s**." % [_started_ingame_date, closing_date])
	elif closing_date != "":
		file.store_line("Closing date: **%s**." % closing_date)
	file.store_line("")
	file.store_line("---")
	file.store_line("")

	if _entries.is_empty():
		file.store_line("*No events of consequence were recorded.*")
	else:
		var last_year: int = 0x7fffffff
		for e_any in _entries:
			var e: Dictionary = e_any
			var y: int = int(e.get("year", 0))
			if y != last_year:
				if last_year != 0x7fffffff:
					file.store_line("")
				file.store_line("## %s" % _year_header(y))
				file.store_line("")
				last_year = y
			file.store_line("- **%s** — %s" % [String(e.get("date", "")), String(e.get("text", ""))])

	file.close()

	if Inbox != null:
		var date: GameDate = GameDate.today()
		var letter: Letter = Letter.create(
			&"chronicle_saved",
			"The scribe",
			date,
			"A chronicle was drafted",
			"The keeper of the table closes the ledger. The record you asked for was pressed into:\n\n%s" % path,
			&"system"
		)
		Inbox.add_letter(letter)

	chronicle_sealed.emit(path)
	return path


func entries() -> Array:
	return _entries


# --- Signal handlers --------------------------------------------------------

func _on_era_changed(prev_id: StringName, new_id: StringName) -> void:
	var prev_name: String = _era_name(prev_id)
	var new_name: String = _era_name(new_id)
	_push(&"era", "The %s gave way to the %s." % [prev_name, new_name])


func _on_base_move_completed(arrival_province: String) -> void:
	var prov_name: String = _province_name(arrival_province)
	_push(&"base", "The operation's heart settled in %s." % prov_name)


func _on_religion_added(id: StringName) -> void:
	if _seen_religions.has(id):
		return
	_seen_religions[id] = true
	var nm: String = "a new faith"
	if Religions != null:
		var r: Religion = Religions.get_religion(id)
		if r != null and not r.religion_name.is_empty():
			nm = r.religion_name
	_push(&"religion", "A new faith took root: %s." % nm)


func _on_actor_died(actor_id: StringName, was_host: bool, _cause: StringName) -> void:
	if not was_host:
		return
	var who: String = "A host"
	if Actors != null:
		var a: Actor = Actors.get_actor(actor_id)
		if a != null:
			var nm: String = a.display_name()
			if not nm.is_empty():
				who = nm
	_push(&"host_lost", "%s, a host of the operation, was lost." % who)


func _on_failure_entered(state: int, _ctx: Dictionary) -> void:
	var nm: String = _failure_name(state)
	_push(&"machine", "The Machine entered %s." % nm)


func _on_failure_recovered(state: int) -> void:
	var nm: String = _failure_name(state)
	_push(&"machine", "The Machine recovered from %s." % nm)


func _failure_name(state: int) -> String:
	if Failures == null:
		return "a degraded state"
	var names: Dictionary = Failures.STATE_NAMES as Dictionary
	return String(names.get(state, "a degraded state"))


func _on_society_identified(society_id: StringName, confirmation: int) -> void:
	if confirmation < 50:
		return
	if _seen_societies.has(society_id):
		return
	_seen_societies[society_id] = true
	var nm: String = _society_name(society_id)
	_push(&"rivals", "A rival society stood revealed: %s." % nm)


# --- Internals --------------------------------------------------------------

func _push(kind: StringName, text: String) -> void:
	if GameClock == null:
		return
	_entries.append({
		"year":  GameClock.year,
		"month": GameClock.month,
		"day":   GameClock.day,
		"date":  GameClock.format_date(),
		"kind":  kind,
		"text":  text,
	})


func _year_header(y: int) -> String:
	if y < 0:
		return "Year %d BCE" % -y
	if y == 0:
		return "Year 1 BCE"
	return "Year %d CE" % y


func _era_name(id: StringName) -> String:
	if Eras == null:
		return String(id)
	if Eras.has_method("get_era"):
		var e: Era = Eras.get_era(id)
		if e != null and not e.display_name.is_empty():
			return e.display_name
	return String(id)


func _province_name(pid: String) -> String:
	if WorldData == null:
		return pid
	var p: Province = WorldData.get_province(pid)
	if p != null and not p.province_name.is_empty():
		return p.province_name
	return pid


func _society_name(sid: StringName) -> String:
	if Rivals == null:
		return String(sid)
	var s: RivalSociety = Rivals.get_society(sid)
	if s != null and not s.display_name.is_empty():
		return s.display_name
	return String(sid)


# --- Persistence ------------------------------------------------------------

func snapshot() -> Dictionary:
	return {
		"entries": _entries.duplicate(true),
		"seen_religions": _seen_religions.duplicate(true),
		"seen_societies": _seen_societies.duplicate(true),
		"started_year": _started_year,
		"started_ingame_date": _started_ingame_date,
	}


func restore(d: Dictionary) -> void:
	var raw_v: Variant = d.get("entries", [])
	var raw: Array = raw_v if raw_v is Array else []
	_entries.clear()
	for e_any in raw:
		if e_any is Dictionary:
			_entries.append((e_any as Dictionary).duplicate(true))
	var sr_raw: Variant = d.get("seen_religions", {})
	_seen_religions = (sr_raw as Dictionary).duplicate(true) if sr_raw is Dictionary else {}
	var ss_raw: Variant = d.get("seen_societies", {})
	_seen_societies = (ss_raw as Dictionary).duplicate(true) if ss_raw is Dictionary else {}
	_started_year = int(d.get("started_year", 0))
	_started_ingame_date = String(d.get("started_ingame_date", ""))
