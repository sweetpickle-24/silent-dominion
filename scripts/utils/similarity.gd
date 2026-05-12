# Similarity is a class_name RefCounted with static methods, not an autoload.
# B3 §3.1 locks the autoload list at 11 entries; Similarity is not among them.
# C1's "autoload as Similarity" phrasing predates the autoload list lock and is stale.
class_name Similarity
extends RefCounted

# Era ordering for distance calculation.
const _ERA_ORDER: Array = [
	&"ancient", &"classical_collapse", &"medieval", &"early_modern", &"modern",
]


# Per C1 §5.3 algorithm. Eight steps. Pure static method.
static func compute(pattern: Pattern, context: RuleContext) -> float:
	# Step 1: required conditions
	if pattern.required_conditions != "":
		var rule_evaluator: Node = _get_autoload(&"RuleEvaluator")
		var required_holds: bool = rule_evaluator.evaluate_predicate(pattern.required_conditions, context)
		if not required_holds:
			return 0.0

	# Step 2: forbidden conditions
	if pattern.forbidden_conditions != "":
		var rule_evaluator: Node = _get_autoload(&"RuleEvaluator")
		var forbidden_holds: bool = rule_evaluator.evaluate_predicate(pattern.forbidden_conditions, context)
		if forbidden_holds:
			return 0.0

	# Step 3: category match — caller's responsibility per C1. Similarity does NOT check.

	# Steps 4-5: weighted attribute matching
	var raw_similarity: float = 1.0
	if not pattern.attribute_templates.is_empty():
		var total_weight: float = 0.0
		var matched_weight: float = 0.0
		for template: AttributeTemplate in pattern.attribute_templates:
			total_weight += template.weight
			var actual: Variant = _resolve_path(template.attribute_path, context)
			var fit: float = _compare(actual, template.expected_value, template.comparison, template.numeric_tolerance)
			matched_weight += fit * template.weight
		raw_similarity = matched_weight / total_weight if total_weight > 0.0 else 0.0

	# Step 6: era and region modifiers
	var era_mod: float = _era_modifier(pattern, context)
	var region_mod: float = _region_modifier(pattern, context)

	# Step 7: provenance penalty captured by era and region modifiers per C1

	# Step 8: corruption penalty
	var corruption_penalty: float = 1.0 - (pattern.suspected_corruption_level / 100.0) * 0.5

	return raw_similarity * era_mod * region_mod * corruption_penalty


static func _get_autoload(name: StringName) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(NodePath(name))


static func _resolve_path(path: String, context: RuleContext) -> Variant:
	var parts: PackedStringArray = path.split(".")
	var current: Variant = context.get_variable(StringName(parts[0]))
	for i in range(1, parts.size()):
		if current == null:
			return null
		current = current.get(parts[i])
	return current


static func _compare(actual: Variant, expected: Variant, comparison: StringName, tolerance: float) -> float:
	if actual == null:
		return 0.0

	match comparison:
		ComparisonValues.EQUALS:
			return 1.0 if actual == expected else 0.0
		ComparisonValues.NOT_EQUALS:
			return 1.0 if actual != expected else 0.0
		ComparisonValues.NUMERIC_GTE:
			return 1.0 if float(actual) >= float(expected) else 0.0
		ComparisonValues.NUMERIC_LTE:
			return 1.0 if float(actual) <= float(expected) else 0.0
		ComparisonValues.NUMERIC_NEAR:
			return 1.0 if absf(float(actual) - float(expected)) <= tolerance else 0.0
		ComparisonValues.NUMERIC_RANGE:
			# expected is [min, max]
			if expected is Array and expected.size() == 2:
				var val: float = float(actual)
				return 1.0 if val >= float(expected[0]) and val <= float(expected[1]) else 0.0
			return 0.0
		ComparisonValues.STRING_CONTAINS:
			return 1.0 if str(actual).contains(str(expected)) else 0.0
		ComparisonValues.SET_MEMBERSHIP:
			# actual is in expected (Array)
			if expected is Array:
				return 1.0 if actual in expected else 0.0
			return 0.0
		ComparisonValues.SET_OVERLAP:
			# any element of actual in expected
			if actual is Array and expected is Array:
				for item in actual:
					if item in expected:
						return 1.0
			return 0.0
		_:
			return 0.0


static func _era_modifier(pattern: Pattern, context: RuleContext) -> float:
	var current_era: StringName = context.world.era if context.world != null else &""
	if pattern.era == current_era:
		return 1.0
	var distance: int = _era_distance(pattern.era, current_era)
	if distance == 1:
		return 0.7
	if distance == 2:
		return 0.4
	return 0.2


static func _region_modifier(pattern: Pattern, context: RuleContext) -> float:
	if pattern.region_scope == &"":
		return 1.0
	var current_region: StringName = &""
	if context.target != null:
		var region_val: Variant = context.target.get("province")
		if region_val == null:
			region_val = context.target.get("region")  # backward compat
		if region_val != null:
			current_region = region_val
	if pattern.region_scope == current_region:
		return 1.0
	# Helpers stubs return false at Step 6; intermediate bands (0.85, 0.6) light up
	# when Region mechanic + adjacency data ship.
	var helpers: Node = _get_autoload(&"Helpers")
	if helpers.regions_adjacent(pattern.region_scope, current_region):
		return 0.85
	if helpers.regions_same_cultural_sphere(pattern.region_scope, current_region):
		return 0.6
	return 0.3


static func _era_distance(era_a: StringName, era_b: StringName) -> int:
	var idx_a: int = _ERA_ORDER.find(era_a)
	var idx_b: int = _ERA_ORDER.find(era_b)
	if idx_a == -1 or idx_b == -1:
		return 3  # unknown era treated as maximally distant
	return absi(idx_a - idx_b)
