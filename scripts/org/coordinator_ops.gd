class_name CoordinatorOps
extends RefCounted
## §C1 Pure-function module for the Coordinator layer. Coordinators
## run one kingdom/city and supervise operatives. This module owns
## the span-of-control cap, the cover-phrase bank indexed by the
## promoted actor's role, and the coverage-selection heuristic.
##
## `org_registry.gd` calls into here rather than reasoning about
## these rules itself. See `operative_ops.gd` for the sibling design
## note.

## Soft cap on operatives reporting to a single coordinator. The
## player can exceed it; each excess costs `STRAIN_SKILL_PENALTY`
## effective-skill and a monthly heat bump. The cap is exposed
## rather than buried so tuning the organisation's shape can happen
## in one file.
const MAX_OPERATIVES: int = 6


## How many operatives above the cap report to this coordinator.
## Returns 0 if within the cap. `reports_count` is the caller's
## tallied number of active subordinates (OrgRegistry owns the
## dictionary; we don't reach back into it).
static func strain_excess(m: OrgMember, reports_count: int) -> int:
	if m == null or m.burned or m.layer != OrgMember.Layer.COORDINATOR:
		return 0
	return maxi(0, reports_count - MAX_OPERATIVES)


## Pick the strongest coverage candidate from a list of active
## coordinators in one kingdom. Highest trust wins; ties break on
## highest skill. Returns null for an empty list. Centralises the
## "which coordinator gets the handoff?" rule so the routing code
## in action_runner stays thin.
static func pick_best_coverage(candidates: Array[OrgMember]) -> OrgMember:
	if candidates.is_empty():
		return null
	var best: OrgMember = candidates[0]
	for m in candidates:
		if m.trust > best.trust:
			best = m
		elif m.trust == best.trust and m.skill > best.skill:
			best = m
	return best


## Cover phrase for a freshly-promoted coordinator, keyed by the
## source actor's role. Kept as a static map so new roles only need
## one touch point.
static func cover_for_role(role: int) -> String:
	match role:
		Actor.Role.MERCHANT:    return "trader; still runs their houses openly"
		Actor.Role.ADVISOR:     return "councillor; their voice at court is also ours"
		Actor.Role.PRIEST:      return "priest; every rite is a covering meeting"
		Actor.Role.PHILOSOPHER: return "scholar; the academy is a front"
		Actor.Role.GENERAL:     return "retired commander; veterans listen"
		Actor.Role.HEIR:        return "heir apparent; kept from the paperwork"
		_:                      return "kept out of records; lives as a private citizen"
