extends Node
## Autoloaded as `PublicNews`. Ring buffer of public events.
##
## Every `EventBus.public_event` is stamped with one of three channels
## (§34.4) and delivered to the scroll with a channel-appropriate
## delay:
##
##   operative  — the player's network, same day or within three.
##   neutral    — merchants, travellers, market price shifts. A fortnight
##                to two months depending on distance and kind.
##   official   — the crown's own announcement. Slowest, but the most
##                formal phrasing; only used for events a state chose
##                to publicise.
##
## The delay metric is rough: two months in-game is the right order of
## magnitude for word to travel across the Mediterranean by ship and
## courier. The channels feel different on the scroll, which is the
## point; precision is not.
##
## Entries are plain Dictionaries so they round-trip through JSON saves
## cleanly. Canonical keys on each delivered event:
##   kind:        StringName
##   headline:    String
##   body:        String
##   abs_day:     int         — GameClock.absolute_day() when delivered
##   origin_day:  int         — absolute_day() when the event happened
##   kingdom_id:  String
##   actors:      Array
##   channel:     String      — "operative", "neutral", or "official"

signal news_added(event: Dictionary)
signal news_changed

const MAX_EVENTS: int = 240

const DELIVERY_TASK_KIND: StringName = &"news_delivery"

# Channel delay ranges in days. The actual delay is sampled per event
# so two events of the same kind don't always arrive on the same day.
const OPERATIVE_DELAY: Array[int]  = [0, 3]
const NEUTRAL_DELAY: Array[int]    = [14, 60]
const OFFICIAL_DELAY: Array[int]   = [30, 90]

# Events whose kind is in the operative set are the player's own
# network talking — they arrive fast. Falsifiable upstream by rival
# counter-intel; that logic lives in RivalRegistry, not here.
const OPERATIVE_KINDS: Array[StringName] = [
	&"rumour", &"plant_idea", &"host_agitate", &"cultivate",
	&"promotion", &"severed_cell", &"routed_letter",
	&"action_success", &"action_failed",
	&"false_flag",
]

# Events that a party chose to publicise. Slow but authoritative.
const OFFICIAL_KINDS: Array[StringName] = [
	&"tax_change", &"ruler_decree", &"succession",
	&"peace_declaration", &"war_declaration",
	&"fiscal_crisis", &"fiscal_recovery",
	&"construction_start", &"construction_done",
]

# Rival society operations carry their own signature and arrive
# through whichever channel matches their cover. RivalRegistry stamps
# the "channel" field on those events directly; we respect it.

var events: Array = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	EventBus.public_event.connect(_on_public_event)
	Scheduler.task_due.connect(_on_task_due)
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
		"channel":   "neutral",
		"headline":  "A quiet turn of the year",
		"body":      "The new year opens without great noise. Grain is priced as last year's was; no army has moved; no oracle of consequence has spoken. The world waits, as it always does, for the first thing to happen.",
		"abs_day":   today,
		"origin_day": today,
		"read":      false,
	})
	events.append({
		"kind":      &"ruler_decree",
		"channel":   "official",
		"headline":  "The tyrant's fast",
		"body":      "From Athens, word: Hippias has decreed three days of fast in the city before the festival of Theseus. The notables obey. The markets are sparse. No one admits to being glad when it ends.",
		"abs_day":   today,
		"origin_day": today,
		"read":      false,
	})
	news_changed.emit()


# --- Intake ------------------------------------------------------------------

func _on_public_event(event: Dictionary) -> void:
	var stamped: Dictionary = event.duplicate(true)
	if not stamped.has("origin_day"):
		stamped["origin_day"] = GameClock.absolute_day()
	if not stamped.has("channel"):
		stamped["channel"] = String(_channel_for(stamped))
	var delay: int = _delay_for_channel(StringName(String(stamped["channel"])))
	if delay <= 0:
		_deliver(stamped)
		return
	Scheduler.schedule_task_in_days(delay, {
		"kind":  String(DELIVERY_TASK_KIND),
		"event": stamped,
	})


func _on_task_due(descriptor: Dictionary) -> void:
	if String(descriptor.get("kind", "")) != String(DELIVERY_TASK_KIND):
		return
	var event: Dictionary = descriptor.get("event", {})
	if typeof(event) != TYPE_DICTIONARY or event.is_empty():
		return
	_deliver(event)


func _channel_for(event: Dictionary) -> StringName:
	# Rival-authored events (false-flag by the player or real rival ops)
	# travel through whichever channel RivalRegistry stamped, or neutral
	# as a safe fallback.
	if event.has("rival_signature"):
		return &"neutral"
	var kind: StringName = StringName(String(event.get("kind", "")))
	if OPERATIVE_KINDS.has(kind):
		return &"operative"
	if OFFICIAL_KINDS.has(kind):
		return &"official"
	return &"neutral"


func _delay_for_channel(channel: StringName) -> int:
	var range_arr: Array
	match channel:
		&"operative": range_arr = OPERATIVE_DELAY
		&"official":  range_arr = OFFICIAL_DELAY
		_:            range_arr = NEUTRAL_DELAY
	return _rng.randi_range(int(range_arr[0]), int(range_arr[1]))


## Final delivery to the scroll buffer.
func _deliver(event: Dictionary) -> void:
	var e: Dictionary = event.duplicate(true)
	e["abs_day"] = GameClock.absolute_day()
	if not e.has("origin_day"):
		e["origin_day"] = e["abs_day"]
	if not e.has("kind"):
		e["kind"] = &"misc"
	if not e.has("channel"):
		e["channel"] = "neutral"
	events.append(e)
	if events.size() > MAX_EVENTS:
		events = events.slice(events.size() - MAX_EVENTS, events.size())
	news_added.emit(e)
	news_changed.emit()


## Legacy public `add()` — kept so existing call sites that bypass the
## channel system (seed data, save restore) can still inject events
## directly onto the scroll.
func add(event: Dictionary) -> void:
	_deliver(event)


# --- Presentation helpers ---------------------------------------------------

## Short prefix phrase for a given channel. Used by the scroll to
## signal provenance without a separate badge column.
static func channel_phrase(channel: String) -> String:
	match channel:
		"operative": return "our own hand reports"
		"official":  return "the crown announces"
		_:           return "travellers say"


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
