class_name OrgMember
extends Resource
## A single member of the player's shadow organisation (§14).
##
## The player does not act directly in the world — they route work
## through a four-layer machine: Lieutenants manage regions, Coordinators
## run cells in a city/kingdom, Operatives do the ground work and
## cultivate Assets. This class is the shared data shape for the first
## three layers. Assets are handled as bare Actors with a relationship
## score; they never become OrgMembers because they don't know they're
## part of anything.
##
## Most members begin life as promoted Actors. `source_actor_id` is the
## pointer back to their `Actors` entry so we can read traits (loyalty,
## greed, charisma, intellect) whenever we need them. Abstract operatives
## spawned by a Coordinator don't have a source actor; their names and
## stats are generated directly on the OrgMember.

enum Layer {
	LIEUTENANT,   # 3-6 of these, each covers a region or domain
	COORDINATOR,  # handful per lieutenant, covers one kingdom/city
	OPERATIVE,    # ground crew, abstracted in bulk under a coordinator
}

@export var id: StringName = &""

# Origin: if non-empty, points at Actors registry. Drives trait reads
# and lets the player see the person behind the role. Empty string for
# operatives the coordinator layer cooked up on its own.
@export var source_actor_id: StringName = &""

@export var display_name: String = ""
@export var cover: String = ""                   # "a scribe at court", "merchant in the port"
@export var layer: Layer = Layer.OPERATIVE
@export var region_id: String = ""               # kingdom_id they cover
@export var superior_id: StringName = &""        # empty for Lieutenants (they answer to the player)

# Player's read of them. Grows with successful dispatches and time,
# decays with botched runs. Not the same as the `relationship` field on
# Actor — that measured personal warmth; this measures operational
# confidence.
@export_range(0, 100) var trust: int = 40

# Their operational competence. Drives the success bonus that goes on
# top of the base action chance whenever work is routed through them.
# Drifts slowly upward with successful tenure.
@export_range(0, 100) var skill: int = 40

# Their *own* exposure. Burns them (cell dissolved, layer rebuild)
# rather than the player. Grows when actions they dispatched fail.
@export_range(0, 100) var heat: int = 0

# Days since they were promoted. Used for "seasoned" checks and flavour
# text in the Roster view.
@export var tenure_days: int = 0

# A burned member is compromised — they've been arrested, flipped, or
# otherwise lost. Kept in the registry as a ghost for save compatibility
# and for the "X was burned" letters that surface in the weeks after.
@export var burned: bool = false

# Flavour-only; the first role the member held at promotion. Used to
# colour Memoirs entries and for the Roster cover blurbs.
@export var origin_blurb: String = ""


func layer_name() -> String:
	match layer:
		Layer.LIEUTENANT:  return "Lieutenant"
		Layer.COORDINATOR: return "Coordinator"
		Layer.OPERATIVE:   return "Operative"
	return "?"


# --- Serialisation -----------------------------------------------------------

static func from_dict(d: Dictionary) -> OrgMember:
	var m: OrgMember = OrgMember.new()
	m.id              = StringName(String(d.get("id", "")))
	m.source_actor_id = StringName(String(d.get("source_actor_id", "")))
	m.display_name    = String(d.get("display_name", ""))
	m.cover           = String(d.get("cover", ""))
	m.layer           = _layer_from_string(String(d.get("layer", "OPERATIVE")))
	m.region_id       = String(d.get("region_id", ""))
	m.superior_id     = StringName(String(d.get("superior_id", "")))
	m.trust           = clampi(int(d.get("trust", 40)), 0, 100)
	m.skill           = clampi(int(d.get("skill", 40)), 0, 100)
	m.heat            = clampi(int(d.get("heat",  0)), 0, 100)
	m.tenure_days     = int(d.get("tenure_days", 0))
	m.burned          = bool(d.get("burned", false))
	m.origin_blurb    = String(d.get("origin_blurb", ""))
	return m


func to_dict() -> Dictionary:
	return {
		"id":              String(id),
		"source_actor_id": String(source_actor_id),
		"display_name":    display_name,
		"cover":           cover,
		"layer":           Layer.keys()[layer],
		"region_id":       region_id,
		"superior_id":     String(superior_id),
		"trust":           trust,
		"skill":           skill,
		"heat":            heat,
		"tenure_days":     tenure_days,
		"burned":          burned,
		"origin_blurb":    origin_blurb,
	}


static func _layer_from_string(s: String) -> Layer:
	match s.to_upper():
		"LIEUTENANT":  return Layer.LIEUTENANT
		"COORDINATOR": return Layer.COORDINATOR
		"OPERATIVE":   return Layer.OPERATIVE
	return Layer.OPERATIVE
