class_name DifficultyProfile
extends RefCounted
## §10.6 difficulty modifiers. This is a value-type wrapper around the
## five hardship toggles stored in `Prefs`. Systems that care about
## difficulty call `DifficultyProfile.current()` and read the booleans
## or the derived scalars — nothing else in the codebase needs to know
## the toggle names directly.

var aggressive_rivals: bool = false
var lean_start: bool = false
var hostile_hosts: bool = false
var fast_hunters: bool = false
var brittle_cover: bool = false


## Returns the profile as configured by current user prefs. Safe to
## call even if `Prefs` is not yet loaded — falls back to defaults.
static func current() -> DifficultyProfile:
	var p: DifficultyProfile = DifficultyProfile.new()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return p
	var prefs: Node = tree.root.get_node_or_null("Prefs")
	if prefs == null:
		return p
	p.aggressive_rivals = bool(prefs.get("aggressive_rivals"))
	p.lean_start        = bool(prefs.get("lean_start"))
	p.hostile_hosts     = bool(prefs.get("hostile_hosts"))
	p.fast_hunters      = bool(prefs.get("fast_hunters"))
	p.brittle_cover     = bool(prefs.get("brittle_cover"))
	return p


# --- Derived scalars (single source of truth for formulas) ------------------

## Extra resistance floor added to every host when `hostile_hosts` is on.
## Applied by `ActorHostPicker` / resistance calculations.
func host_resistance_bonus() -> int:
	return 15 if hostile_hosts else 0


## Multiplier for cover decay per action. 1.0 == vanilla, 1.25 when
## `brittle_cover` is on (§10.6 note: "cover decay per action +25%").
func cover_decay_multiplier() -> float:
	return 1.25 if brittle_cover else 1.0


## Scale for rival action frequency. 2.0 doubles the pressure.
func rival_action_frequency() -> float:
	return 2.0 if aggressive_rivals else 1.0


## Starting-purse multiplier. 0.5 when `lean_start` is on.
func starting_purse_multiplier() -> float:
	return 0.5 if lean_start else 1.0


## Scale for hunter emergence thresholds (lower means hunters arrive
## sooner). 0.6 when `fast_hunters` is on.
func hunter_threshold_multiplier() -> float:
	return 0.6 if fast_hunters else 1.0
