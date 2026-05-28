class_name TreatyPrimitive
extends Resource

# Identity
@export var id: StringName = &""
@export var category: StringName = &""  # &"information" | &"resource" | &"operational" | &"restraint" | &"term"

# Specification
@export var kind: StringName = &""  # subcategory: &"share_intelligence", &"transfer_silver", etc.
@export var parameters: Dictionary = {}

# Direction
@export var direction: StringName = &"two_way"  # &"one_way" | &"two_way" | &"from_them"

# Human-readable description for UI and logs
@export var description: String = ""
