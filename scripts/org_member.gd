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
##
## §C1 design decision — single-class, per-layer Ops modules.
## The docs spec reads as if each layer should be a distinct class.
## We keep `OrgMember` as a single resource because:
##   - save/load stays a single serialisation path;
##   - the Roster view can iterate a single typed array;
##   - promotions move between layers without reconstructing a
##     different class.
## The per-layer *behaviour* lives in three sibling modules under
## `scripts/org/`: `OperativeOps`, `CoordinatorOps`, `LieutenantOps`.
## `OrgMember` is pure data and serialisation; the modules are pure
## functions that take an `OrgMember` and any external context. This
## gives us the benefits the docs were asking for — each layer's
## rules in one place — without the downsides of class splitting.

enum Layer {
	LIEUTENANT,   # 3-6 of these, each covers a region or domain
	COORDINATOR,  # handful per lieutenant, covers one kingdom/city
	OPERATIVE,    # ground crew, abstracted in bulk under a coordinator
}

## §21.5 functional specialisations. Only meaningful on Lieutenants
## — coordinators and operatives leave this at NONE. The mapping to
## ideal family backgrounds drives the natural-authority bonus when a
## lieutenant is drawn from a matching dynasty.
enum Specialisation {
	NONE,
	FINANCIAL,     # banking / merchant dynasties
	INTELLIGENCE,  # administrative / diplomatic backgrounds
	IDEOLOGICAL,   # scholarly / clerical lineages
	SECURITY,      # military / hard-loyalty lines
	POLITICAL,     # noble / courtier houses
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

# --- Source integrity (§18) ---------------------------------------------------
#
# How reliable the intel flowing through this member is. 100 = trusted
# completely; drops after cross-reference contradictions or failed
# actions built on their reporting. Runs parallel to `trust` (which is
# the player's personal confidence in the person) and `skill` (their
# operational competence).
@export_range(0, 100) var confidence: int = 100

# --- Internal corruption (§19) ------------------------------------------------
#
# Months since the last audit. Long tenure without oversight is a
# corruption risk in itself; this drives the visible "drift" warning in
# the Roster and increases the yield of audit_cell.
@export var months_since_audit: int = 0

# Flagged by an audit / source-check as potentially compromised. Purely
# informational; the consequences come from the response the player
# chooses (quiet reassign, double-agent, sever). Resets on audit pass.
@export var suspected_compromised: bool = false

# Double-agent mode (§18.5). The member has been confirmed compromised
# and flipped: we now use them as a controlled feeder back into the
# rival network. They stop being a reliable source themselves — their
# reports carry our chosen noise — and they steadily bleed exposure.
@export var double_agent: bool = false

## Where the suspected / confirmed corruption is coming from. Tagged at
## the moment `suspected_compromised` (or `double_agent`) is raised so
## that audit letters, roster hints, and downstream dialogue can speak
## to the real source. UNKNOWN is the default while flags are clean.
enum CorruptionSource {
	UNKNOWN,  # no current flag
	GREED,    # drift from within — bribes, side dealings, tenure rot
	RIVAL,    # the member has been turned / fed by a rival network
}
@export var corruption_source: CorruptionSource = CorruptionSource.UNKNOWN

@export var specialisation: Specialisation = Specialisation.NONE


func layer_name() -> String:
	match layer:
		Layer.LIEUTENANT:  return "Lieutenant"
		Layer.COORDINATOR: return "Coordinator"
		Layer.OPERATIVE:   return "Operative"
	return "?"


func specialisation_label() -> String:
	match specialisation:
		Specialisation.FINANCIAL:    return "Financial"
		Specialisation.INTELLIGENCE: return "Intelligence"
		Specialisation.IDEOLOGICAL:  return "Ideological"
		Specialisation.SECURITY:     return "Security"
		Specialisation.POLITICAL:    return "Political"
		_:                           return ""


## Returns the recommended specialisation based on the origin
## family's domain, or NONE if no family is tracked. Used by the
## Roster UI to suggest the natural posting for a promotion.
func recommended_specialisation_from_family(f) -> Specialisation:
	if f == null:
		return Specialisation.NONE
	match int(f.domain):
		int(Family.Domain.BANKING), int(Family.Domain.MERCHANT):
			return Specialisation.FINANCIAL
		int(Family.Domain.SCHOLARLY), int(Family.Domain.RELIGIOUS):
			return Specialisation.IDEOLOGICAL
		int(Family.Domain.MILITARY):
			return Specialisation.SECURITY
		int(Family.Domain.COURT):
			return Specialisation.POLITICAL
		_:
			return Specialisation.NONE


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
	m.confidence            = clampi(int(d.get("confidence", 100)), 0, 100)
	m.months_since_audit    = int(d.get("months_since_audit", 0))
	m.suspected_compromised = bool(d.get("suspected_compromised", false))
	m.double_agent          = bool(d.get("double_agent", false))
	m.corruption_source     = _corr_from_string(String(d.get("corruption_source", "UNKNOWN")))
	m.specialisation        = _spec_from_string(String(d.get("specialisation", "NONE")))
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
		"confidence":            confidence,
		"months_since_audit":    months_since_audit,
		"suspected_compromised": suspected_compromised,
		"double_agent":          double_agent,
		"corruption_source":     CorruptionSource.keys()[corruption_source],
		"specialisation":        Specialisation.keys()[specialisation],
	}


static func _layer_from_string(s: String) -> Layer:
	match s.to_upper():
		"LIEUTENANT":  return Layer.LIEUTENANT
		"COORDINATOR": return Layer.COORDINATOR
		"OPERATIVE":   return Layer.OPERATIVE
	return Layer.OPERATIVE


static func _corr_from_string(s: String) -> CorruptionSource:
	match s.to_upper():
		"GREED": return CorruptionSource.GREED
		"RIVAL": return CorruptionSource.RIVAL
		_:       return CorruptionSource.UNKNOWN


func corruption_source_label() -> String:
	match corruption_source:
		CorruptionSource.GREED: return "greed"
		CorruptionSource.RIVAL: return "rival hand"
		_:                      return ""


static func _spec_from_string(s: String) -> Specialisation:
	match s.to_upper():
		"FINANCIAL":    return Specialisation.FINANCIAL
		"INTELLIGENCE": return Specialisation.INTELLIGENCE
		"IDEOLOGICAL":  return Specialisation.IDEOLOGICAL
		"SECURITY":     return Specialisation.SECURITY
		"POLITICAL":    return Specialisation.POLITICAL
		_:              return Specialisation.NONE
