# Per Family 9 spec, this should be per_tick_batched at scale. Using synchronous
# at substep 11.1 because EventBus's batched dispatch path is still stubbed and
# 20 places don't justify implementing it now. Revisit when high-volume per-place
# events ship (Trace mechanic, substep 11.8).
class_name PlaceTickedEvent
extends EventBase

@export var place_id: StringName = &""
@export var day: int = 0
@export var tax_yield_today: int = 0
@export var population_delta: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"world_shared"
