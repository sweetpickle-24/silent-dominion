class_name ActionDefinition
extends Resource
## Static template for a player action (§3.4 Action Palette).
##
## Definitions come from `data/actions.json`. Each definition describes
## WHAT an action is — costs, tier, base success chance, how long it
## takes to resolve, what kind of target it needs. The ActionRunner
## consumes these to turn a player click into a queued pending action.

enum Tier {
	DEEP_SHADOW,   # §3.4 Tier 1 — very low exposure
	ACTIVE,        # §3.4 Tier 2 — medium exposure
	HIGH,          # §3.4 Tier 3 — high exposure
}

enum TargetKind {
	NONE,          # self-action (e.g. "wait")
	ACTOR,         # needs a target Actor id
	KINGDOM,       # needs a target kingdom id
	PROVINCE,      # needs a target province id
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var blurb: String = ""                       # short description shown in UI
@export var tier: Tier = Tier.DEEP_SHADOW
@export var target_kind: TargetKind = TargetKind.ACTOR

# Cost fields. Phase 0 does not yet enforce these; recorded for future
# resource / exposure systems.
@export var silver_cost: int = 0
@export var exposure_cost: int = 0

# Resolution timing. Randomised on issue as [min, max] inclusive.
@export var min_days_to_resolve: int = 3
@export var max_days_to_resolve: int = 10

# Base success chance 0.0-1.0 before any trait modifiers are applied.
@export var base_success_chance: float = 0.75

# Report voice. Used to pick era-appropriate phrasing when building the
# resolution letter. Keep short; "operative" for Phase 0.
@export var report_sender: String = "Anonymous operative"

# §5 host cultivation: if true, the ACTOR target must currently qualify
# as a host (loyal, non-ruler, alive). The chosen host executes the act
# on the player's behalf — so their traits drive the success roll and
# exposure is dampened because the visible hand is theirs, not yours.
@export var requires_host_target: bool = false


static func from_dict(d: Dictionary) -> ActionDefinition:
	var a: ActionDefinition = ActionDefinition.new()
	a.id                   = StringName(String(d.get("id", "")))
	a.display_name         = String(d.get("display_name", ""))
	a.blurb                = String(d.get("blurb", ""))
	a.tier                 = _tier_from_string(String(d.get("tier", "DEEP_SHADOW")))
	a.target_kind          = _target_from_string(String(d.get("target_kind", "ACTOR")))
	a.silver_cost          = int(d.get("silver_cost", 0))
	a.exposure_cost        = int(d.get("exposure_cost", 0))
	a.min_days_to_resolve  = int(d.get("min_days_to_resolve", 3))
	a.max_days_to_resolve  = int(d.get("max_days_to_resolve", 10))
	a.base_success_chance  = float(d.get("base_success_chance", 0.75))
	a.report_sender        = String(d.get("report_sender", "Anonymous operative"))
	a.requires_host_target = bool(d.get("requires_host_target", false))
	return a


static func _tier_from_string(s: String) -> Tier:
	match s.to_upper():
		"DEEP_SHADOW": return Tier.DEEP_SHADOW
		"ACTIVE":      return Tier.ACTIVE
		"HIGH":        return Tier.HIGH
		_:             return Tier.DEEP_SHADOW


static func _target_from_string(s: String) -> TargetKind:
	match s.to_upper():
		"NONE":     return TargetKind.NONE
		"ACTOR":    return TargetKind.ACTOR
		"KINGDOM":  return TargetKind.KINGDOM
		"PROVINCE": return TargetKind.PROVINCE
		_:          return TargetKind.ACTOR
