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
signal worldwide_event_delivered(event: Dictionary)

## §B12 Reach tier for a public event. Orthogonal to `channel` (which
## describes *who* carried the news). The tier asks *how far the
## story reaches*.
##   WORLDWIDE — the death of a pharaoh, a great battle's outcome.
##               Every kingdom talks about it. If the player has the
##               auto-pause pref, the clock stops when one lands.
##   STATE     — a kingdom-level event: a new tax, a regency declared.
##               Visible on the map digest and the scroll.
##   FACTIONAL — tied to a faction/institution: a banking house
##               cornering the silver, a religion schism.
##   LOCAL     — a market rumour, a village harvest. Present on the
##               scroll for colour but filtered from the world digest.
enum Tier { WORLDWIDE, STATE, FACTIONAL, LOCAL }

const MAX_EVENTS: int = 240

const DELIVERY_TASK_KIND: StringName = &"news_delivery"

# Channel delay ranges in days. The actual delay is sampled per event
# so two events of the same kind don't always arrive on the same day.
const OPERATIVE_DELAY: Array[int]  = [0, 3]
const NEUTRAL_DELAY: Array[int]    = [14, 60]
const OFFICIAL_DELAY: Array[int]   = [30, 90]

# §B13 Propagation models. How a story reaches the player's table.
const PROP_RADIAL:        StringName = &"radial"
const PROP_ROUTE:         StringName = &"route"
const PROP_INSTITUTIONAL: StringName = &"institutional"

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

# §B12 Tier inference by kind. Anything not listed gets LOCAL.
const WORLDWIDE_KINDS: Array[StringName] = [
	&"succession", &"war_declaration", &"peace_declaration",
	&"ruler_death", &"immortal_revealed", &"dynasty_fall",
]
const STATE_KINDS: Array[StringName] = [
	&"tax_change", &"ruler_decree", &"fiscal_crisis", &"fiscal_recovery",
	&"army_shift", &"army_logistics_cut", &"war_weariness",
	&"population_collapse", &"population_boom", &"unrest_crisis",
	&"construction_start", &"construction_done",
	&"plague", &"famine", &"bank_veto",
]
const FACTIONAL_KINDS: Array[StringName] = [
	&"banking_house_added", &"banking_house_compromised",
	&"rival_op", &"religion_event",
	&"entity_event", &"society_acted",
	&"false_flag", &"severed_cell", &"routed_letter",
]

# Rival society operations carry their own signature and arrive
# through whichever channel matches their cover. RivalRegistry stamps
# the "channel" field on those events directly; we respect it.

var events: Array = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _region_centroid_cache: Dictionary = {}   # region_id -> Vector2 uv centroid


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
	# §C3 — do not seed a ghost ruler (Athens has no actor-ruler in the
	# current data). Pull a real ruler from one of the kingdoms that
	# actually has one, deterministically. If none is loaded yet we
	# defer; if none exists at all, skip the decree entirely.
	if WorldData != null and not WorldData.is_loaded():
		WorldData.world_loaded.connect(_seed_placeholder_decree, CONNECT_ONE_SHOT)
	else:
		_seed_placeholder_decree()
	news_changed.emit()


func _seed_placeholder_decree() -> void:
	if Actors == null:
		return
	var picks: Array = ["sparta", "persia", "athens", "rome", "carthage"]
	var ruler: Actor = null
	var ruler_kid: String = ""
	for kid in picks:
		ruler = Actors.ruler_of(kid)
		if ruler != null:
			ruler_kid = kid
			break
	if ruler == null:
		# Any living ruler in any kingdom.
		for a in Actors.actors_by_role(Actor.Role.RULER):
			if a != null and a.is_alive():
				ruler = a
				ruler_kid = a.kingdom_id
				break
	if ruler == null:
		return
	var k: Kingdom = WorldData.get_kingdom(ruler_kid)
	var kname: String = k.kingdom_name if k != null else ruler_kid.capitalize()
	var today: int = GameClock.absolute_day()
	events.append({
		"kind":      &"ruler_decree",
		"channel":   "official",
		"headline":  "A decree out of %s" % kname,
		"body":      ("From %s, word: %s has issued a new decree, touching grain, "
					+ "tax, and the shape of the coming season. The notables repeat "
					+ "it; the markets adjust; no one in earshot admits to being surprised."
					) % [kname, ruler.display_name()],
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
	if not stamped.has("tier"):
		stamped["tier"] = int(_tier_for(stamped))
	if not stamped.has("propagation"):
		stamped["propagation"] = String(_propagation_for(stamped))
	var base_delay: int = _delay_for_channel(StringName(String(stamped["channel"])))
	var delay: int = maxi(0, int(round(float(base_delay) * _propagation_modifier(stamped))))
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


## §B12 Infer a Tier from a raw event dictionary.
func _tier_for(event: Dictionary) -> int:
	var kind: StringName = StringName(String(event.get("kind", "")))
	if WORLDWIDE_KINDS.has(kind):
		return int(Tier.WORLDWIDE)
	if STATE_KINDS.has(kind):
		return int(Tier.STATE)
	if FACTIONAL_KINDS.has(kind):
		return int(Tier.FACTIONAL)
	return int(Tier.LOCAL)


## §B13 Infer a propagation model from an event dict. Emitters may
## override by setting `propagation` directly — this is only called
## when they don't.
func _propagation_for(event: Dictionary) -> StringName:
	var kind: StringName = StringName(String(event.get("kind", "")))
	# Rival-authored / op-stamped → institutional (bankers gossip first).
	if event.has("rival_signature") or event.has("institution_id"):
		return PROP_INSTITUTIONAL
	# Trade / market / fiscal moves → follow the trade routes.
	match kind:
		&"tax_change", &"fiscal_crisis", &"fiscal_recovery", \
		&"banking_house_added", &"banking_house_compromised", \
		&"bank_veto":
			return PROP_ROUTE
	# Anything geographically grounded defaults to radial.
	if event.has("province") or event.has("kingdom_id"):
		return PROP_RADIAL
	return PROP_RADIAL


## §B13 Distance-scaled delay modifier. Returns 1.0 at zero distance
## and smoothly expands / contracts based on propagation model.
func _propagation_modifier(event: Dictionary) -> float:
	var mode: StringName = StringName(String(event.get("propagation", PROP_RADIAL)))
	match mode:
		PROP_RADIAL:
			return _radial_modifier(event)
		PROP_ROUTE:
			return _route_modifier(event)
		PROP_INSTITUTIONAL:
			# Institutions talk to each other fast. If the event
			# reaches a banking house / religion / academy node,
			# it's on our table quickly.
			return 0.60
	return 1.0


func _radial_modifier(event: Dictionary) -> float:
	var origin_region: String = _event_origin_region(event)
	if origin_region == "":
		return 1.0
	var here: String = Base.province_id if Base.province_id != "" else origin_region
	var dist: float = _region_distance(origin_region, here)
	# 0.0 distance → 0.8 (local news is a little quicker than baseline).
	# Maximum map-diagonal distance → ~1.8 (far news grinds in).
	return clampf(0.80 + dist * 1.0, 0.6, 2.0)


func _route_modifier(event: Dictionary) -> float:
	var origin_region: String = _event_origin_region(event)
	if origin_region == "":
		return 1.0
	var origin: Province = WorldData.get_province(origin_region)
	if origin == null:
		return 1.0
	# A road or port at origin speeds the caravans that carry the
	# news; a province with neither is route-slow.
	if origin.has_building(&"harbour"):
		return 0.50
	if origin.has_building(&"road_network"):
		return 0.70
	return 1.30


func _event_origin_region(event: Dictionary) -> String:
	var p: String = String(event.get("province", ""))
	if p != "":
		return p
	var k: String = String(event.get("kingdom_id", ""))
	if k == "":
		return ""
	var kd: Kingdom = WorldData.get_kingdom(k)
	if kd == null or kd.owned_provinces.is_empty():
		return ""
	return kd.owned_provinces[0]


func _region_distance(a_region: String, b_region: String) -> float:
	if a_region == b_region:
		return 0.0
	var a: Vector2 = _region_centroid(a_region)
	var b: Vector2 = _region_centroid(b_region)
	if a == Vector2.ZERO or b == Vector2.ZERO:
		return 0.0
	# UV space is 0..1 on both axes; diagonal = sqrt(2) ≈ 1.414.
	return clampf(a.distance_to(b), 0.0, 1.414)


func _region_centroid(region_id: String) -> Vector2:
	if _region_centroid_cache.has(region_id):
		return _region_centroid_cache[region_id]
	if MapData == null or not MapData.cells_by_region.has(region_id):
		return Vector2.ZERO
	var ids: Array = MapData.cells_by_region[region_id]
	if ids.is_empty():
		return Vector2.ZERO
	var sum: Vector2 = Vector2.ZERO
	var count: int = 0
	for cid in ids:
		var cell: MapCell = MapData.cells.get(int(cid), null)
		if cell == null:
			continue
		sum += cell.center_uv
		count += 1
	if count == 0:
		return Vector2.ZERO
	var c: Vector2 = sum / float(count)
	_region_centroid_cache[region_id] = c
	return c


func tier_name(t: int) -> String:
	match t:
		int(Tier.WORLDWIDE): return "worldwide"
		int(Tier.STATE):     return "state"
		int(Tier.FACTIONAL): return "factional"
		int(Tier.LOCAL):     return "local"
	return "local"


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
	if not e.has("tier"):
		e["tier"] = int(_tier_for(e))
	_apply_narrator_bias(e)
	_apply_calibration(e)
	events.append(e)
	if events.size() > MAX_EVENTS:
		events = events.slice(events.size() - MAX_EVENTS, events.size())
	news_added.emit(e)
	news_changed.emit()
	if int(e.get("tier", int(Tier.LOCAL))) == int(Tier.WORLDWIDE):
		worldwide_event_delivered.emit(e)


# --- §B14 Narrator bias ------------------------------------------------------

## If the event has a `narrator_id`, look up the intermediary and
## rewrite headline/body to reflect their personality. Does nothing
## if no narrator is stamped — emitters opt in.
##
## Rules (small, consistent nudges — we are not rewriting prose):
##   paranoia ≥ 70  → hedge words prepended to body ("it is said that…").
##   ambition ≥ 70  → headline gains an intensifier suffix.
##   loyalty  ≥ 70  → soften ruler criticism if the body mentions them.
func _apply_narrator_bias(e: Dictionary) -> void:
	var narrator_id: StringName = StringName(String(e.get("narrator_id", "")))
	if narrator_id == &"":
		return
	var actor: Actor = Actors.get_actor(narrator_id)
	if actor == null:
		return
	var paranoid: bool = actor.paranoia >= 70
	var ambitious: bool = actor.ambition >= 70
	var loyal: bool = actor.loyalty >= 70
	var body: String = String(e.get("body", ""))
	var headline: String = String(e.get("headline", ""))
	if paranoid and body != "":
		body = "It is said that " + _lower_first(body)
	if loyal:
		body = body.replace("tyrant", "ruler") \
			.replace("usurper", "ruler") \
			.replace("Hippias's crimes", "the ruler's hard decisions")
	if ambitious and headline != "":
		headline = headline + " — and the consequences will be felt"
	e["headline"] = headline
	e["body"] = body
	e["narrator_bias_applied"] = true


static func _lower_first(s: String) -> String:
	if s.is_empty():
		return s
	return s.substr(0, 1).to_lower() + s.substr(1)


# --- §10.5 Calibration against operative reports ----------------------------
#
# Each delivered event is scored 0..1 against the current inbox. Letters
# whose subject or body mentions the same region / kingdom / actor as the
# event contribute their tokens to a "reference" bag; the event's own
# tokens form the "observed" bag. Jaccard overlap of the two bags is the
# calibration score; we bucket the result into one of three verdicts:
#   - matches operative dispatches (>= 0.45)
#   - partial overlap             (>= 0.15)
#   - contradicts operative dispatches (< 0.15 but references present)
# If no overlapping reference letter exists, the event gets
# calibration_verdict = &"no_reference" and is not drawn with a band.
const _CALIBRATION_MATCH: StringName     = &"matches"
const _CALIBRATION_PARTIAL: StringName   = &"partial"
const _CALIBRATION_CONTRADICT: StringName = &"contradicts"
const _CALIBRATION_NONE: StringName      = &"no_reference"

func _apply_calibration(e: Dictionary) -> void:
	# Operative-channel events are self-reports; calibration is
	# meaningless there.
	if String(e.get("channel", "neutral")) == "operative":
		e["calibration_verdict"] = _CALIBRATION_NONE
		e["calibration_score"] = 0.0
		return
	var ref_bag: Dictionary = _reference_bag(e)
	if ref_bag.is_empty():
		e["calibration_verdict"] = _CALIBRATION_NONE
		e["calibration_score"] = 0.0
		return
	var observed: Dictionary = _tokenise(String(e.get("headline", "")) + " " + String(e.get("body", "")))
	var score: float = _jaccard(observed, ref_bag)
	e["calibration_score"] = score
	if score >= 0.45:
		e["calibration_verdict"] = _CALIBRATION_MATCH
	elif score >= 0.15:
		e["calibration_verdict"] = _CALIBRATION_PARTIAL
	else:
		e["calibration_verdict"] = _CALIBRATION_CONTRADICT


func _reference_bag(e: Dictionary) -> Dictionary:
	# Candidate operative letters: recent + referencing the same anchor.
	var bag: Dictionary = {}
	var inbox: Node = get_tree().root.get_node_or_null("Inbox")
	if inbox == null:
		return bag
	var letters: Array = inbox.letters if "letters" in inbox else []
	var province: String = String(e.get("province", ""))
	var kingdom: String = String(e.get("kingdom_id", ""))
	var actors: Array = e.get("actor_ids", []) if e.has("actor_ids") else []
	for l in letters:
		if not (l is Letter):
			continue
		# Only operative-flavoured letters count as "the truth on the
		# ground" — the chronicle / news kinds share propagation with
		# the event so aren't a useful reference.
		var k: StringName = (l as Letter).kind
		if k != &"field" and k != &"intel" and k != &"dispatch" and k != &"operative":
			if k != &"misc":
				continue
		var text: String = (l as Letter).subject + " " + (l as Letter).body
		# Anchor match: require at least one mention.
		var hit: bool = false
		if province != "" and text.findn(province) != -1: hit = true
		if not hit and kingdom != "" and text.findn(kingdom) != -1: hit = true
		if not hit:
			for aid in actors:
				if text.findn(String(aid)) != -1:
					hit = true
					break
		if not hit:
			continue
		for tok in _tokenise(text).keys():
			bag[tok] = true
	return bag


static func _tokenise(text: String) -> Dictionary:
	var bag: Dictionary = {}
	var lower: String = text.to_lower()
	var cursor: String = ""
	for ch in lower:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			cursor += ch
		else:
			if cursor.length() >= 4 and not _STOPWORDS.has(cursor):
				bag[cursor] = true
			cursor = ""
	if cursor.length() >= 4 and not _STOPWORDS.has(cursor):
		bag[cursor] = true
	return bag


static func _jaccard(a: Dictionary, b: Dictionary) -> float:
	if a.is_empty() or b.is_empty():
		return 0.0
	var inter: int = 0
	var seen: Dictionary = {}
	for k in a.keys():
		seen[k] = true
		if b.has(k):
			inter += 1
	var union: int = seen.size()
	for k in b.keys():
		if not seen.has(k):
			union += 1
	if union == 0:
		return 0.0
	return float(inter) / float(union)


const _STOPWORDS: Dictionary = {
	"that": true, "with": true, "from": true, "this": true, "into": true,
	"have": true, "they": true, "their": true, "there": true, "about": true,
	"which": true, "would": true, "could": true, "should": true, "these": true,
	"those": true, "been": true, "were": true, "will": true, "them": true,
	"than": true, "such": true, "also": true, "when": true, "while": true,
	"very": true, "over": true, "some": true, "upon": true, "only": true,
}


## Return the verdict label as human prose (for the UI band).
func calibration_phrase(verdict: StringName) -> String:
	match verdict:
		_CALIBRATION_MATCH:      return "Matches our operative dispatches."
		_CALIBRATION_PARTIAL:    return "Partial overlap with operative dispatches."
		_CALIBRATION_CONTRADICT: return "Contradicts operative dispatches."
		_:                       return ""


# --- Filter helpers ---------------------------------------------------------

## Events at or above a given tier (lower enum values = broader reach).
## Use for the world-level map digest (STATE minimum) and any
## worldwide-only auto-pause feed.
func events_min_tier(min_tier: int) -> Array:
	var out: Array = []
	for e in events:
		if int(e.get("tier", int(Tier.LOCAL))) <= min_tier:
			out.append(e)
	return out


## Events whose tier matches exactly. Used when the UI needs to show
## per-bucket counts (e.g. "3 state events this year").
func events_of_tier(t: int) -> Array:
	var out: Array = []
	for e in events:
		if int(e.get("tier", int(Tier.LOCAL))) == t:
			out.append(e)
	return out


## Legacy public `add()` — kept so existing call sites that bypass the
## channel system (seed data, save restore) can still inject events
## directly onto the scroll.
func add(event: Dictionary) -> void:
	_deliver(event)


# --- Presentation helpers ---------------------------------------------------

## Short prefix phrase for a given channel. Used by the scroll to
## signal provenance without a separate badge column.
func channel_phrase(channel: String) -> String:
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
