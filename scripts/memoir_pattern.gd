class_name MemoirPattern
extends Resource
## A single entry in the player's Memoirs — a profile plus an approach
## that has been proven to work (§13.1).
##
## Profile is a dictionary of tagged conditions the registry builds
## when recording an outcome. We keep the shape loose on purpose:
## different categories of pattern care about different variables,
## and over the course of play new variables get added without
## breaking older entries.
##
## Usage lifecycle:
##   * player completes an action manually against a target
##   * Memoirs records a Pattern (or extends an existing one)
##   * later, when the player frames a similar action on a similar
##     target, Memoirs.match_for(...) offers this Pattern back as
##     an automation hint
##   * if too long passes without the pattern being refreshed
##     against fresh intelligence, Memoirs flags it unverified —
##     running it from stale notes risks a misfire (§13.5)

@export var id: StringName = &""

## Grouping. "social_approach", "host_cultivate", "institution_seed",
## "ruler_rumour", etc. Memoirs uses the category to narrow matches.
@export var category: StringName = &""

## Human-readable one-liner used by the Memoirs panel header.
@export var headline: String = ""

## The action id that worked. Future richer patterns will carry a
## sequence; for now a single dispatched action is enough to hang
## everything else on.
@export var action_id: StringName = &""

## §23 cultural tag. Derived from the target's native language at
## record time. A Latin-merchant pattern will not apply to an
## Arabic merchant even if their trait bands line up — Memoirs
## matching filters on this first.
@export var culture_tag: StringName = &""

## The distilled profile. Keys are StringName tags, values are
## StringName or int. Typical keys for a social pattern:
##   "role", "kingdom_id", "greed_band", "loyalty_band",
##   "paranoia_band", "ambition_band", "piety_band",
##   "competence_band"
## Bands are "low" / "mid" / "high". Role is the Actor.Role label.
@export var profile: Dictionary = {}

## Times this pattern has been fired. `successes` includes both
## manual refreshes and automated runs.
@export var samples: int = 0
@export var successes: int = 0

## Game-year (negative for BCE) the pattern was first recorded and
## last refreshed against live intelligence. Used by the staleness
## check.
@export var first_recorded_year: int = 0
@export var last_verified_year: int = 0

## When true the library entry has been flagged as unverified by
## the staleness tick (§13.5). Purely advisory — the player can
## still fire it.
@export var unverified: bool = false


const STALE_YEARS: int = 25   # library ages hard; a quarter-century without use is a warning


func success_ratio() -> float:
	if samples <= 0:
		return 0.0
	return float(successes) / float(samples)


func confidence_phrase() -> String:
	var r: float = success_ratio()
	if samples < 2:
		return "a single datum"
	if r >= 0.8:
		return "reliable across many"
	if r >= 0.5:
		return "sometimes"
	return "more often fails than works"


func stale_phrase() -> String:
	return "notes going brittle" if unverified else "notes fresh"


# --- Serialisation -----------------------------------------------------------

static func from_dict(d: Dictionary) -> MemoirPattern:
	var p: MemoirPattern = MemoirPattern.new()
	p.id       = StringName(String(d.get("id", "")))
	p.category = StringName(String(d.get("category", "")))
	p.headline = String(d.get("headline", ""))
	p.action_id = StringName(String(d.get("action_id", "")))
	p.culture_tag = StringName(String(d.get("culture_tag", "")))
	var raw: Dictionary = d.get("profile", {})
	p.profile = {}
	for k in raw.keys():
		p.profile[StringName(String(k))] = raw[k]
	p.samples            = int(d.get("samples", 0))
	p.successes          = int(d.get("successes", 0))
	p.first_recorded_year = int(d.get("first_recorded_year", 0))
	p.last_verified_year = int(d.get("last_verified_year", 0))
	p.unverified         = bool(d.get("unverified", false))
	return p


func to_dict() -> Dictionary:
	var out_profile: Dictionary = {}
	for k in profile.keys():
		out_profile[String(k)] = profile[k]
	return {
		"id":                   String(id),
		"category":             String(category),
		"headline":             headline,
		"action_id":            String(action_id),
		"culture_tag":          String(culture_tag),
		"profile":              out_profile,
		"samples":              samples,
		"successes":            successes,
		"first_recorded_year":  first_recorded_year,
		"last_verified_year":   last_verified_year,
		"unverified":           unverified,
	}
