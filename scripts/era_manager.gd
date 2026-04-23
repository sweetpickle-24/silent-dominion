extends Node
## Autoloaded as `Eras`. Tracks the current era and emits transitions
## when the game clock crosses an era boundary (§6.2).
##
## Eras are read from `res://data/eras.json` on boot. The current era
## is the one whose window `covers(GameClock.year)`. Listeners use
## `current` / `current_id()` for queries, and connect to
## `era_changed(prev_id, new_id)` for transitions.
##
## What the rest of the game does with this:
##   - Scheduler / Actions scale dispatch delay by
##     `Eras.current.communication_multiplier`.
##   - Picture / Exposure decay factor reads
##     `Eras.current.visibility_decay_multiplier`.
##   - Languages uses era transitions as the hook to evolve
##     vernaculars and retire dead languages (§23.5).
##   - Table chrome & fonts swap when `era_changed` fires.
##
## Era transitions are rare (roughly every few centuries of play) so
## it's fine to do meaningful work inside the signal — language
## evolution, chronicle entries, table re-theming.

signal era_changed(prev_id: StringName, new_id: StringName)

const DATA_PATH: String = "res://data/eras.json"

var eras: Array[Era] = []
var current: Era = null


func _ready() -> void:
	DevLogger.write("Eras: ready")
	_load_data()
	_initialise()
	GameClock.year_passed.connect(_on_year_passed)


# --- Public API --------------------------------------------------------------

func current_id() -> StringName:
	if current == null:
		return &""
	return current.id


func get_era(id: StringName) -> Era:
	for e in eras:
		if e.id == id:
			return e
	return null


func era_for_year(year: int) -> Era:
	for e in eras:
		if e.covers(year):
			return e
	# Before the first or after the last — clamp to nearest.
	if not eras.is_empty():
		if year < eras[0].year_start:
			return eras[0]
		return eras[eras.size() - 1]
	return null


func communication_multiplier() -> float:
	if current == null:
		return 1.0
	return current.communication_multiplier


func visibility_decay_multiplier() -> float:
	if current == null:
		return 1.0
	return current.visibility_decay_multiplier


# --- Internals ---------------------------------------------------------------

func _load_data() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("[Eras] %s missing — era progression disabled." % DATA_PATH)
		return
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_warning("[Eras] could not open %s" % DATA_PATH)
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[Eras] malformed eras.json")
		return
	var arr: Array = parsed.get("eras", [])
	eras.clear()
	for entry in arr:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		eras.append(Era.from_dict(entry))
	eras.sort_custom(func(a, b): return a.year_start < b.year_start)


func _initialise() -> void:
	current = era_for_year(GameClock.year)


func _on_year_passed(_y: int) -> void:
	var fresh: Era = era_for_year(GameClock.year)
	if fresh == null or current == null:
		current = fresh
		return
	if fresh.id == current.id:
		return
	var prev_id: StringName = current.id
	current = fresh
	era_changed.emit(prev_id, current.id)
	_announce_transition(prev_id, current)


func _announce_transition(prev_id: StringName, new_era: Era) -> void:
	var date: GameDate = GameDate.today()
	var prev_era: Era = get_era(prev_id)
	var prev_label: String = prev_era.display_name if prev_era != null else String(prev_id)
	var body: String = (
		"The ground has shifted beneath the work. What was called "
		+ "%s is closing; what is opening has the shape of the %s.\n\n%s"
	) % [prev_label, new_era.display_name, new_era.blurb]
	var letter: Letter = Letter.create(
		StringName("era_transition_%s_%d" % [String(new_era.id), -GameClock.year]),
		"The Chronicle",
		date,
		"The age turns — %s" % new_era.display_name,
		body,
		&"news"
	)
	EventBus.letter_delivered.emit(letter)


# --- Save / load -------------------------------------------------------------

func snapshot() -> Dictionary:
	return {
		"current_id": String(current.id) if current != null else "",
	}


func restore(d: Dictionary) -> void:
	var cid: StringName = StringName(String(d.get("current_id", "")))
	if cid != &"":
		var match: Era = get_era(cid)
		if match != null:
			current = match
			return
	current = era_for_year(GameClock.year)
