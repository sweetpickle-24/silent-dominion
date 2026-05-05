extends GutTest


# --- Helpers ---

# Minimal mock object for use as self_obj/target in rule contexts.
class MockEntity:
	extends Resource
	var value: int = 0
	var name: StringName = &""
	var kind: StringName = &""


func _make_rule(condition: String, id: StringName = &"test_rule") -> Rule:
	var rule := Rule.new()
	rule.id = id
	rule.condition = condition
	rule.base_delta = -10
	rule.attribution_tag = &"test_tag"
	return rule


func _make_context(self_obj: Object = null, target_obj: Object = null, event_obj: EventBase = null) -> RuleContext:
	var ctx := RuleContext.new()
	ctx.event = event_obj
	ctx.self_obj = self_obj
	ctx.target = target_obj
	ctx.world = WorldView.snapshot()
	ctx.helpers = (Engine.get_main_loop() as SceneTree).root.get_node("Helpers")
	return ctx


# --- Expression caching ---

func test_expression_caching_same_condition_parsed_once():
	var rule_a := _make_rule("true")
	var rule_b := _make_rule("true", &"rule_b")
	var ctx := _make_context()
	# Evaluate twice with same condition string
	RuleEvaluator.evaluate(rule_a, ctx)
	RuleEvaluator.evaluate(rule_b, ctx)
	# Cache should have exactly one entry for "true"
	assert_true(RuleEvaluator._expression_cache.has("true"),
		"Condition string should be in cache")
	assert_eq(RuleEvaluator._expression_cache.size(), 1,
		"Only one unique condition should be cached")


func test_expression_caching_different_conditions():
	var rule_a := _make_rule("true")
	var rule_b := _make_rule("false")
	var ctx := _make_context()
	RuleEvaluator.evaluate(rule_a, ctx)
	RuleEvaluator.evaluate(rule_b, ctx)
	assert_eq(RuleEvaluator._expression_cache.size(), 2,
		"Two different conditions should produce two cache entries")


# --- Truthy / falsy ---

func test_truthy_condition_returns_rule():
	var rule := _make_rule("true")
	var ctx := _make_context()
	var result = RuleEvaluator.evaluate(rule, ctx)
	assert_not_null(result, "Truthy condition should return non-null")
	assert_eq(result, rule, "Should return the rule itself")


func test_falsy_condition_returns_null():
	var rule := _make_rule("false")
	var ctx := _make_context()
	var result = RuleEvaluator.evaluate(rule, ctx)
	assert_null(result, "Falsy condition should return null")


func test_empty_condition_returns_null():
	var rule := _make_rule("")
	var ctx := _make_context()
	var result = RuleEvaluator.evaluate(rule, ctx)
	assert_null(result, "Empty condition should return null")


# --- Parse error ---

func test_parse_error_returns_null():
	var rule := _make_rule("this is not valid @@@ gdscript")
	var ctx := _make_context()
	var result = RuleEvaluator.evaluate(rule, ctx)
	assert_null(result, "Malformed condition should return null")


# --- Execute error ---

func test_execute_error_returns_null():
	# Reference a method that doesn't exist on self_obj
	var entity := MockEntity.new()
	var rule := _make_rule("self.nonexistent_method()")
	var ctx := _make_context(entity)
	var result = RuleEvaluator.evaluate(rule, ctx)
	assert_null(result, "Execute error should return null")


# --- Context variable resolution ---

func test_self_variable_resolves():
	var entity := MockEntity.new()
	entity.value = 10
	var rule := _make_rule("self.value > 5")
	var ctx := _make_context(entity)
	var result = RuleEvaluator.evaluate(rule, ctx)
	assert_not_null(result, "self.value > 5 should fire when value=10")


func test_self_variable_falsy():
	var entity := MockEntity.new()
	entity.value = 3
	var rule := _make_rule("self.value > 5")
	var ctx := _make_context(entity)
	var result = RuleEvaluator.evaluate(rule, ctx)
	assert_null(result, "self.value > 5 should not fire when value=3")


func test_target_variable_resolves():
	var target := MockEntity.new()
	target.kind = &"library"
	var rule := _make_rule('target.kind == "library"')
	var ctx := _make_context(null, target)
	var result = RuleEvaluator.evaluate(rule, ctx)
	assert_not_null(result, "target.kind == library should fire")


func test_world_variable_resolves():
	var rule := _make_rule('world.era == "ancient"')
	var ctx := _make_context()
	var result = RuleEvaluator.evaluate(rule, ctx)
	assert_not_null(result, "world.era should resolve to 'ancient' at day 0")


func test_event_variable_resolves():
	var event := GameDayTickedEvent.new()
	event.day = 42
	var rule := _make_rule("event.day == 42")
	var ctx := _make_context(null, null, event)
	var result = RuleEvaluator.evaluate(rule, ctx)
	assert_not_null(result, "event.day should resolve to 42")


func test_helpers_variable_resolves():
	var rule := _make_rule('"scholar" in helpers.scholar_professions()')
	var ctx := _make_context()
	var result = RuleEvaluator.evaluate(rule, ctx)
	assert_not_null(result, "helpers.scholar_professions() should contain 'scholar'")


func test_unqualified_self_access():
	# Per C3: Expression.execute() with base_object = self_obj allows
	# unqualified access like "value > 5" instead of "self.value > 5"
	var entity := MockEntity.new()
	entity.value = 10
	var rule := _make_rule("value > 5")
	var ctx := _make_context(entity)
	var result = RuleEvaluator.evaluate(rule, ctx)
	assert_not_null(result, "Unqualified 'value > 5' should resolve on self_obj")


# --- evaluate_predicate ---

func test_predicate_truthy():
	var ctx := _make_context()
	var result: bool = RuleEvaluator.evaluate_predicate("true", ctx)
	assert_true(result, "Predicate 'true' should return true")


func test_predicate_falsy():
	var ctx := _make_context()
	var result: bool = RuleEvaluator.evaluate_predicate("false", ctx)
	assert_false(result, "Predicate 'false' should return false")


func test_predicate_empty_returns_false():
	var ctx := _make_context()
	var result: bool = RuleEvaluator.evaluate_predicate("", ctx)
	assert_false(result, "Empty predicate should return false")


func test_predicate_with_context():
	var entity := MockEntity.new()
	entity.value = 42
	var ctx := _make_context(entity)
	var result: bool = RuleEvaluator.evaluate_predicate("self.value == 42", ctx)
	assert_true(result, "Predicate should resolve self.value")


# --- Cleanup ---

func before_each():
	# Clear the expression cache between tests so caching tests are isolated
	RuleEvaluator._expression_cache.clear()
