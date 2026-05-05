extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

# Expression cache: condition_string -> parsed Expression instance.
# Each rule's parse cost is paid once; subsequent evaluations only execute().
var _expression_cache: Dictionary = {}

var _logger: Node


func _ready() -> void:
	_logger = get_node("/root/Logger")
	_logger.info(LogChannels.RULE_EVAL, "RuleEvaluator ready")


# Evaluate a rule against a context. Returns the Rule if condition is truthy, else null.
# Per C3: Expression.execute() receives context.self_obj as base_object so unqualified
# access in conditions (e.g. "disposition_baseline") resolves on self.
func evaluate(rule: Rule, context: RuleContext) -> Variant:
	if rule.condition.is_empty():
		return null
	var expr: Expression = _get_or_parse(rule.condition)
	if expr == null:
		return null
	var result: Variant = expr.execute(context.variable_values(), context.self_obj)
	if expr.has_execute_failed():
		_logger.error(LogChannels.RULE_EVAL, "Rule %s execute failed: %s" % [rule.id, expr.get_error_text()])
		return null
	if not result:
		return null
	if _logger.enabled_for(LogChannels.RULE_EVAL, _LOG_DEBUG):
		_logger.debug(LogChannels.RULE_EVAL, "Rule fired: %s" % rule.id)
	return rule


# Evaluate a bare condition string as a boolean predicate.
# Used by Similarity for required_conditions / forbidden_conditions, and by
# TimeKeeper for era-transition checks.
func evaluate_predicate(condition_string: String, context: RuleContext) -> bool:
	if condition_string.is_empty():
		return false
	var expr: Expression = _get_or_parse(condition_string)
	if expr == null:
		return false
	var result: Variant = expr.execute(context.variable_values(), context.self_obj)
	if expr.has_execute_failed():
		_logger.error(LogChannels.RULE_EVAL, "Predicate execute failed: %s" % expr.get_error_text())
		return false
	return bool(result)


# --- Internal ---

func _get_or_parse(condition_string: String) -> Expression:
	if _expression_cache.has(condition_string):
		return _expression_cache[condition_string]
	var expr := Expression.new()
	var error: Error = expr.parse(condition_string, RuleContext.VARIABLE_NAMES)
	if error != OK:
		_logger.error(LogChannels.RULE_EVAL, "Expression parse failed: %s | condition: %s" % [expr.get_error_text(), condition_string])
		return null
	_expression_cache[condition_string] = expr
	return expr
