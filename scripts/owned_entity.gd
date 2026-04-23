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
	BANKING_HOUSE,     # wraps a BankingHouse resource into the entity graph
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


# --- Longevity (§20.4) -------------------------------------------------------
#
# Accumulated standing: decades of archives, contacts, contracts.
# Rises one point per year tenure up to INSTITUTIONAL_MEMORY_CAP.
# Feeds a small but real intelligence/visibility bonus in the
# registry that newcomers simply cannot match.
@export_range(0, 200) var institutional_memory: int = 0

# Beneficial control is "live" when a proxy answers to the chain of
# loyal actors the registry understands. Major political shocks —
# the ruler of the home kingdom falls, the province flips hands —
# knock this off, at which point the entity survives but yields
# nothing to the player until control is re-established through a
# new proxy arrangement.
@export var control_disrupted: bool = false
@export var control_disrupted_reason: StringName = &""
@export var control_disrupted_year: int = 0


# --- §20 beneficial-ownership paperwork -------------------------------------
#
# The official record does not name the player and never will. What
# investigators see when they open the archive is the `nominal_owner`
# — a respectable figurehead whose paperwork the proxy forged — and
# if they lean harder, `proxy_chain`: the sequence of names the money
# actually routes through before anyone connected to the player sees
# silver. Each extra hop in the chain dampens the visibility hit
# when the entity is scrutinised.
#
# `papers_founding_year` tracks when the current paperwork was
# notarised. Regimes changing, wars, dynastic successions — any of
# these plausibly invalidate old charters. When the gap between
# papers_founding_year and current year grows past PAPERS_STALE_YEARS
# the entity flags "papers thin" and an investigator will land much
# harder if they hit.
@export var nominal_owner_name: String = ""
@export var nominal_owner_role: String = ""
@export var proxy_chain: Array[StringName] = []
@export var papers_founding_year: int = 0

## When `kind == BANKING_HOUSE` this is the StringName id of the
## underlying `BankingHouse` resource owned by `Finance`. Empty for
## all other kinds. The two records are paired by
## `EntityRegistry.found_banking_house` and never diverge.
@export var banking_house_id: StringName = &""


const PAPERS_STALE_YEARS: int = 120


const CORRUPTION_LEAK_THRESHOLD: int = 40
const CORRUPTION_LOSS_THRESHOLD: int = 80

const INSTITUTIONAL_MEMORY_CAP: int = 200

## Tenure (years) at which "accumulated archives" starts to pay a
## bonus. Everything under this is still a young house.
const MEMORY_BONUS_FLOOR: int = 40


func is_active() -> bool:
	return not dissolved and not compromised


func control_live() -> bool:
	return is_active() and not control_disrupted


func memory_phrase() -> String:
	if institutional_memory >= 150:
		return "six centuries of paper speak through them"
	if institutional_memory >= 100:
		return "an archive the continent has forgotten is still theirs"
	if institutional_memory >= MEMORY_BONUS_FLOOR:
		return "long-enough memory to name their own grandfathers' creditors"
	if institutional_memory >= 15:
		return "a thickening stack of ledgers"
	return "too young to have records worth the name"


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


## §20 — headline that would appear if an investigator pulled the
## entity's filings today. "Mnesarkhos son of Euphronos, shipper" —
## never the player's name.
func papers_headline() -> String:
	if nominal_owner_name == "":
		return "no name on the charter that anyone can still read"
	if nominal_owner_role == "":
		return nominal_owner_name
	return "%s, %s" % [nominal_owner_name, nominal_owner_role]


func papers_depth() -> int:
	return proxy_chain.size()


func papers_are_stale(now_year: int) -> bool:
	if papers_founding_year == 0:
		return false
	return (now_year - papers_founding_year) > PAPERS_STALE_YEARS


func papers_phrase(now_year: int) -> String:
	var depth: int = papers_depth()
	var depth_bit: String = ""
	match depth:
		0:
			depth_bit = "one thin veil"
		1:
			depth_bit = "two names between us and the ink"
		2:
			depth_bit = "three hands between us and the ink"
		_:
			depth_bit = "%d hands between us and the ink" % (depth + 1)
	var stale_bit: String = ", papers thin with age" if papers_are_stale(now_year) else ""
	return "%s — %s%s" % [papers_headline(), depth_bit, stale_bit]


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
		Kind.BANKING_HOUSE:   return "Banking house"
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
	e.institutional_memory    = clampi(int(d.get("institutional_memory", 0)), 0, INSTITUTIONAL_MEMORY_CAP)
	e.control_disrupted       = bool(d.get("control_disrupted", false))
	e.control_disrupted_reason = StringName(String(d.get("control_disrupted_reason", "")))
	e.control_disrupted_year  = int(d.get("control_disrupted_year", 0))
	e.nominal_owner_name    = String(d.get("nominal_owner_name", ""))
	e.nominal_owner_role    = String(d.get("nominal_owner_role", ""))
	e.proxy_chain = []
	for v in d.get("proxy_chain", []):
		e.proxy_chain.append(StringName(String(v)))
	e.papers_founding_year  = int(d.get("papers_founding_year", 0))
	e.banking_house_id      = StringName(String(d.get("banking_house_id", "")))
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
		"institutional_memory":     institutional_memory,
		"control_disrupted":        control_disrupted,
		"control_disrupted_reason": String(control_disrupted_reason),
		"control_disrupted_year":   control_disrupted_year,
		"nominal_owner_name":       nominal_owner_name,
		"nominal_owner_role":       nominal_owner_role,
		"proxy_chain":              _proxy_chain_as_strings(),
		"papers_founding_year":     papers_founding_year,
		"banking_house_id":         String(banking_house_id),
	}


func _proxy_chain_as_strings() -> Array:
	var out: Array = []
	for v in proxy_chain:
		out.append(String(v))
	return out


static func _kind_from_string(s: String) -> Kind:
	match s.to_upper():
		"TRADING_COMPANY": return Kind.TRADING_COMPANY
		"ACADEMY":         return Kind.ACADEMY
		"MONASTERY":       return Kind.MONASTERY
		"GUILD":           return Kind.GUILD
		"ESTATE":          return Kind.ESTATE
		"BANKING_HOUSE":   return Kind.BANKING_HOUSE
		_:                  return Kind.TRADING_COMPANY
