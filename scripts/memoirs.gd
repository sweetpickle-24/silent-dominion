extends Node
## Autoloaded as `Memoirs`. The player's pattern library (§13 / §30).
##
## Records successful manual approaches against named actors and
## institutions, then offers them back as automation hints when a
## similar situation arises. A match is a fuzzy comparison over the
## profile variables stored on each pattern — role, kingdom, and
## trait bands. Patterns age out to "unverified" over game-years
## (§13.5); an unverified pattern is still usable but warned about.
##
## This pass delivers the machine: recording, matching, staleness.
## Automation execution and regional dispatch (§13.3) are separate
## passes that will read from this registry.

signal pattern_added(id: StringName)
signal pattern_refreshed(id: StringName, success: bool)
signal pattern_flagged_unverified(id: StringName)


const TRAIT_BAND_LOW: StringName  = &"low"
const TRAIT_BAND_MID: StringName  = &"mid"
const TRAIT_BAND_HIGH: StringName = &"high"

## Match threshold (0..1). Below this we do not offer the pattern.
const MATCH_THRESHOLD: float = 0.6

## Key-by-key similarity contributions (summed then normalised).
## Role is a hard-ish match; kingdom is weaker; traits compare on
## band equality.
const WEIGHT_ROLE:     float = 2.0
const WEIGHT_KINGDOM:  float = 0.5
const WEIGHT_TRAIT:    float = 1.0


# id -> MemoirPattern
var patterns: Dictionary = {}


func _ready() -> void:
	EventBus.action_resolved.connect(_on_action_resolved)
	GameClock.year_passed.connect(_on_year_passed)


# --- Public API --------------------------------------------------------------

func all_patterns() -> Array[MemoirPattern]:
	var out: Array[MemoirPattern] = []
	for p in patterns.values():
		out.append(p)
	out.sort_custom(func(a: MemoirPattern, b: MemoirPattern) -> bool:
		return a.last_verified_year > b.last_verified_year)
	return out


func get_pattern(id: StringName) -> MemoirPattern:
	return patterns.get(id, null)


## Find the strongest pattern in `category` that applies to `target`
## for running `action_id`. Returns null if nothing above threshold.
##
## §23 cultural tagging: matching hard-filters on culture. A pattern
## tagged `latin` does not apply to a `koine_greek` merchant even
## if their trait bands are identical. Cross-culture transfer is a
## deliberate design non-feature — those are "new encounter"
## territory.
func match_for(action_id: StringName, target: Actor) -> MemoirPattern:
	if target == null:
		return null
	var best: MemoirPattern = null
	var best_score: float = 0.0
	var profile: Dictionary = _profile_for_actor(target)
	var target_culture: StringName = _culture_for_actor(target)
	for p in patterns.values():
		if p.action_id != action_id:
			continue
		if p.culture_tag != &"" and target_culture != &"" and p.culture_tag != target_culture:
			continue
		var s: float = _similarity(profile, p.profile)
		if s >= MATCH_THRESHOLD and s > best_score:
			best = p
			best_score = s
	return best


## Match quality as the four §30.2 tiers. Returns one of:
##   &"confident"   (>=0.80)
##   &"approximate" (0.50..0.80)
##   &"unreliable"  (<0.50 but some signal)
##   &"none"        (no pattern at all)
func match_quality(action_id: StringName, target: Actor) -> StringName:
	if target == null:
		return &"none"
	var profile: Dictionary = _profile_for_actor(target)
	var target_culture: StringName = _culture_for_actor(target)
	var best: float = 0.0
	for p in patterns.values():
		if p.action_id != action_id:
			continue
		if p.culture_tag != &"" and target_culture != &"" and p.culture_tag != target_culture:
			continue
		var s: float = _similarity(profile, p.profile)
		if s > best:
			best = s
	# Transition window (§22.4). Patterns against targets in the
	# kingdom the player is still settling into match at reduced
	# reliability — the player has not yet rebuilt direct familiarity.
	if Base != null and target != null:
		var penalty: float = Base.memoirs_quality_penalty_for(target.kingdom_id)
		if penalty > 0.0:
			best = max(0.0, best - penalty)
	if best >= 0.80:
		return &"confident"
	if best >= 0.50:
		return &"approximate"
	if best > 0.0:
		return &"unreliable"
	return &"none"


## Qualitative blurb the compose view can show when offering the
## pattern as automation ("A proven hand on merchants like this.").
func match_offer_phrase(p: MemoirPattern) -> String:
	if p == null:
		return ""
	var culture_phrase: String = ""
	if p.culture_tag != &"":
		culture_phrase = " — cast in a %s mould" % Languages.display_name(p.culture_tag)
	var base: String = "You've walked this one before%s. %s, %s." % [culture_phrase, p.confidence_phrase(), p.stale_phrase()]
	if p.unverified:
		base += " Notes may be out of date."
	return base


# --- Event hooks -------------------------------------------------------------

func _on_action_resolved(action_id: StringName, result: Dictionary) -> void:
	var target_id: String = String(result.get("target_id", ""))
	if target_id == "":
		return
	var target: Actor = Actors.get_actor(StringName(target_id))
	if target == null:
		return
	var success: bool = bool(result.get("success", false))
	# Only record categories we understand — everything else is
	# ignored so the library doesn't fill with noise.
	var category: StringName = _category_for(action_id)
	if category == &"":
		return
	_record_outcome(category, action_id, target, success)


func _on_year_passed(_y: int) -> void:
	var now: int = -GameClock.year
	for p in patterns.values():
		if p.unverified:
			continue
		if now - p.last_verified_year >= MemoirPattern.STALE_YEARS:
			p.unverified = true
			pattern_flagged_unverified.emit(p.id)


# --- Recording ---------------------------------------------------------------

func _record_outcome(category: StringName, action_id: StringName, target: Actor, success: bool) -> void:
	var profile: Dictionary = _profile_for_actor(target)
	var now: int = -GameClock.year
	# Look for a close-enough pattern to extend; otherwise create fresh.
	var culture: StringName = _culture_for_actor(target)
	var existing: MemoirPattern = _closest_pattern(action_id, profile, 0.85, culture)
	if existing == null:
		# Only successful first-encounters seed the library — failed
		# one-offs are rarely informative.
		if not success:
			return
		var p: MemoirPattern = MemoirPattern.new()
		p.id = StringName("pattern_%s_%s_%d" % [String(category), String(action_id), Time.get_ticks_msec()])
		p.category = category
		p.action_id = action_id
		p.culture_tag = _culture_for_actor(target)
		p.profile = profile.duplicate(true)
		p.headline = _headline_for(category, target)
		p.samples = 1
		p.successes = 1
		p.first_recorded_year = now
		p.last_verified_year = now
		patterns[p.id] = p
		pattern_added.emit(p.id)
		return

	existing.samples += 1
	if success:
		existing.successes += 1
	existing.last_verified_year = now
	existing.unverified = false
	pattern_refreshed.emit(existing.id, success)


func _closest_pattern(action_id: StringName, profile: Dictionary, threshold: float, culture: StringName = &"") -> MemoirPattern:
	var best: MemoirPattern = null
	var best_score: float = 0.0
	for p in patterns.values():
		if p.action_id != action_id:
			continue
		if culture != &"" and p.culture_tag != &"" and p.culture_tag != culture:
			continue
		var s: float = _similarity(profile, p.profile)
		if s >= threshold and s > best_score:
			best = p
			best_score = s
	return best


# --- Profile / similarity ----------------------------------------------------

func _profile_for_actor(a: Actor) -> Dictionary:
	var profile: Dictionary = {
		&"role":            Actor.Role.keys()[a.role],
		&"kingdom_id":      a.kingdom_id,
		&"greed_band":      _band(a.greed),
		&"loyalty_band":    _band(a.loyalty),
		&"paranoia_band":   _band(a.paranoia),
		&"ambition_band":   _band(a.ambition),
		&"piety_band":      _band(a.piety),
		&"competence_band": _band(a.intellect),
	}
	return profile


func _culture_for_actor(a: Actor) -> StringName:
	if a == null or a.kingdom_id == "":
		return &""
	return Languages.native_of(a.kingdom_id)


func _band(v: int) -> StringName:
	if v >= 67:
		return TRAIT_BAND_HIGH
	if v >= 34:
		return TRAIT_BAND_MID
	return TRAIT_BAND_LOW


func _similarity(a: Dictionary, b: Dictionary) -> float:
	var total: float = 0.0
	var got: float = 0.0
	for key in b.keys():
		var w: float = _weight_for(key)
		total += w
		if not a.has(key):
			continue
		if String(a[key]) == String(b[key]):
			got += w
	if total <= 0.0:
		return 0.0
	return got / total


func _weight_for(key: StringName) -> float:
	match String(key):
		"role":       return WEIGHT_ROLE
		"kingdom_id": return WEIGHT_KINGDOM
		_:            return WEIGHT_TRAIT


# --- Category and copy -------------------------------------------------------

func _category_for(action_id: StringName) -> StringName:
	match String(action_id):
		"cultivate":           return &"host_cultivate"
		"bribe":               return &"bribe_target"
		"plant_rumour":        return &"ruler_rumour"
		"seed_idea":           return &"institution_seed"
		"recruit_asset":       return &"asset_recruit"
		_:                     return &""


func _headline_for(category: StringName, target: Actor) -> String:
	var role: String = Actor.Role.keys()[target.role].capitalize()
	var bands: Array[String] = _dominant_bands(target)
	var bands_phrase: String = "; ".join(bands) if not bands.is_empty() else "mixed profile"
	match String(category):
		"host_cultivate":   return "Cultivating %s with %s" % [role.to_lower(), bands_phrase]
		"bribe_target":     return "Paying the %s of the %s kind" % [role.to_lower(), bands_phrase]
		"ruler_rumour":     return "Seeding rumours into %s courts" % role.to_lower()
		"institution_seed": return "Seeding ideas through the %s" % role.to_lower()
		"asset_recruit":    return "Recruiting %s assets (%s)" % [role.to_lower(), bands_phrase]
		_:                  return "Approach to %s" % role.to_lower()


func _dominant_bands(a: Actor) -> Array[String]:
	var out: Array[String] = []
	if a.greed    >= 67: out.append("greedy")
	if a.paranoia >= 67: out.append("paranoid")
	if a.ambition >= 67: out.append("ambitious")
	if a.piety    >= 67: out.append("pious")
	if a.loyalty  <= 33: out.append("disloyal")
	if a.loyalty  >= 67: out.append("loyalist")
	return out


# --- Save / load -------------------------------------------------------------

func snapshot() -> Dictionary:
	var arr: Array = []
	for p in patterns.values():
		arr.append(p.to_dict())
	return {"patterns": arr}


func restore(d: Dictionary) -> void:
	patterns.clear()
	for entry in d.get("patterns", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var p: MemoirPattern = MemoirPattern.from_dict(entry)
		if p.id == &"":
			continue
		patterns[p.id] = p
