class_name Religion
extends Resource
## A single faith — pantheon, mystery cult, philosophy-as-cult, or
## organised church. Religions are structured entities (§25.1):
## doctrine + institution + popular faith + reform pressure +
## openness, plus a phase along the lifecycle (§25.2).
##
## Religions are the long-arc target of ideological play. They drift
## monthly in the Religions autoload; the resource itself is just the
## data shape and a few read-only helpers.

enum Phase {
	EMERGENCE,      # a charismatic founder, a small population pool
	CONSOLIDATION,  # doctrine and hierarchy harden
	DOMINANCE,      # established cultural authority in its region
	FRACTURE,       # schism in progress
	DECLINE,        # losing depth and institutional weight
}

@export var id: StringName = &""
@export var religion_name: String = ""
@export var phase: Phase = Phase.CONSOLIDATION

## §25.3 — ideologies (Stoicism, Confucianism, later liberalism /
## nationalism) share the religious data model wholesale. This
## flag only changes the vocabulary used in UI and the weighting
## of certain lifecycle nudges (ideologies fracture on reform
## potential faster; religions fracture on doctrinal rigidity).
@export var is_ideology: bool = false

# All five §25.1 attributes on a 0-100 scale.
@export_range(0, 100) var doctrinal_rigidity:    int = 50
@export_range(0, 100) var institutional_strength: int = 50
@export_range(0, 100) var popular_depth:          int = 50
@export_range(0, 100) var reform_potential:       int = 0
@export_range(0, 100) var ecumenical_openness:    int = 50

## province_id -> share 0..100 of that province's population
## that follows this faith. Multiple religions can co-exist in the
## same province; shares need not sum to 100 (the remainder is
## treated as "unaffiliated" or local pagan).
@export var presence: Dictionary = {}

## Year the religion was first recognised in-world (negative for BCE).
## Used by the lifecycle to skip emergence/consolidation drift in the
## first decades of play.
@export var founded_year: int = 0

## If this religion split off from another, the parent's id. Empty
## for original faiths. Used by the schism logic so the splinter
## remembers where it came from.
@export var parent_religion_id: StringName = &""


# --- §13.4 manual-engagement gate -------------------------------------------
#
# A religion is an opaque black box until the player has worked
# through it manually at least once. `engaged_manually` latches
# true after the first successful religion-aimed action against
# one of its significant provinces. The snapshot captured at that
# moment is what the staleness check compares against later —
# doctrinal or institutional drift past `ENGAGEMENT_STALE_DRIFT`
# means the old library entry is no longer a safe guide.
@export var engaged_manually: bool = false
@export var engaged_year: int = 0
@export var engaged_doctrinal_rigidity: int = 0
@export var engaged_institutional_strength: int = 0
@export var engaged_popular_depth: int = 0
@export var engaged_reform_potential: int = 0
@export var engaged_ecumenical_openness: int = 0


const ENGAGEMENT_STALE_DRIFT: int = 15


func phase_name() -> String:
	return Phase.keys()[phase]


func kind_label() -> String:
	return "school of thought" if is_ideology else "faith"


func follower_verb() -> String:
	return "adhere to" if is_ideology else "follow"


func engagement_stale() -> bool:
	if not engaged_manually:
		return false
	return (
		absi(doctrinal_rigidity     - engaged_doctrinal_rigidity)     >= ENGAGEMENT_STALE_DRIFT
		or absi(institutional_strength - engaged_institutional_strength) >= ENGAGEMENT_STALE_DRIFT
		or absi(popular_depth        - engaged_popular_depth)        >= ENGAGEMENT_STALE_DRIFT
		or absi(reform_potential     - engaged_reform_potential)     >= ENGAGEMENT_STALE_DRIFT
		or absi(ecumenical_openness  - engaged_ecumenical_openness)  >= ENGAGEMENT_STALE_DRIFT
	)


func snapshot_engagement(year: int) -> void:
	engaged_manually = true
	engaged_year = year
	engaged_doctrinal_rigidity = doctrinal_rigidity
	engaged_institutional_strength = institutional_strength
	engaged_popular_depth = popular_depth
	engaged_reform_potential = reform_potential
	engaged_ecumenical_openness = ecumenical_openness


func is_extinct() -> bool:
	return phase == Phase.DECLINE and popular_depth < 5


func dominant_in(province_id: String) -> bool:
	return share_in(province_id) >= 50


func share_in(province_id: String) -> int:
	return int(presence.get(province_id, 0))


func set_share(province_id: String, share: int) -> void:
	var v: int = clampi(share, 0, 100)
	if v <= 0:
		presence.erase(province_id)
	else:
		presence[province_id] = v


# --- Serialisation ----------------------------------------------------------

static func from_dict(d: Dictionary) -> Religion:
	var r: Religion = Religion.new()
	r.id                    = StringName(String(d.get("id", "")))
	r.religion_name         = String(d.get("name", String(r.id)))
	r.phase                 = _phase_from_string(String(d.get("phase", "CONSOLIDATION")))
	r.doctrinal_rigidity    = clampi(int(d.get("doctrinal_rigidity", 50)),    0, 100)
	r.institutional_strength = clampi(int(d.get("institutional_strength", 50)), 0, 100)
	r.popular_depth          = clampi(int(d.get("popular_depth", 50)),          0, 100)
	r.reform_potential       = clampi(int(d.get("reform_potential", 0)),         0, 100)
	r.ecumenical_openness    = clampi(int(d.get("ecumenical_openness", 50)),    0, 100)
	r.founded_year           = int(d.get("founded_year", 0))
	r.parent_religion_id     = StringName(String(d.get("parent_religion_id", "")))
	r.is_ideology            = bool(d.get("is_ideology", false))
	r.engaged_manually              = bool(d.get("engaged_manually", false))
	r.engaged_year                  = int(d.get("engaged_year", 0))
	r.engaged_doctrinal_rigidity    = int(d.get("engaged_doctrinal_rigidity", 0))
	r.engaged_institutional_strength = int(d.get("engaged_institutional_strength", 0))
	r.engaged_popular_depth         = int(d.get("engaged_popular_depth", 0))
	r.engaged_reform_potential      = int(d.get("engaged_reform_potential", 0))
	r.engaged_ecumenical_openness   = int(d.get("engaged_ecumenical_openness", 0))
	r.presence = {}
	for pid in d.get("presence", {}).keys():
		r.presence[String(pid)] = clampi(int(d["presence"][pid]), 0, 100)
	return r


func to_dict() -> Dictionary:
	return {
		"id":                     String(id),
		"name":                   religion_name,
		"phase":                  phase_name(),
		"doctrinal_rigidity":     doctrinal_rigidity,
		"institutional_strength": institutional_strength,
		"popular_depth":          popular_depth,
		"reform_potential":       reform_potential,
		"ecumenical_openness":    ecumenical_openness,
		"founded_year":           founded_year,
		"parent_religion_id":     String(parent_religion_id),
		"is_ideology":            is_ideology,
		"engaged_manually":       engaged_manually,
		"engaged_year":           engaged_year,
		"engaged_doctrinal_rigidity":     engaged_doctrinal_rigidity,
		"engaged_institutional_strength": engaged_institutional_strength,
		"engaged_popular_depth":          engaged_popular_depth,
		"engaged_reform_potential":       engaged_reform_potential,
		"engaged_ecumenical_openness":    engaged_ecumenical_openness,
		"presence":               presence.duplicate(true),
	}


static func _phase_from_string(s: String) -> Phase:
	match s.to_upper():
		"EMERGENCE":     return Phase.EMERGENCE
		"CONSOLIDATION": return Phase.CONSOLIDATION
		"DOMINANCE":     return Phase.DOMINANCE
		"FRACTURE":      return Phase.FRACTURE
		"DECLINE":       return Phase.DECLINE
		_:               return Phase.CONSOLIDATION
