extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

# --- Inner classes ---

## Lightweight handle returned by subscribe(), used to unsubscribe.
class SubscriptionHandle:
	var id: int
	var event_class: GDScript

	func _init(p_id: int, p_event_class: GDScript) -> void:
		id = p_id
		event_class = p_event_class


## Internal subscription record. Not exposed outside EventBus.
class Subscription:
	var id: int
	var handler: Callable
	var priority: int
	var scope_filter: StringName
	var end_of_tick_phase: StringName

	func _init(
		p_id: int,
		p_handler: Callable,
		p_priority: int,
		p_scope_filter: StringName,
		p_end_of_tick_phase: StringName,
	) -> void:
		id = p_id
		handler = p_handler
		priority = p_priority
		scope_filter = p_scope_filter
		end_of_tick_phase = p_end_of_tick_phase


# --- State ---

# GDScript (event class) -> Array[Subscription], kept sorted by priority (ascending).
var _subscriptions: Dictionary = {}

var _current_tick_index: int = 0
var _next_handle_id: int = 0

# Cached autoload reference — avoids static-analysis issues with cross-autoload access.
var _logger: Node


func _ready() -> void:
	_logger = get_node("/root/Logger")
	_logger.info(LogChannels.EVENT_BUS, "EventBus ready")


# --- Public API ---

func subscribe(
	event_class: GDScript,
	handler: Callable,
	priority: int = 100,
	scope_filter: StringName = &"",
	end_of_tick_phase: StringName = EndOfTickPhases.UI,
) -> SubscriptionHandle:
	var sub_id: int = _next_handle_id
	_next_handle_id += 1

	var sub := Subscription.new(sub_id, handler, priority, scope_filter, end_of_tick_phase)

	if not _subscriptions.has(event_class):
		_subscriptions[event_class] = []
	var subs: Array = _subscriptions[event_class]
	subs.append(sub)
	# Keep sorted by priority ascending (lower fires first).
	subs.sort_custom(func(a: Subscription, b: Subscription) -> bool: return a.priority < b.priority)

	if _logger.enabled_for(LogChannels.EVENT_BUS, _LOG_DEBUG):
		_logger.debug(LogChannels.EVENT_BUS, "Subscribed", {
			"event": event_class.resource_path,
			"handler": str(handler),
			"priority": priority,
			"id": sub_id,
		})

	return SubscriptionHandle.new(sub_id, event_class)


func unsubscribe(handle: SubscriptionHandle) -> void:
	if not _subscriptions.has(handle.event_class):
		return
	var subs: Array = _subscriptions[handle.event_class]
	for i in range(subs.size()):
		if (subs[i] as Subscription).id == handle.id:
			subs.remove_at(i)
			return


func dispatch(event: EventBase) -> void:
	var mode: StringName = event.get_delivery_mode()

	match mode:
		DeliveryModes.SYNCHRONOUS:
			_dispatch_synchronous(event)
		DeliveryModes.QUEUED:
			push_error("EventBus: queued dispatch not yet implemented (Step 2 — synchronous only)")
		DeliveryModes.PER_TICK_BATCHED:
			push_error("EventBus: per-tick-batched dispatch not yet implemented (Step 2 — synchronous only)")
		_:
			push_error("EventBus: unknown delivery mode '%s'" % mode)


func end_of_tick(day: int) -> void:
	if _logger.enabled_for(LogChannels.EVENT_BUS, _LOG_DEBUG):
		_logger.debug(LogChannels.EVENT_BUS, "end_of_tick", {"day": day, "tick_index": _current_tick_index})
	_current_tick_index += 1
	# TODO: drain queued events per phase ordering (EndOfTickPhases)
	# TODO: process per-tick-batched events
	# TODO: call resolve_contested_operations(day)


func resolve_contested_operations(_day: int) -> void:
	push_error("EventBus: resolve_contested_operations not yet implemented")


func register_contested_operation(_op: Resource) -> void:
	push_error("EventBus: register_contested_operation not yet implemented")


func get_recent_events(_event_class: GDScript, _days_window: int = 1) -> Array:
	# TODO: implement recent-events ring buffer
	return []


# --- Internal dispatch ---

func _dispatch_synchronous(event: EventBase) -> void:
	var event_class: GDScript = event.get_script()

	# Stamp timing metadata.
	var tk: Node = get_node_or_null("/root/TimeKeeper")
	if tk and tk.get("current_day") != null:
		event.fired_at_day = tk.current_day
	event.fired_at_tick_index = _current_tick_index

	var subs: Array = _subscriptions.get(event_class, [])
	for sub: Subscription in subs:
		if not _passes_scope_filter(event, sub):
			continue
		sub.handler.call(event)
		if _logger.enabled_for(LogChannels.EVENT_BUS, _LOG_DEBUG):
			_logger.debug(LogChannels.EVENT_BUS, "%s -> %s (priority %d)" % [
				event_class.resource_path,
				str(sub.handler),
				sub.priority,
			])

	_current_tick_index += 1


func _passes_scope_filter(event: EventBase, sub: Subscription) -> bool:
	var scoping: StringName = event.get_scoping()

	if scoping == Scoping.WORLD_SHARED:
		return true

	if scoping == Scoping.PER_IMMORTAL:
		# If subscriber has no filter, deliver to all (e.g. player-only mechanics).
		if sub.scope_filter == &"":
			return true
		# Per-immortal events must have immortal_ref.
		var immortal_ref: Variant = event.get("immortal_ref")
		if immortal_ref == null:
			return true
		return immortal_ref == sub.scope_filter

	if scoping == Scoping.SCOPED_BY_AWARENESS:
		# TODO: implement awareness-scoped delivery when first awareness-scoped event is created.
		# For now, fall through and deliver to all subscribers.
		return true

	return true
