class_name FirstContactState
extends Resource

@export var immortal_a_id: StringName = &""  # alphabetical-first
@export var immortal_b_id: StringName = &""
@export var stage: StringName = &"unaware"  # &"unaware" | &"a_aware" | &"b_aware" | &"mutual_aware" | &"contact_initiated" | &"contact_responded" | &"channel_open"
@export var first_aware_day: int = -1
@export var contact_initiated_day: int = -1
@export var contact_initiator_id: StringName = &""
@export var opening_gesture_kind: StringName = &""  # &"shared_intelligence" | &"host_courtesy" | &"gifted_pattern"
@export var opening_gesture_response: StringName = &""  # &"reciprocated" | &"ignored" | &"hostile"
