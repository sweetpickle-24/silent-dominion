class_name AutomationRule
extends Resource
## A standing order the player has delegated to the organisation (§13.2).
##
## The player saw a pattern in their Memoirs, decided they had walked
## it often enough to trust, and said "run this on its own from now
## on." The rule records *what* action to dispatch, *against whom*
## (a single actor, anyone matching in a kingdom, or — later — a
## whole region), and *how often*. The engine ticks monthly, fires
## an action when the cadence elapses, and flags the rule if the
## underlying pattern has grown stale.
##
## Rules are strictly delegation of already-learned work. They are
## not a way to discover new things: if Memoirs doesn't have a
## current pattern for the action-target profile, the engine
## refuses to fire and pauses the rule with a note.

enum Scope {
	ACTOR,      # fire against one specific actor by id
	KINGDOM,    # fire against anyone in kingdom_id whose profile matches
	REGION,     # §13.3 — fire against anyone in a geographic region
}

@export var id: StringName = &""

@export var scope: Scope = Scope.ACTOR

## For ACTOR scope: the actor id. Empty for other scopes.
@export var target_actor_id: StringName = &""

## For KINGDOM scope: the kingdom id. Empty for other scopes.
@export var kingdom_id: String = ""

## For REGION scope: the region id. Empty for other scopes.
@export var region_id: String = ""

## The action to dispatch. Must match the pattern.
@export var action_id: StringName = &""

## The pattern this rule was founded on. If the pattern is removed
## or goes stale past the engine's tolerance, the rule is paused.
@export var pattern_id: StringName = &""

## Lieutenant the player wants routing this — nice-to-have, not
## enforced. Engine still routes through the closest coordinator.
@export var preferred_lieutenant_id: StringName = &""

## How often (in months) the rule fires when active.
@export_range(1, 60) var cadence_months: int = 6

## Life-cycle.
@export var active: bool = true
@export var paused: bool = false
@export var paused_reason: StringName = &""

@export var created_year: int = 0
@export var last_fired_abs_day: int = 0
@export var fire_count: int = 0
@export var success_count: int = 0


func scope_label() -> String:
	match scope:
		Scope.ACTOR:   return "on a named hand"
		Scope.KINGDOM: return "across one kingdom"
		Scope.REGION:  return "across a region"
	return "somewhere"


func success_ratio() -> float:
	if fire_count <= 0:
		return 0.0
	return float(success_count) / float(fire_count)


func from_dict_into(d: Dictionary) -> void:
	id = StringName(String(d.get("id", "")))
	scope = _scope_from_string(String(d.get("scope", "ACTOR")))
	target_actor_id = StringName(String(d.get("target_actor_id", "")))
	kingdom_id = String(d.get("kingdom_id", ""))
	region_id = String(d.get("region_id", ""))
	action_id = StringName(String(d.get("action_id", "")))
	pattern_id = StringName(String(d.get("pattern_id", "")))
	preferred_lieutenant_id = StringName(String(d.get("preferred_lieutenant_id", "")))
	cadence_months = clampi(int(d.get("cadence_months", 6)), 1, 60)
	active = bool(d.get("active", true))
	paused = bool(d.get("paused", false))
	paused_reason = StringName(String(d.get("paused_reason", "")))
	created_year = int(d.get("created_year", 0))
	last_fired_abs_day = int(d.get("last_fired_abs_day", 0))
	fire_count = int(d.get("fire_count", 0))
	success_count = int(d.get("success_count", 0))


static func from_dict(d: Dictionary) -> AutomationRule:
	var r: AutomationRule = AutomationRule.new()
	r.from_dict_into(d)
	return r


func to_dict() -> Dictionary:
	return {
		"id":                     String(id),
		"scope":                  Scope.keys()[scope],
		"target_actor_id":        String(target_actor_id),
		"kingdom_id":             kingdom_id,
		"region_id":              region_id,
		"action_id":              String(action_id),
		"pattern_id":             String(pattern_id),
		"preferred_lieutenant_id": String(preferred_lieutenant_id),
		"cadence_months":         cadence_months,
		"active":                 active,
		"paused":                 paused,
		"paused_reason":          String(paused_reason),
		"created_year":           created_year,
		"last_fired_abs_day":     last_fired_abs_day,
		"fire_count":             fire_count,
		"success_count":          success_count,
	}


static func _scope_from_string(s: String) -> Scope:
	match s.to_upper():
		"ACTOR":   return Scope.ACTOR
		"KINGDOM": return Scope.KINGDOM
		"REGION":  return Scope.REGION
		_:         return Scope.ACTOR
