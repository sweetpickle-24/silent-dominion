# Family 10 spec calls for queued delivery. Using synchronous at substep 11.4
# because EventBus's queued path is stubbed and consumers are test-only.
# Revisit when the queued dispatch path is implemented (likely substep 11.5+
# when UI consumers need it, or a dedicated infrastructure substep).
class_name LetterArrivedInInboxEvent
extends EventBase

@export var letter_id: StringName = &""
@export var immortal_id: StringName = &""
@export var subject: String = ""
@export var day_received: int = 0

func get_delivery_mode() -> StringName:
	return &"synchronous"

func get_scoping() -> StringName:
	return &"per_immortal"
