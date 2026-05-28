class_name ReligionRecord
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: StringName = &"religion"  # &"religion" | &"ideology" | &"hybrid"
@export var founded_day: int = -1
@export var era_of_emergence: StringName = &"ancient"
@export var parent_religion_id: StringName = &""
@export var schism_child_ids: Array[StringName] = []

# Six §25.1 attributes (0-100)
@export var doctrinal_rigidity: int = 50
@export var institutional_strength: int = 30
@export var popular_depth: int = 40
@export var ecumenical_openness: int = 50
@export var reform_potential: int = 10
@export var geographic_concentration_score: int = 50

@export var lifecycle_phase: StringName = &"consolidation"  # emergence/consolidation/dominance/fracture/decline/extinct

# Liturgical language association
@export var liturgical_language_id: StringName = &""


func is_active() -> bool:
	return lifecycle_phase != &"extinct"
