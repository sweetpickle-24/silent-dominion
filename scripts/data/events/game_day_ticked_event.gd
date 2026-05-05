class_name GameDayTickedEvent
extends EventBase

@export var day: int = 0
@export var year: int = 0
@export var era: StringName = &"ancient"
@export var season: StringName = &"spring"
@export var year_changed: bool = false

# Inherits get_delivery_mode() -> &"synchronous" from EventBase.
# Inherits get_scoping() -> &"world_shared" from EventBase.
# Override these methods in subclasses that need different delivery/scoping.
