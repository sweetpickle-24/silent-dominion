class_name RouteRecord
extends Resource

@export var id: StringName
@export var name: String
@export var kind: StringName = &"overland"
@export var tier: StringName = &"regional"
@export var waypoints: Array[StringName] = []
@export var line_thickness: float = 2.0
