# Autoloads accessed via SceneTree root because GDScript class_name scripts
# can't reference autoload globals directly. C3's API is preserved.
class_name RuleContext
extends RefCounted

# Five universal variables — always present, may be null.
var event: EventBase = null
var self_obj: Object = null      # "self" is reserved in GDScript; Expression variable name is "self"
var target: Object = null
var world: WorldView = null
var helpers: Node = null          # Helpers autoload reference

# Standard variable name list for Expression.parse.
# Note: "self" is the Expression-facing name for self_obj.
const VARIABLE_NAMES: Array = ["event", "self", "target", "world", "helpers"]


# Returns values array in same order as VARIABLE_NAMES for Expression.execute().
func variable_values() -> Array:
	return [event, self_obj, target, world, helpers]


static func _get_autoload(name: StringName) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(NodePath(name))


# Constructor for event-driven evaluations.
static func for_event(event_obj: EventBase, owner: Object, the_target: Object = null) -> RuleContext:
	var ctx := RuleContext.new()
	ctx.event = event_obj
	ctx.self_obj = owner
	ctx.target = the_target
	ctx.world = WorldView.snapshot()
	ctx.helpers = _get_autoload(&"Helpers")
	return ctx


# Constructor for non-event evaluations (era transitions, society emergence, etc.).
static func world_only(day: int, era: StringName) -> RuleContext:
	var ctx := RuleContext.new()
	ctx.world = WorldView.snapshot_for(day, era)
	ctx.helpers = _get_autoload(&"Helpers")
	return ctx


# Resolve a variable by its Expression-facing name.
# Used by the Similarity function's attribute_path resolver.
func get_variable(name: StringName) -> Variant:
	match name:
		&"event": return event
		&"self": return self_obj
		&"target": return target
		&"world": return world
		&"helpers": return helpers
		_: return null
