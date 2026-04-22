extends Node
## Autoloaded as `PublicNews`. Ring buffer of public events.
##
## Everything emitted on EventBus.public_event lands here — whether it
## came from the WorldAI (autonomous world) or from the player's own
## high-intervention actions (future). The Public Dispatches scroll on
## the table reads this buffer.
##
## Entries are plain Dictionaries so they round-trip through JSON saves
## cleanly. Expected keys on each event:
##   kind:       StringName — e.g. &"ruler_decree", &"war", &"death"
##   headline:   String     — short period-voice title
##   body:       String     — longer prose, BBCode allowed
##   abs_day:    int        — GameClock.absolute_day() at authoring
##   kingdom_id: String     — optional, for filtering/colouring
##   actors:     Array      — optional, list of actor ids referenced

signal news_added(event: Dictionary)
signal news_changed

const MAX_EVENTS: int = 240

var events: Array = []


func _ready() -> void:
	EventBus.public_event.connect(_on_public_event)
	_seed_placeholder_events()


## Seed a small set of dispatches so the scroll isn't empty on first
## boot. Called once; ignored if events have already been loaded (via a
## save restore) or already accumulated through other means.
func _seed_placeholder_events() -> void:
	if not events.is_empty():
		return
	var today: int = GameClock.absolute_day()
	events.append({
		"kind":      &"misc",
		"headline":  "A quiet turn of the year",
		"body":      "The new year opens without great noise. Grain is priced as last year's was; no army has moved; no oracle of consequence has spoken. The world waits, as it always does, for the first thing to happen.",
		"abs_day":   today,
		"read":      false,
	})
	events.append({
		"kind":      &"ruler_decree",
		"headline":  "The tyrant's fast",
		"body":      "From Athens, word: Hippias has decreed three days of fast in the city before the festival of Theseus. The notables obey. The markets are sparse. No one admits to being glad when it ends.",
		"abs_day":   today,
		"read":      false,
	})
	news_changed.emit()


func _on_public_event(event: Dictionary) -> void:
	add(event)


## Append an event to the ring. Missing timestamp is filled from
## the game clock. Oldest events are discarded once the buffer
## overflows MAX_EVENTS.
func add(event: Dictionary) -> void:
	var e: Dictionary = event.duplicate(true)
	if not e.has("abs_day"):
		e["abs_day"] = GameClock.absolute_day()
	if not e.has("kind"):
		e["kind"] = &"misc"
	events.append(e)
	if events.size() > MAX_EVENTS:
		events = events.slice(events.size() - MAX_EVENTS, events.size())
	news_added.emit(e)
	news_changed.emit()


func unread_count() -> int:
	var n: int = 0
	for e in events:
		if not bool(e.get("read", false)):
			n += 1
	return n


func mark_all_read() -> void:
	var changed: bool = false
	for e in events:
		if not bool(e.get("read", false)):
			e["read"] = true
			changed = true
	if changed:
		news_changed.emit()


# --- Save/load hooks ---------------------------------------------------------

func snapshot() -> Array:
	return events.duplicate(true)


func restore(arr: Array) -> void:
	events.clear()
	for entry in arr:
		if typeof(entry) == TYPE_DICTIONARY:
			events.append(entry.duplicate(true))
	news_changed.emit()
