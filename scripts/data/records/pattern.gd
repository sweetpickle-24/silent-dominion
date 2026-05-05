class_name Pattern
extends Resource

# === Identity ===
@export var id: StringName
@export var name: String
@export var category: StringName
@export var description: String

# === Profile template ===
@export_multiline var required_conditions: String = ""
@export var attribute_templates: Array[AttributeTemplate] = []
@export_multiline var forbidden_conditions: String = ""

# === Approach ===
@export var approach_steps: Array[ApproachStep] = []

# === Provenance and learning ===
@export var learned_from_event_id: StringName = &""
@export var learned_at_day: int = 0
@export var region_scope: StringName = &""
@export var era: StringName = &"ancient"

# === Track record ===
@export var success_count: int = 0
@export var failure_count: int = 0
@export var last_validated_day: int = 0
@export var last_misfired_day: int = -1

# === Staleness ===
@export var staleness_state: StringName = StalenessValues.FRESH

# === Library-corruption tracking ===
@export var suspected_corruption_level: int = 0
@export var corruption_evidence: Array[StringName] = []

# === Tags ===
@export var tags: PackedStringArray = PackedStringArray()


# === Methods ===

func compute_similarity(context: RuleContext) -> float:
	return Similarity.compute(self, context)


func is_automation_eligible() -> bool:
	if staleness_state == StalenessValues.STALE:
		return false
	if suspected_corruption_level >= 80:
		return false
	return true


func mark_validated(day: int) -> void:
	last_validated_day = day
	if staleness_state == StalenessValues.AGING:
		staleness_state = StalenessValues.FRESH
	success_count += 1


func mark_misfired(day: int) -> void:
	last_misfired_day = day
	failure_count += 1


func total_applications() -> int:
	return success_count + failure_count


func empirical_success_rate() -> float:
	if total_applications() == 0:
		return 0.5
	return float(success_count) / float(total_applications())
