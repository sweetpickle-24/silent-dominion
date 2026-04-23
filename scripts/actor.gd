class_name Actor
extends Resource
## A single person in the world.
##
## Actors are the universal data model for anyone who can be manipulated,
## bribed, cultivated, assassinated, or otherwise acted upon — historical
## figures, procedurally generated characters, and members of the player's
## own organisation all share this class.
##
## Per §24: every character is described by ten canonical traits on a
## 0-100 scale. 50 = average for their station, <30 = notable deficiency,
## >70 = notable strength/extreme.

enum Role {
	RULER,         # king, tyrant, consul, pharaoh
	HEIR,          # designated successor
	GENERAL,       # military commander
	PRIEST,        # religious authority
	MERCHANT,      # trade magnate
	ADVISOR,       # councillor / senator
	PHILOSOPHER,   # scholar / theorist
	AGENT,         # your own organisation (future)
	COMMONER,      # generic NPC
}

@export var id: StringName = &""
@export var given_name: String = ""
@export var epithet: String = ""             # e.g. "the Just", "son of Hystaspes"
@export var birth_year: int = 0              # negative for BCE
@export var death_year: int = 0              # 0 = still alive
@export var role: Role = Role.COMMONER
@export var province_id: String = ""         # where they live
@export var kingdom_id: String = ""          # whose kingdom they serve

# --- Canonical §24 traits (0-100) ---------------------------------------------

@export_range(0, 100) var ambition: int = 50
@export_range(0, 100) var paranoia: int = 50
@export_range(0, 100) var loyalty: int = 50
@export_range(0, 100) var piety: int = 50
@export_range(0, 100) var intellect: int = 50
@export_range(0, 100) var greed: int = 50
@export_range(0, 100) var ruthlessness: int = 50
@export_range(0, 100) var curiosity: int = 50
@export_range(0, 100) var resilience: int = 50
@export_range(0, 100) var charisma: int = 50

# --- Relationship (not a trait; §5 host cultivation) -------------------------
#
# -100 .. +100. 0 = they have no personal stance on you; positive = growing
# warmth and eventually loyalty; negative = wariness up to open hostility.
# Moves when the player interacts with them (cultivate, bribe, seed_rumour,
# ...), mutually decays toward zero when ignored.
@export_range(-100, 100) var relationship: int = 0


# --- Language profile (§23) --------------------------------------------------
#
# A dictionary of language_id (StringName) -> competence level 0..3.
# Most actors speak exactly one language fluently — whatever is native
# to the kingdom they were generated in. Cosmopolitan provinces and
# scholarly roles spread this wider. Competence levels follow §23.1:
#   0 = none, 1 = basic, 2 = functional, 3 = fluent.
# Absent keys mean "none"; there's no ceremony to speaking nothing.
@export var languages: Dictionary = {}


# --- Family / dynasty (§21) --------------------------------------------------
#
# Actors may belong to a named family tracked across generations.
# `family_id` is empty for actors not part of a tracked dynasty.
# Parentage is a soft reference: `parent_id` may be empty even when a
# family is set (e.g. the founding generation). Children are populated
# only when a relation is authored — we don't invent parents for world
# seed actors retroactively.
@export var family_id: StringName = &""
@export var parent_id: StringName = &""
@export var children: Array = []


# --- Long-run compression (§6.5) --------------------------------------------
#
# Actors who have been dead for long enough (see
# ActorRegistry.COMPRESS_AFTER_YEARS) are flagged here. Compressed
# actors stay in the registry so Memoirs, family trees, and letters
# can still reference them by id, but they are **skipped by the
# iteration helpers**: WorldAI rolls, month/year ticks, ambient
# simulation. The registry only has to pay for their existence once
# they die and the compression window closes.
@export var compressed: bool = false


func is_compressed() -> bool:
	return compressed


const LANG_NONE: int       = 0
const LANG_BASIC: int      = 1
const LANG_FUNCTIONAL: int = 2
const LANG_FLUENT: int     = 3


func speaks(language_id: StringName, min_level: int = LANG_FUNCTIONAL) -> bool:
	return int(languages.get(language_id, 0)) >= min_level


func language_level(language_id: StringName) -> int:
	return int(languages.get(language_id, 0))


func known_languages() -> Array:
	var out: Array = []
	for k in languages.keys():
		if int(languages[k]) >= LANG_BASIC:
			out.append(k)
	return out

# --- Host memory (§5 fragility) ----------------------------------------------
#
# Once an actor has been cultivated past HOST_THRESHOLD they remember
# it — even after the relationship has cooled. That memory is what makes
# a former host capable of betraying the player later (WorldAI monthly
# defection roll). `betrayed` latches once they do, so they don't keep
# denouncing the same immortal every month forever.
@export var ever_host: bool = false
@export var betrayed: bool = false


# --- Host status (§5) --------------------------------------------------------
#
# An actor becomes a "host" once they're loyal enough to act on your
# behalf. Rulers are explicitly excluded — you don't run a ruler, you
# influence them. Status is derived from relationship, so it rises and
# falls with cultivation/decay automatically.
const HOST_THRESHOLD: int = 60


func is_host() -> bool:
	if not is_alive():
		return false
	if role == Role.RULER:
		return false
	return relationship >= HOST_THRESHOLD


# --- Lifecycle ---------------------------------------------------------------

func is_alive() -> bool:
	return death_year == 0


func display_name() -> String:
	if epithet.is_empty():
		return given_name
	return "%s, %s" % [given_name, epithet]


func age_in(current_year: int) -> int:
	# Input uses negative years for BCE (matches GameClock).
	if birth_year == 0:
		return 0
	if death_year != 0 and current_year >= death_year:
		return death_year - birth_year
	return current_year - birth_year


# --- Trait access helpers ----------------------------------------------------

const TRAIT_KEYS: Array[StringName] = [
	&"ambition", &"paranoia", &"loyalty", &"piety", &"intellect",
	&"greed", &"ruthlessness", &"curiosity", &"resilience", &"charisma",
]


func get_trait(key: StringName) -> int:
	return int(get(key))


func qualitative(value: int) -> String:
	if value < 30:
		return "low"
	if value > 70:
		return "high"
	return "average"


# --- Serialisation ------------------------------------------------------------

static func from_dict(d: Dictionary) -> Actor:
	var a: Actor = Actor.new()
	a.id          = StringName(String(d.get("id", "")))
	a.given_name  = String(d.get("given_name", ""))
	a.epithet     = String(d.get("epithet", ""))
	a.birth_year  = int(d.get("birth_year", 0))
	a.death_year  = int(d.get("death_year", 0))
	a.role        = _role_from_string(String(d.get("role", "COMMONER")))
	a.province_id = String(d.get("province_id", ""))
	a.kingdom_id  = String(d.get("kingdom_id", ""))

	var traits: Dictionary = d.get("traits", {})
	for k in TRAIT_KEYS:
		if traits.has(String(k)):
			a.set(k, clampi(int(traits[String(k)]), 0, 100))

	a.relationship = clampi(int(d.get("relationship", 0)), -100, 100)
	a.ever_host    = bool(d.get("ever_host", false))
	a.betrayed     = bool(d.get("betrayed", false))
	a.languages = {}
	for lk in d.get("languages", {}).keys():
		a.languages[StringName(String(lk))] = clampi(
			int(d["languages"][lk]), 0, Actor.LANG_FLUENT
		)
	a.family_id = StringName(String(d.get("family_id", "")))
	a.parent_id = StringName(String(d.get("parent_id", "")))
	a.children = []
	for cid in d.get("children", []):
		a.children.append(StringName(String(cid)))
	a.compressed = bool(d.get("compressed", false))
	return a


func to_dict() -> Dictionary:
	var traits: Dictionary = {}
	for k in TRAIT_KEYS:
		traits[String(k)] = get_trait(k)
	var lang_out: Dictionary = {}
	for lk in languages.keys():
		lang_out[String(lk)] = int(languages[lk])
	var kids_out: Array = []
	for cid in children:
		kids_out.append(String(cid))
	return {
		"id": String(id),
		"given_name": given_name,
		"epithet": epithet,
		"birth_year": birth_year,
		"death_year": death_year,
		"role": Role.keys()[role],
		"province_id": province_id,
		"kingdom_id": kingdom_id,
		"traits": traits,
		"relationship": relationship,
		"ever_host": ever_host,
		"betrayed": betrayed,
		"languages": lang_out,
		"family_id": String(family_id),
		"parent_id": String(parent_id),
		"children": kids_out,
		"compressed": compressed,
	}


static func _role_from_string(s: String) -> Role:
	match s.to_upper():
		"RULER":       return Role.RULER
		"HEIR":        return Role.HEIR
		"GENERAL":     return Role.GENERAL
		"PRIEST":      return Role.PRIEST
		"MERCHANT":    return Role.MERCHANT
		"ADVISOR":     return Role.ADVISOR
		"PHILOSOPHER": return Role.PHILOSOPHER
		"AGENT":       return Role.AGENT
		_:             return Role.COMMONER


func role_name() -> String:
	return Role.keys()[role]
