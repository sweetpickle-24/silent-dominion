class_name MemoirsLibrary
extends Resource

@export var immortal_id: StringName = &""
@export var patterns: Array[Pattern] = []

# TODO Step 7+: active_automations: Array[ActiveAutomation]
# TODO T4-8: library_corruption_state: LibraryCorruptionState


func get_pattern(pattern_id: StringName) -> Pattern:
	for p in patterns:
		if p.id == pattern_id:
			return p
	return null


func patterns_by_category(category: StringName) -> Array[Pattern]:
	var matches: Array[Pattern] = []
	for p in patterns:
		if p.category == category:
			matches.append(p)
	return matches
