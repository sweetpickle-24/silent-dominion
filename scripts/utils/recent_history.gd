class_name RecentHistoryQueries
extends RefCounted

# Autoloads accessed via SceneTree root because this is a class_name script.
static func _get_autoload(name: StringName) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(NodePath(name))


# Most recent events of a class within a window.
func events_within(event_class: GDScript, days_window: int) -> Array:
	var event_bus: Node = _get_autoload(&"EventBus")
	return event_bus.get_recent_events(event_class, days_window)


# General-purpose counted query: count events within a window where a field matches a value.
func count_events_with(event_class: GDScript, days_window: int, key: StringName, value: Variant) -> int:
	var events: Array = events_within(event_class, days_window)
	var count: int = 0
	for ev in events:
		if ev.get(key) == value:
			count += 1
	return count

# TODO: book_burnings_in_region(region, days_window) — needs BookBurningEvent class
# TODO: battles_in_region(region, days_window) — needs BattleResolvedEvent class
# TODO: deaths_of_chain_member(immortal_ref, days_window) — needs ChainLinkRemovedEvent class
