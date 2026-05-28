class_name ReputationRecord
extends Resource

@export var immortal_id: StringName = &""
@export var reputation_score: int = 50  # 0-100, starts neutral
@export var treaties_honoured: int = 0
@export var treaties_broken: int = 0
@export var treaties_signed: int = 0
@export var treaties_active: int = 0

# History of reputation events: array of {day, delta, reason}
@export var events: Array = []

# Per-observer adjustments — different societies may have slightly different views
@export var per_observer_adjustments: Dictionary = {}  # observer_immortal_id -> int


func get_reputation_as_seen_by(observer_immortal_id: StringName) -> int:
	var adjustment: int = per_observer_adjustments.get(observer_immortal_id, 0)
	return clampi(reputation_score + adjustment, 0, 100)


func apply_delta(delta: int, day: int, reason: String) -> void:
	reputation_score = clampi(reputation_score + delta, 0, 100)
	events.append({"day": day, "delta": delta, "reason": reason})
