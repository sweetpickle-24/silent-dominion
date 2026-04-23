class_name LieutenantOps
extends RefCounted
## §C1 Pure-function module for the Lieutenant layer. Lieutenants
## run regions (one kingdom in Phase 2.1) and supervise coordinators.
## This module owns the span-of-control cap, the eligibility check
## for lieutenant promotion, and the "who is the lieutenant over X?"
## lookup shape.
##
## `org_registry.gd` calls into here rather than reasoning about
## these rules itself. See `operative_ops.gd` for the sibling design
## note.

## Soft cap on coordinators reporting to a single lieutenant. Same
## mechanics as `CoordinatorOps.MAX_OPERATIVES`.
const MAX_COORDINATORS: int = 5

## Minimum tenure (in days) for a coordinator to be eligible for
## promotion to lieutenant. One game-year.
const PROMOTION_MIN_TENURE_DAYS: int = 365

## Minimum trust for a coordinator to be considered promotable.
const PROMOTION_MIN_TRUST: int = 70


## How many coordinators above the cap report to this lieutenant.
## See `CoordinatorOps.strain_excess` for the matching signature.
static func strain_excess(m: OrgMember, reports_count: int) -> int:
	if m == null or m.burned or m.layer != OrgMember.Layer.LIEUTENANT:
		return 0
	return maxi(0, reports_count - MAX_COORDINATORS)


## Eligibility gate for promotion from Coordinator to Lieutenant.
## A coordinator qualifies once they have both survived a year and
## earned the player's trust. ActionRunner uses this rather than
## re-implementing the rule inline.
static func is_promotable(m: OrgMember) -> bool:
	if m == null or m.burned:
		return false
	if m.layer != OrgMember.Layer.COORDINATOR:
		return false
	if m.trust < PROMOTION_MIN_TRUST:
		return false
	if m.tenure_days < PROMOTION_MIN_TENURE_DAYS:
		return false
	return true


## Find the lieutenant whose `region_id` matches `kingdom_id`.
## Returns &"" if no lieutenant covers this region (in which case a
## fresh coordinator reports straight to the player). Operates on
## the full member list to stay pure.
static func find_over(members: Array[OrgMember], kingdom_id: String) -> StringName:
	for m in members:
		if m.burned:
			continue
		if m.layer == OrgMember.Layer.LIEUTENANT and m.region_id == kingdom_id:
			return m.id
	return &""
