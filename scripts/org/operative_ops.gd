class_name OperativeOps
extends RefCounted
## §C1 Pure-function module for the Operative layer of the player's
## organisation. Functions here take an `OrgMember` (and occasionally
## some context) and return values or perform targeted mutations. They
## do not own state. `org_registry.gd` is the stateful owner; this
## module is the per-layer behaviour table.
##
## Why this split? `OrgMember` itself is intentionally pure data
## (§OrgMember header comment) so save/load stays a no-op. The
## previous design mixed per-layer decisions inline into
## `org_registry.gd`, which made each layer's rules hard to read at a
## glance. Splitting into three sibling modules (`OperativeOps`,
## `CoordinatorOps`, `LieutenantOps`) keeps each layer's behaviour
## co-located and leaves `org_registry.gd` as the sequencer.

const OP_COVER_BANK: Array[String] = [
	"a scribe at the record-house",
	"a merchant in the coastal quarter",
	"a steward at a minor temple",
	"a smith with custom of the palace",
	"a purser on the ferry route",
	"a tutor to a second son",
	"a harbour clerk",
	"an innkeeper on the north road",
]


## Operatives have no subordinates, so their span-strain is always 0.
## Provided for symmetry with the other ops modules.
static func strain_excess(_m: OrgMember) -> int:
	return 0


## Abstract (non-actor) operatives drift up slowly toward a floor of
## 60 trust; promoted-from-actor operatives follow the actor-driven
## drift (handled in CoordinatorOps/OrgRegistry). Separated here so
## the "cooked up on its own" path has a single, documented home.
static func trust_drift_abstract(m: OrgMember, rng: RandomNumberGenerator) -> int:
	if m.trust < 60:
		return 1 if rng.randf() < 0.33 else 0
	return 0


## Build a fresh abstract operative under `coord`. Returns a detached
## `OrgMember` — caller is responsible for registering it. Keeps all
## the recruitment details (cover, skill band, trust band, name-bank
## read) in one place so tuning this layer doesn't require editing
## the registry.
static func spawn_abstract(
		coord: OrgMember,
		rng: RandomNumberGenerator,
	) -> OrgMember:
	var op: OrgMember = OrgMember.new()
	op.id              = StringName("org_op_%s_%d_%d" % [coord.region_id, Time.get_ticks_msec(), rng.randi()])
	op.source_actor_id = &""
	op.display_name    = _abstract_op_name(coord.region_id, rng)
	op.layer           = OrgMember.Layer.OPERATIVE
	op.region_id       = coord.region_id
	op.superior_id     = coord.id
	op.trust           = rng.randi_range(40, 55)
	op.skill           = clampi(coord.skill - 10 + rng.randi_range(-5, 10), 20, 75)
	op.heat            = 0
	op.tenure_days     = 0
	op.cover           = OP_COVER_BANK[rng.randi_range(0, OP_COVER_BANK.size() - 1)]
	op.origin_blurb    = "Recruited by %s." % coord.display_name
	return op


static func _abstract_op_name(kingdom_id: String, rng: RandomNumberGenerator) -> String:
	var bank: Array = Actors.NAME_BANKS.get(kingdom_id, ["Eunomos", "Syros", "Dares"])
	return "%s (op.)" % String(bank[rng.randi_range(0, bank.size() - 1)])
