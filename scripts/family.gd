class_name Family
extends Resource
## §21 — a single dynasty the player's network tracks across
## generations. Not every actor has one; families only exist where
## the player (or the world) has cause to watch the line, typically
## banking houses, trusted courtiers, or merchant-gentry that serve
## the shadow continuously.
##
## A family is a *persistent organisational node*: the member actors
## come and go, the family culture accumulates. Trait weights on
## newly spawned members read from the culture here, which is how
## loyalty or resentment compounds across generations.

enum Domain {
	GENERIC,
	BANKING,
	MERCHANT,
	SCHOLARLY,
	MILITARY,
	RELIGIOUS,
	COURT,
}

@export var id: StringName = &""
@export var family_name: String = ""
@export var domain: Domain = Domain.GENERIC
@export var home_kingdom: String = ""
@export var founded_year: int = 0

## All actor ids the family has ever carried, living or dead, eldest
## first. The current head is `head_id`; heirs and other living
## members follow.
@export var members: Array = []     # Array[StringName]
@export var head_id: StringName = &""

## Cultural inheritance toward the player. -100 (resentful, actively
## hostile succession) .. +100 (deeply loyal, silent-patron lore
## baked into the children's upbringing). Shifts on crisis actions
## and the head's own relationship at death.
@export_range(-100, 100) var loyalty_culture: int = 0

## Stat ceiling pressure passed to the next generation. Rises with
## investment (education, training), falls with neglect. Feeds into
## weighted trait spawn for new children.
@export_range(-40, 40) var competence_bias: int = 0
@export_range(-40, 40) var resentment: int = 0
@export_range(-40, 40) var fatigue: int = 0

## Running count of generations that have headed the family. 1 at
## founding. Incremented each succession. Displayed in dossier to
## cue "three generations served" lore without being overly precise.
@export var generations_served: int = 1

## Soft decline score (0..100). Rises monthly when resentment/fatigue
## are high and loyalty_culture is low. A family crossing 70 is at
## risk of catastrophic decline — public scandal, defection, or an
## heir who simply refuses to serve.
@export_range(0, 100) var decline_score: int = 0

@export var dissolved: bool = false
@export var dissolved_reason: String = ""
@export var dissolved_year: int = 0

## When true the family is on an "underdog" development track: their
## junior members gain faster trait growth whenever the player runs
## an action inside the family's domain and it succeeds. Set by the
## registry at founding when the line is chosen from outside the
## established court / banking lineages, or flipped on later via
## `Dynasties.mark_underdog`. Cultivated underdogs catch up to the
## incumbents across a generation or two.
@export var underdog_focus: bool = false


# --- Open need (§21.3) -------------------------------------------------------
#
# At most one open need at a time. A family with an open need and
# no response before the deadline counts as "ignored" and its
# culture takes the §21.3 penalty. The inbox letter that announced
# the need is referenced by `need_letter_id` so the player can
# reply to it from the dossier.
@export var need_kind: StringName = &""          # "legal", "blackmail", "business", "succession", "status", "drift"
@export var need_headline: String = ""
@export var need_blurb: String = ""
@export var need_deadline_abs_day: int = 0
@export var need_letter_id: StringName = &""


func is_active() -> bool:
	return not dissolved


func has_open_need() -> bool:
	return need_kind != &""


func need_label() -> String:
	match String(need_kind):
		"legal":      return "a member in legal or political danger"
		"blackmail":  return "an external threat against them"
		"business":   return "a business crisis they cannot ride out alone"
		"succession": return "a succession dispute inside the family"
		"status":     return "a quiet request for status advancement"
		"drift":      return "ideological drift in the next generation"
		_:            return "a matter requiring the patron's attention"


## The trait most closely tied to the family's domain. Used by the
## underdog-development path in `FamilyRegistry`. All strings match
## Actor field names for cheap `get`/`set` in the registry.
func primary_trait_for_domain() -> String:
	match domain:
		Domain.BANKING:   return "greed"
		Domain.MERCHANT:  return "ambition"
		Domain.SCHOLARLY: return "piety"
		Domain.MILITARY:  return "ruthlessness"
		Domain.RELIGIOUS: return "piety"
		Domain.COURT:     return "loyalty"
	return "ambition"


func domain_label() -> String:
	match domain:
		Domain.BANKING:   return "banking"
		Domain.MERCHANT:  return "merchant"
		Domain.SCHOLARLY: return "scholarly"
		Domain.MILITARY:  return "military"
		Domain.RELIGIOUS: return "religious"
		Domain.COURT:     return "court"
		_:                return "household"


func culture_phrase() -> String:
	if loyalty_culture >= 70:
		return "a silent-patron cult carried in the blood"
	if loyalty_culture >= 40:
		return "deep inherited loyalty to an unnamed benefactor"
	if loyalty_culture >= 15:
		return "a quiet sense of obligation to you"
	if loyalty_culture > -15:
		return "no settled feeling toward you either way"
	if loyalty_culture > -40:
		return "unease and a growing coldness in the children"
	return "resentment taught at the dinner table"


func generation_phrase() -> String:
	if generations_served <= 1:
		return "the first generation to carry the name in your service"
	if generations_served == 2:
		return "the second generation in your service"
	if generations_served == 3:
		return "the third generation in your service"
	return "the %dth generation in your service" % generations_served


func from_dict_members(src: Array) -> void:
	members.clear()
	for v in src:
		members.append(StringName(String(v)))


static func from_dict(d: Dictionary) -> Family:
	var f: Family = Family.new()
	f.id               = StringName(String(d.get("id", "")))
	f.family_name      = String(d.get("family_name", ""))
	f.domain           = int(d.get("domain", Domain.GENERIC)) as Domain
	f.home_kingdom     = String(d.get("home_kingdom", ""))
	f.founded_year     = int(d.get("founded_year", 0))
	f.head_id          = StringName(String(d.get("head_id", "")))
	f.loyalty_culture  = clampi(int(d.get("loyalty_culture", 0)), -100, 100)
	f.competence_bias  = clampi(int(d.get("competence_bias", 0)), -40, 40)
	f.resentment       = clampi(int(d.get("resentment", 0)), -40, 40)
	f.fatigue          = clampi(int(d.get("fatigue", 0)), -40, 40)
	f.generations_served = maxi(1, int(d.get("generations_served", 1)))
	f.decline_score    = clampi(int(d.get("decline_score", 0)), 0, 100)
	f.dissolved        = bool(d.get("dissolved", false))
	f.dissolved_reason = String(d.get("dissolved_reason", ""))
	f.dissolved_year   = int(d.get("dissolved_year", 0))
	f.underdog_focus   = bool(d.get("underdog_focus", false))
	f.from_dict_members(d.get("members", []))
	f.need_kind            = StringName(String(d.get("need_kind", "")))
	f.need_headline        = String(d.get("need_headline", ""))
	f.need_blurb           = String(d.get("need_blurb", ""))
	f.need_deadline_abs_day = int(d.get("need_deadline_abs_day", 0))
	f.need_letter_id       = StringName(String(d.get("need_letter_id", "")))
	return f


func to_dict() -> Dictionary:
	var ms: Array = []
	for m in members:
		ms.append(String(m))
	return {
		"id": String(id),
		"family_name": family_name,
		"domain": int(domain),
		"home_kingdom": home_kingdom,
		"founded_year": founded_year,
		"head_id": String(head_id),
		"loyalty_culture": loyalty_culture,
		"competence_bias": competence_bias,
		"resentment": resentment,
		"fatigue": fatigue,
		"generations_served": generations_served,
		"decline_score": decline_score,
		"dissolved": dissolved,
		"dissolved_reason": dissolved_reason,
		"dissolved_year": dissolved_year,
		"underdog_focus": underdog_focus,
		"members": ms,
		"need_kind":             String(need_kind),
		"need_headline":         need_headline,
		"need_blurb":            need_blurb,
		"need_deadline_abs_day": need_deadline_abs_day,
		"need_letter_id":        String(need_letter_id),
	}
