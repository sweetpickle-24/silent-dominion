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
	return a


func to_dict() -> Dictionary:
	var traits: Dictionary = {}
	for k in TRAIT_KEYS:
		traits[String(k)] = get_trait(k)
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
