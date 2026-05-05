class_name Rule
extends Resource

@export var id: StringName
@export_multiline var condition: String
@export var base_delta: int = 0
@export var attribution_tag: StringName = &""
# TODO: @export var scale_modifiers: Array[ScaleModifier] = []
#   Schema TBD — see Gap 2 stacking modifier composition (T4-13).
@export var priority: int = 0
@export var event_type_filter: StringName = &""
