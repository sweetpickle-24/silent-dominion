extends GutTest

# Test event class that uses queued delivery.
class QueuedTestEvent:
	extends EventBase
	var payload: String = ""
	func get_delivery_mode() -> StringName:
		return &"queued"
	func get_scoping() -> StringName:
		return &"world_shared"

var _received: Array = []
var _sub


func before_each():
	_received.clear()
	var eb: Node = get_node("/root/EventBus")
	_sub = eb.subscribe(
		QueuedTestEvent,
		func(e): _received.append(e.payload), 100)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if _sub:
		eb.unsubscribe(_sub)
		_sub = null
	# Clear any leftover queued events
	eb._queued_events.clear()


func test_queued_does_not_fire_immediately():
	var eb: Node = get_node("/root/EventBus")
	var event := QueuedTestEvent.new()
	event.payload = "hello"
	eb.dispatch(event)
	assert_eq(_received.size(), 0, "Queued event should NOT fire on dispatch")


func test_drain_fires_queued():
	var eb: Node = get_node("/root/EventBus")
	var event := QueuedTestEvent.new()
	event.payload = "world"
	eb.dispatch(event)
	assert_eq(_received.size(), 0)
	eb._drain_queued()
	assert_eq(_received.size(), 1)
	assert_eq(_received[0], "world")


func test_drain_fires_in_priority_order():
	var eb: Node = get_node("/root/EventBus")
	var received_order: Array = []
	var sub_low = eb.subscribe(QueuedTestEvent, func(e): received_order.append("low"), 10)
	var sub_high = eb.subscribe(QueuedTestEvent, func(e): received_order.append("high"), 200)
	var event := QueuedTestEvent.new()
	eb.dispatch(event)
	eb._drain_queued()
	# Priority 10 fires before 100 fires before 200
	assert_eq(received_order[0], "low")
	assert_eq(received_order[-1], "high")
	eb.unsubscribe(sub_low)
	eb.unsubscribe(sub_high)


func test_empty_drain_is_idempotent():
	var eb: Node = get_node("/root/EventBus")
	eb._drain_queued()
	assert_eq(_received.size(), 0, "Empty drain should do nothing")
	eb._drain_queued()
	assert_eq(_received.size(), 0)


func test_end_of_tick_drains_queue():
	var eb: Node = get_node("/root/EventBus")
	var event := QueuedTestEvent.new()
	event.payload = "tick_drain"
	eb.dispatch(event)
	eb.end_of_tick(1)
	assert_eq(_received.size(), 1)
	assert_eq(_received[0], "tick_drain")
