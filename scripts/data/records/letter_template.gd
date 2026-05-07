class_name LetterTemplate
extends Resource

@export var id: StringName = &""
@export var triggering_event_class: StringName = &""
@export var sender_kind: StringName = &"system"

@export var subject_variants: Array[String] = []
@export var body_variants: Array[String] = []

@export var content_category: StringName = &""
@export var is_authored: bool = false
