extends GutTest


# --- Helpers ---

class MockTarget:
	extends Resource
	var kind: StringName = &""
	var profession: StringName = &""
	var ambition: int = 0
	var region: StringName = &""
	var tags: Array = []


func _make_pattern(overrides: Dictionary = {}) -> Pattern:
	var p := Pattern.new()
	p.id = overrides.get("id", &"test_pattern")
	p.category = overrides.get("category", PatternCategories.BRIBE)
	p.era = overrides.get("era", &"ancient")
	p.region_scope = overrides.get("region_scope", &"")
	p.required_conditions = overrides.get("required_conditions", "")
	p.forbidden_conditions = overrides.get("forbidden_conditions", "")
	p.suspected_corruption_level = overrides.get("corruption", 0)
	p.last_validated_day = overrides.get("last_validated_day", 0)
	if overrides.has("attribute_templates"):
		p.attribute_templates.clear()
		for t in overrides["attribute_templates"]:
			p.attribute_templates.append(t)
	return p


func _make_attr(path: String, expected: Variant, comparison: StringName = ComparisonValues.EQUALS, weight: float = 1.0, tolerance: float = 0.0) -> AttributeTemplate:
	var t := AttributeTemplate.new()
	t.attribute_path = path
	t.expected_value = expected
	t.comparison = comparison
	t.weight = weight
	t.numeric_tolerance = tolerance
	return t


func _make_context(target_obj: Resource = null, era: StringName = &"ancient") -> RuleContext:
	var ctx := RuleContext.new()
	ctx.target = target_obj
	ctx.world = WorldView.snapshot()
	ctx.world.era = era
	ctx.helpers = (Engine.get_main_loop() as SceneTree).root.get_node("Helpers")
	return ctx


# --- Required / forbidden conditions ---

func test_required_false_returns_zero():
	var p := _make_pattern({"required_conditions": "false"})
	var ctx := _make_context()
	assert_eq(Similarity.compute(p, ctx), 0.0)


func test_required_true_no_attrs_returns_one():
	var p := _make_pattern({"required_conditions": "true"})
	var ctx := _make_context()
	assert_eq(Similarity.compute(p, ctx), 1.0)


func test_forbidden_true_returns_zero():
	var p := _make_pattern({"forbidden_conditions": "true"})
	var ctx := _make_context()
	assert_eq(Similarity.compute(p, ctx), 0.0)


func test_forbidden_false_no_attrs_returns_one():
	var p := _make_pattern({"forbidden_conditions": "false"})
	var ctx := _make_context()
	assert_eq(Similarity.compute(p, ctx), 1.0)


# --- Empty templates ---

func test_empty_attrs_no_conditions_returns_one():
	var p := _make_pattern()
	var ctx := _make_context()
	assert_eq(Similarity.compute(p, ctx), 1.0)


# --- Attribute matching ---

func test_single_attr_exact_match():
	var target := MockTarget.new()
	target.kind = &"library"
	var p := _make_pattern({
		"attribute_templates": [_make_attr("target.kind", &"library")],
	})
	var ctx := _make_context(target)
	assert_eq(Similarity.compute(p, ctx), 1.0)


func test_single_attr_exact_miss():
	var target := MockTarget.new()
	target.kind = &"temple"
	var p := _make_pattern({
		"attribute_templates": [_make_attr("target.kind", &"library")],
	})
	var ctx := _make_context(target)
	assert_eq(Similarity.compute(p, ctx), 0.0)


func test_two_attrs_equal_weight_one_match():
	var target := MockTarget.new()
	target.kind = &"library"
	target.profession = &"warrior"
	var p := _make_pattern({
		"attribute_templates": [
			_make_attr("target.kind", &"library"),
			_make_attr("target.profession", &"scholar"),
		],
	})
	var ctx := _make_context(target)
	assert_almost_eq(Similarity.compute(p, ctx), 0.5, 0.001)


func test_two_attrs_weighted_heavy_match():
	var target := MockTarget.new()
	target.kind = &"library"
	target.profession = &"warrior"
	var p := _make_pattern({
		"attribute_templates": [
			_make_attr("target.kind", &"library", ComparisonValues.EQUALS, 3.0),
			_make_attr("target.profession", &"scholar", ComparisonValues.EQUALS, 1.0),
		],
	})
	var ctx := _make_context(target)
	assert_almost_eq(Similarity.compute(p, ctx), 0.75, 0.001)


func test_two_attrs_weighted_heavy_miss():
	var target := MockTarget.new()
	target.kind = &"temple"
	target.profession = &"scholar"
	var p := _make_pattern({
		"attribute_templates": [
			_make_attr("target.kind", &"library", ComparisonValues.EQUALS, 3.0),
			_make_attr("target.profession", &"scholar", ComparisonValues.EQUALS, 1.0),
		],
	})
	var ctx := _make_context(target)
	assert_almost_eq(Similarity.compute(p, ctx), 0.25, 0.001)


func test_numeric_near_within_tolerance():
	var target := MockTarget.new()
	target.ambition = 62
	var p := _make_pattern({
		"attribute_templates": [
			_make_attr("target.ambition", 60, ComparisonValues.NUMERIC_NEAR, 1.0, 5.0),
		],
	})
	var ctx := _make_context(target)
	assert_eq(Similarity.compute(p, ctx), 1.0)


func test_numeric_near_outside_tolerance():
	var target := MockTarget.new()
	target.ambition = 70
	var p := _make_pattern({
		"attribute_templates": [
			_make_attr("target.ambition", 60, ComparisonValues.NUMERIC_NEAR, 1.0, 5.0),
		],
	})
	var ctx := _make_context(target)
	assert_eq(Similarity.compute(p, ctx), 0.0)


# --- Era modifier ---

func test_era_same():
	var p := _make_pattern({"era": &"ancient"})
	var ctx := _make_context(null, &"ancient")
	assert_eq(Similarity.compute(p, ctx), 1.0)


func test_era_one_off():
	var p := _make_pattern({"era": &"ancient"})
	var ctx := _make_context(null, &"classical_collapse")
	assert_almost_eq(Similarity.compute(p, ctx), 0.7, 0.001)


func test_era_two_off():
	var p := _make_pattern({"era": &"ancient"})
	var ctx := _make_context(null, &"medieval")
	assert_almost_eq(Similarity.compute(p, ctx), 0.4, 0.001)


func test_era_three_off():
	var p := _make_pattern({"era": &"ancient"})
	var ctx := _make_context(null, &"early_modern")
	assert_almost_eq(Similarity.compute(p, ctx), 0.2, 0.001)


# --- Region modifier ---

func test_region_empty_scope():
	var p := _make_pattern({"region_scope": &""})
	var ctx := _make_context()
	assert_eq(Similarity.compute(p, ctx), 1.0)


func test_region_same():
	var target := MockTarget.new()
	target.region = &"attica"
	var p := _make_pattern({"region_scope": &"attica"})
	var ctx := _make_context(target)
	assert_eq(Similarity.compute(p, ctx), 1.0)


func test_region_different_with_stubs():
	# Helpers stubs return false for adjacent/cultural sphere, so lands at 0.3.
	var target := MockTarget.new()
	target.region = &"phocis"
	var p := _make_pattern({"region_scope": &"attica"})
	var ctx := _make_context(target)
	assert_almost_eq(Similarity.compute(p, ctx), 0.3, 0.001)


# --- Corruption penalty ---

func test_corruption_zero():
	var p := _make_pattern({"corruption": 0})
	var ctx := _make_context()
	assert_eq(Similarity.compute(p, ctx), 1.0)


func test_corruption_100():
	var p := _make_pattern({"corruption": 100})
	var ctx := _make_context()
	assert_almost_eq(Similarity.compute(p, ctx), 0.5, 0.001)


func test_corruption_50():
	var p := _make_pattern({"corruption": 50})
	var ctx := _make_context()
	assert_almost_eq(Similarity.compute(p, ctx), 0.75, 0.001)


# --- Composed ---

func test_composed_full_pipeline():
	# required true + forbidden false + 2 attributes (one match, one miss, equal weight)
	# + era 1 off (classical vs ancient) + corruption 50
	# raw_similarity = 0.5, era_mod = 0.7, region_mod = 1.0 (no region scope), corruption = 0.75
	# result = 0.5 * 0.7 * 1.0 * 0.75 = 0.2625
	var target := MockTarget.new()
	target.kind = &"library"
	target.profession = &"warrior"
	var p := _make_pattern({
		"required_conditions": "true",
		"forbidden_conditions": "false",
		"era": &"ancient",
		"corruption": 50,
		"attribute_templates": [
			_make_attr("target.kind", &"library"),
			_make_attr("target.profession", &"scholar"),
		],
	})
	var ctx := _make_context(target, &"classical_collapse")
	assert_almost_eq(Similarity.compute(p, ctx), 0.2625, 0.001)
