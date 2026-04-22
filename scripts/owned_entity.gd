class_name OwnedEntity
extends Resource
## A durable institution under the player's beneficial control (§20).
##
## Hosts and coordinators die. Treasuries empty. Wars uproot operatives.
## An owned entity persists. The player never appears on its records;
## what they hold is direction through a chain of proxies. The proxy
## actor recorded here is the topmost loyalist whose own loyalties
## chain back through the organisation to the player.
##
## Banking houses (§16, BankingHouse resource) predate this class and
## stay separate — their mechanics around capacity / discretion /
## curiosity are fiddly enough to deserve their own model. Everything
## else lives here.

enum Kind {
	TRADING_COMPANY,   # ports + commercial cover
	ACADEMY,           # ideological infrastructure + scholar pipeline
	MONASTERY,         # permanent intelligence node + correspondence
	GUILD,             # urban intelligence + craft control
	ESTATE,            # rural revenue + provincial access
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: Kind = Kind.TRADING_COMPANY

## Where the entity is rooted. Province is its physical home;
## kingdom is denormalised for fast lookups.
@export var home_province: String = ""
@export var home_kingdom: String = ""

## Year first founded (negative for BCE). Together with current year
## this is the entity's tenure — long-running houses earn small
## bonuses that newcomers do not (§20.4 institutional memory).
@export var founded_year: int = 0

## Monthly silver yielded to Purse, before corruption skim.
@export var monthly_yield_silver: int = 0

## Monthly visibility bump applied to home_kingdom (and to anywhere
## in `reach` for trading companies). Caps at PlayerPicture's own
## ceiling — set conservatively here, the manager handles the cap.
@export var monthly_visibility_bump: int = 0

## Trading companies have explicit reach across other kingdoms;
## other kinds are home-only and leave this empty.
@export var reach: Array[String] = []

## Topmost loyalist on the official record. Their loyalty (and life)
## determines whether the player still effectively controls the
## entity. Empty during transitions; the registry attempts to
## reattach to a fresh proxy on actor death.
@export var proxy_actor_id: StringName = &""

## 0..100. Rises slowly with age; faster when a rival's hand is on
## the proxy, or when the entity is in an unstable kingdom. Above
## CORRUPTION_LEAK_THRESHOLD the entity quietly skims a percentage
## of its monthly yield; above CORRUPTION_LOSS_THRESHOLD the
## player loses control entirely.
@export_range(0, 100) var corruption: int = 0

## A rival society has acquired beneficial control. The entity still
## yields silver but does so to the rival's purse and leaks
## intelligence in the player's network. Set by RivalRegistry's
## counter-ops; not produced spontaneously.
@export var compromised: bool = false

## Terminal state — confiscated, dissolved, war-destroyed. Kept in
## the registry as a tombstone for the ledger.
@export var dissolved: bool = false
@export var dissolved_reason: StringName = &""


const CORRUPTION_LEAK_THRESHOLD: int = 40
const CORRUPTION_LOSS_THRESHOLD: int = 80


func is_active() -> bool:
	return not dissolved and not compromised


func tenure_years(now_year: int) -> int:
	# now_year is in negative-BCE convention to match founded_year.
	return max(0, now_year - founded_year)


func corruption_band() -> StringName:
	if dissolved:                                return &"closed"
	if compromised:                              return &"turned"
	if corruption >= CORRUPTION_LOSS_THRESHOLD:  return &"lost"
	if corruption >= CORRUPTION_LEAK_THRESHOLD:  return &"leaking"
	if corruption >= 20:                          return &"frayed"
	return &"sound"


func corruption_phrase() -> String:
	match corruption_band():
		&"closed":  return "shuttered"
		&"turned":  return "in another's hand"
		&"lost":    return "no longer answering us"
		&"leaking": return "skimming, but still ours"
		&"frayed":  return "sloppy at the edges"
		&"sound":   return "running clean"
	return "unknown"


func kind_label() -> String:
	match kind:
		Kind.TRADING_COMPANY: return "Trading company"
		Kind.ACADEMY:         return "Academy"
		Kind.MONASTERY:       return "Monastery"
		Kind.GUILD:           return "Guild"
		Kind.ESTATE:          return "Estate"
	return "Institution"


# --- Serialisation -----------------------------------------------------------

static func from_dict(d: Dictionary) -> OwnedEntity:
	var e: OwnedEntity = OwnedEntity.new()
	e.id                     = StringName(String(d.get("id", "")))
	e.display_name           = String(d.get("display_name", ""))
	e.kind                   = _kind_from_string(String(d.get("kind", "TRADING_COMPANY")))
	e.home_province          = String(d.get("home_province", ""))
	e.home_kingdom           = String(d.get("home_kingdom", ""))
	e.founded_year           = int(d.get("founded_year", 0))
	e.monthly_yield_silver   = int(d.get("monthly_yield_silver", 0))
	e.monthly_visibility_bump = int(d.get("monthly_visibility_bump", 0))
	e.reach = []
	for v in d.get("reach", []):
		e.reach.append(String(v))
	e.proxy_actor_id   = StringName(String(d.get("proxy_actor_id", "")))
	e.corruption       = clampi(int(d.get("corruption", 0)), 0, 100)
	e.compromised      = bool(d.get("compromised", false))
	e.dissolved        = bool(d.get("dissolved", false))
	e.dissolved_reason = StringName(String(d.get("dissolved_reason", "")))
	return e


func to_dict() -> Dictionary:
	return {
		"id":                       String(id),
		"display_name":             display_name,
		"kind":                     Kind.keys()[kind],
		"home_province":            home_province,
		"home_kingdom":             home_kingdom,
		"founded_year":             founded_year,
		"monthly_yield_silver":     monthly_yield_silver,
		"monthly_visibility_bump":  monthly_visibility_bump,
		"reach":                    reach.duplicate(),
		"proxy_actor_id":           String(proxy_actor_id),
		"corruption":               corruption,
		"compromised":              compromised,
		"dissolved":                dissolved,
		"dissolved_reason":         String(dissolved_reason),
	}


static func _kind_from_string(s: String) -> Kind:
	match s.to_upper():
		"TRADING_COMPANY": return Kind.TRADING_COMPANY
		"ACADEMY":         return Kind.ACADEMY
		"MONASTERY":       return Kind.MONASTERY
		"GUILD":           return Kind.GUILD
		"ESTATE":          return Kind.ESTATE
		_:                  return Kind.TRADING_COMPANY
