class_name RivalSociety
extends Resource
## A named secret society per §5. Resource rather than Node because
## we want to serialise their evolving foothold map cleanly and
## because RivalRegistry is the authoritative owner of their lifecycle.
##
## Hidden information by design: the player discovers a society's
## existence, methods, and footholds through investigation (see §8.12
## fingerprint chain). Nothing on this object should be rendered to
## the UI directly — it flows through the fingerprint library first.

## Organisational shape of the rival network (§5 "Mechanically distinct").
## Drives the texture of their operations: hierarchical societies move
## slowly but in force; cellular ones strike fast and scatter.
enum NetworkShape {
	HIERARCHICAL,   # Architects
	CELLULAR,       # Pyre
	FAMILY,         # Weavers
	DISTRIBUTED,    # Veil
	DIFFUSE,        # Compact
}

## How often the society acts, relative to the global monthly tick.
## A SLOW society acts roughly once a year; REACTIVE acts every few
## months; CONSTANT is always nibbling at the edges somewhere.
enum Tempo {
	SLOW,           # ~1 op / 10-14 months
	REACTIVE,       # ~1 op / 3-5 months, triggered by instability
	GENERATIONAL,   # ~1 op / year, tied to dynastic events
	STEADY,         # ~1 op / 4-6 months
	CONSTANT,       # ~1 op / 2 months, small movements
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var philosophy: String = ""
@export var network_shape: NetworkShape = NetworkShape.HIERARCHICAL
@export var tempo: Tempo = Tempo.STEADY

# Kingdom ids where the society has its deepest roots (§5 strongholds).
# Foothold scores in these regions regenerate toward the ceiling monthly.
@export var stronghold_kingdoms: Array[String] = []

# The characteristic levers this society pulls. The RivalRegistry's
# method→event-kind map turns these into specific public events at
# operation time. Ordering is preference order — the first method
# applicable in the target region is the one chosen.
@export var preferred_methods: Array[StringName] = []

# Per-kingdom foothold strength 0-100. Mutated monthly. A society
# with foothold 0 in a kingdom has no meaningful presence there.
@export var footholds: Dictionary = {}  # String kingdom_id -> int

# Monotonically incrementing counter of operations this society has
# executed in the current campaign. Helps the fingerprint chain decide
# whether there is enough material to match.
@export var ops_count: int = 0


func foothold_in(kingdom_id: String) -> int:
	return int(footholds.get(kingdom_id, 0))


func bump_foothold(kingdom_id: String, delta: int) -> void:
	if kingdom_id.is_empty():
		return
	var cap: int = 90 if stronghold_kingdoms.has(kingdom_id) else 70
	var prev: int = foothold_in(kingdom_id)
	var next: int = clampi(prev + delta, 0, cap)
	footholds[kingdom_id] = next


func to_dict() -> Dictionary:
	return {
		"id":                  String(id),
		"display_name":        display_name,
		"philosophy":          philosophy,
		"network_shape":       NetworkShape.keys()[network_shape],
		"tempo":               Tempo.keys()[tempo],
		"stronghold_kingdoms": stronghold_kingdoms.duplicate(),
		"preferred_methods":   _string_names_to_strings(preferred_methods),
		"footholds":           footholds.duplicate(true),
		"ops_count":           ops_count,
	}


static func from_dict(d: Dictionary) -> RivalSociety:
	var s: RivalSociety = RivalSociety.new()
	s.id                  = StringName(String(d.get("id", "")))
	s.display_name        = String(d.get("display_name", ""))
	s.philosophy          = String(d.get("philosophy", ""))
	s.network_shape       = _shape_from_string(String(d.get("network_shape", "HIERARCHICAL")))
	s.tempo               = _tempo_from_string(String(d.get("tempo", "STEADY")))
	var sh: Variant = d.get("stronghold_kingdoms", [])
	if sh is Array:
		for k in sh:
			s.stronghold_kingdoms.append(String(k))
	var pm: Variant = d.get("preferred_methods", [])
	if pm is Array:
		for m in pm:
			s.preferred_methods.append(StringName(String(m)))
	var fh: Variant = d.get("footholds", {})
	if fh is Dictionary:
		for k in fh:
			s.footholds[String(k)] = int(fh[k])
	s.ops_count = int(d.get("ops_count", 0))
	return s


static func _string_names_to_strings(arr: Array[StringName]) -> Array:
	var out: Array = []
	for s in arr:
		out.append(String(s))
	return out


static func _shape_from_string(s: String) -> NetworkShape:
	match s:
		"HIERARCHICAL": return NetworkShape.HIERARCHICAL
		"CELLULAR":     return NetworkShape.CELLULAR
		"FAMILY":       return NetworkShape.FAMILY
		"DISTRIBUTED":  return NetworkShape.DISTRIBUTED
		"DIFFUSE":      return NetworkShape.DIFFUSE
		_:              return NetworkShape.HIERARCHICAL


static func _tempo_from_string(s: String) -> Tempo:
	match s:
		"SLOW":         return Tempo.SLOW
		"REACTIVE":     return Tempo.REACTIVE
		"GENERATIONAL": return Tempo.GENERATIONAL
		"STEADY":       return Tempo.STEADY
		"CONSTANT":     return Tempo.CONSTANT
		_:              return Tempo.STEADY
