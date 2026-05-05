class_name SaveFailedEvent
extends EventBase

@export var error_code: int = 0
@export var path: String = ""

# Inherits get_delivery_mode() -> &"synchronous" from EventBase.
# Inherits get_scoping() -> &"world_shared" from EventBase.
