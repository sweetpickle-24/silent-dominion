# B4 specifies DELIVERY_MODE and SCOPING as const StringName on each event class.
# GDScript 4.6 does not allow const (or static var) redeclaration in subclasses —
# "The member 'X' already exists in parent class" is a hard parse error.
# Workaround: virtual methods get_delivery_mode() / get_scoping() that subclasses
# override. Semantically equivalent; the EventBus calls event.get_delivery_mode()
# instead of event_class.DELIVERY_MODE.
# Pending vault ratification as a formal deviation from B4.
class_name EventBase
extends Resource

@export var fired_at_day: int = -1
@export var fired_at_tick_index: int = -1

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
