class_name RulerAI
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _world_registry: Node
var _immortal_registry: Node
var _rule_evaluator: Node
var _kingdom_node: Node

var _ruler_states: Dictionary = {}       # StringName kingdom_id -> RulerState
var _runners: Dictionary = {}            # StringName kingdom_id -> RuleListRunner
var _rules_baseline: Array = []          # rules every ruler runs
var _rules_full_fidelity: Array = []     # additional rules for full-fidelity rulers
var _tick_sub
var _reactive_subs: Array = []

# Succession risk thresholds (ruler age in days)
const SUCCESSION_AGE_MODERATE: int = 18250   # ~50 years
const SUCCESSION_AGE_HIGH: int = 21900       # ~60 years
const SUCCESSION_AGE_CRITICAL: int = 25550   # ~70 years


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_world_registry = get_node("/root/WorldRegistry")
	_immortal_registry = get_node("/root/ImmortalRegistry")
	_rule_evaluator = get_node("/root/RuleEvaluator")
	_kingdom_node = get_node_or_null("../Kingdom")
	_load_rules()
	_initialize_ruler_states()
	_tick_sub = _event_bus.subscribe(
		preload("res://scripts/data/events/game_day_ticked_event.gd"),
		Callable(self, "_on_game_day_ticked"),
		160, &"", EndOfTickPhases.WORLD_SHARED,
	)
	_wire_reactive_subscriptions()
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"ruler_ai_state",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)
	_logger.info(LogChannels.RULER_AI, "RulerAI ready", {
		"rulers": _ruler_states.size(),
		"baseline_rules": _rules_baseline.size(),
		"full_fidelity_rules": _rules_full_fidelity.size(),
	})


func _load_rules() -> void:
	var dir := DirAccess.open("res://data/rules/ruler_ai/")
	if dir == null:
		_logger.info(LogChannels.RULER_AI, "No data/rules/ruler_ai/ — no ruler rules loaded")
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var resource = ResourceLoader.load("res://data/rules/ruler_ai/" + fname)
			if resource is SocietyAIRule:
				if resource.rule_tier == &"full_fidelity":
					_rules_full_fidelity.append(resource)
				else:
					_rules_baseline.append(resource)
		fname = dir.get_next()
	dir.list_dir_end()
	_rules_baseline.sort_custom(func(a: SocietyAIRule, b: SocietyAIRule) -> bool: return a.priority < b.priority)
	_rules_full_fidelity.sort_custom(func(a: SocietyAIRule, b: SocietyAIRule) -> bool: return a.priority < b.priority)


func _initialize_ruler_states() -> void:
	if _kingdom_node == null:
		return
	for kid: StringName in _kingdom_node.all_kingdom_ids():
		_ensure_ruler_state(kid)


func _ensure_ruler_state(kingdom_id: StringName) -> void:
	if _ruler_states.has(kingdom_id):
		return
	if _kingdom_node == null:
		return
	var k: KingdomRecord = _kingdom_node.get_kingdom(kingdom_id)
	if k == null:
		return
	var state := RulerState.new()
	state.ruler_character_id = k.ruler_character_id
	state.kingdom_id = kingdom_id
	state.goal_weights = {
		&"maintain_power": 80,
		&"secure_succession": 30,
		&"protect_realm": 60,
		&"expand_influence": 40,
	}
	state.fidelity = &"low"
	_ruler_states[kingdom_id] = state
	_runners[kingdom_id] = RuleListRunner.new()
	for rule: SocietyAIRule in _rules_baseline:
		_runners[kingdom_id].ensure_rule_state(rule.id)
	for rule: SocietyAIRule in _rules_full_fidelity:
		_runners[kingdom_id].ensure_rule_state(rule.id)


func _wire_reactive_subscriptions() -> void:
	var reactive_events: Array = [
		preload("res://scripts/data/events/kingdom_treasury_condition_changed_event.gd"),
		preload("res://scripts/data/events/kingdom_unrest_threshold_crossed_event.gd"),
	]
	for event_class in reactive_events:
		var sub = _event_bus.subscribe(
			event_class,
			Callable(self, "_on_reactive_event"),
			260, &"", EndOfTickPhases.WORLD_SHARED,
		)
		_reactive_subs.append(sub)


# --- Per-tick evaluation ---

func _on_game_day_ticked(event: GameDayTickedEvent) -> void:
	for kid: StringName in _ruler_states.keys():
		_evaluate_ruler(kid, event.day)
	_check_succession_risks(event.day)


func _evaluate_ruler(kingdom_id: StringName, day: int) -> void:
	var state: RulerState = _ruler_states.get(kingdom_id, null)
	if state == null:
		return
	var runner: RuleListRunner = _runners.get(kingdom_id, null)
	if runner == null:
		return
	# Determine fidelity
	_update_fidelity(state, kingdom_id)
	# Build context
	var context: RuleContext = _build_ruler_context(state, kingdom_id, day)
	# Select rules based on fidelity
	var rules: Array = _rules_baseline.duplicate()
	if state.fidelity == &"full":
		rules.append_array(_rules_full_fidelity)
		rules.sort_custom(func(a: SocietyAIRule, b: SocietyAIRule) -> bool: return a.priority < b.priority)
	# Evaluate — one decision per ruler per tick
	runner.evaluate_rules(
		rules, day, context, _rule_evaluator,
		func(rule: SocietyAIRule) -> bool: return _fire_decision(rule, state, kingdom_id, day),
		true,
	)


func _on_reactive_event(event: EventBase) -> void:
	var day: int = _time_keeper.current_day
	var kingdom_id: StringName = &""
	if event is KingdomTreasuryConditionChangedEvent:
		kingdom_id = event.kingdom_id
	elif event is KingdomUnrestThresholdCrossedEvent:
		kingdom_id = event.kingdom_id
	if kingdom_id == &"":
		return
	var state: RulerState = _ruler_states.get(kingdom_id, null)
	var runner: RuleListRunner = _runners.get(kingdom_id, null)
	if state == null or runner == null:
		return
	var context: RuleContext = _build_ruler_context(state, kingdom_id, day)
	context.event = event
	var rules: Array = _rules_baseline.duplicate()
	if state.fidelity == &"full":
		rules.append_array(_rules_full_fidelity)
	runner.evaluate_reactive(
		rules, event, day, context, _rule_evaluator,
		func(rule: SocietyAIRule) -> bool: return _fire_decision(rule, state, kingdom_id, day),
	)


# --- Context building ---
# self = ruler CharacterRecord (self.ambition, self.paranoia, etc.)
# target = KingdomRecord (target.treasury_condition, target.unrest, target.tax_level, etc.)

func _build_ruler_context(state: RulerState, kingdom_id: StringName, day: int) -> RuleContext:
	var ruler_char: CharacterRecord = _immortal_registry.get_character_record_any(state.ruler_character_id)
	var kingdom: KingdomRecord = null
	if _kingdom_node != null:
		kingdom = _kingdom_node.get_kingdom(kingdom_id)
	var ctx := RuleContext.new()
	ctx.self_obj = ruler_char
	ctx.target = kingdom
	ctx.world = WorldView.snapshot_for(day, _time_keeper.current_era)
	ctx.helpers = get_node_or_null("/root/Helpers")
	return ctx


# --- Decision firing ---

func _fire_decision(rule: SocietyAIRule, state: RulerState, kingdom_id: StringName, day: int) -> bool:
	var decision: StringName = rule.action_kind
	var params: Dictionary = rule.action_params
	_apply_decision(decision, params, kingdom_id, day)
	state.record_decision(decision, day, &"success")
	var event := RulerDecisionMadeEvent.new()
	event.kingdom_id = kingdom_id
	event.ruler_character_id = state.ruler_character_id
	event.decision = decision
	event.params = params
	event.day = day
	_event_bus.dispatch(event)
	if _logger.enabled_for(LogChannels.RULER_AI, _LOG_DEBUG):
		_logger.debug(LogChannels.RULER_AI, "Ruler decision", {
			"kingdom": kingdom_id, "decision": decision,
		})
	return true


func _apply_decision(decision: StringName, params: Dictionary, kingdom_id: StringName, day: int) -> void:
	if _kingdom_node == null:
		return
	match decision:
		&"adjust_tax_level":
			var delta: int = params.get("delta", 0)
			_kingdom_node.apply_tax_level_change(kingdom_id, delta, day)
		&"raise_army":
			var amount: int = params.get("amount", 50)
			_kingdom_node.apply_army_change(kingdom_id, amount)
		&"disband_army":
			var amount: int = params.get("amount", 50)
			_kingdom_node.apply_army_change(kingdom_id, -amount)
		&"service_debt":
			var amount: int = params.get("amount", 100)
			var k: KingdomRecord = _kingdom_node.get_kingdom(kingdom_id)
			if k != null and not k.debt_by_creditor.is_empty():
				var creditor: StringName = k.debt_by_creditor.keys()[0]
				_kingdom_node.apply_debt_change(kingdom_id, creditor, -amount)
		&"take_loan":
			var creditor: StringName = params.get("creditor", &"merchant_guild")
			var amount: int = params.get("amount", 500)
			_kingdom_node.apply_debt_change(kingdom_id, creditor, amount)
		&"shift_faction_favor":
			var faction: StringName = params.get("faction", &"military")
			var delta: int = params.get("delta", 5)
			_kingdom_node.apply_faction_shift(kingdom_id, faction, delta)
		&"set_rivalry_tension":
			var other: StringName = params.get("other_kingdom", &"")
			var delta: int = params.get("delta", 10)
			if other != &"":
				_kingdom_node.apply_rivalry_tension_change(kingdom_id, other, delta)
		&"purge_advisor":
			var advisor_id: StringName = params.get("advisor_id", &"")
			if advisor_id != &"":
				var rs: RulerState = _ruler_states.get(kingdom_id, null)
				if rs != null:
					rs.advisor_influence.erase(advisor_id)
		&"invest_in_place":
			var place_id: StringName = params.get("place_id", &"")
			if place_id != &"" and _world_registry != null:
				var place: PlaceRecord = _world_registry.get_place(place_id)
				if place != null:
					place.infrastructure_level = mini(place.infrastructure_level + 1, 100)


# --- Fidelity ---

func _update_fidelity(state: RulerState, kingdom_id: StringName) -> void:
	var investigation: Node = get_node_or_null("../Investigation")
	if investigation == null or _kingdom_node == null:
		state.fidelity = &"low"
		return
	var k: KingdomRecord = _kingdom_node.get_kingdom(kingdom_id)
	if k == null:
		state.fidelity = &"low"
		return
	if investigation.has_method("get_coverage"):
		var coverage: int = investigation.get_coverage(&"player", k.capital_place_id)
		state.fidelity = &"full" if coverage > 0 else &"low"
	else:
		state.fidelity = &"low"


# --- Succession risk ---

func _check_succession_risks(day: int) -> void:
	for kid: StringName in _ruler_states.keys():
		var state: RulerState = _ruler_states[kid]
		var ruler: CharacterRecord = _immortal_registry.get_character_record_any(state.ruler_character_id)
		if ruler == null:
			continue
		var age_days: int = ruler.age_in_days(day)
		var risk: StringName = _compute_risk(age_days)
		var prev_risk: StringName = _compute_risk(age_days - 1)
		if risk != prev_risk:
			var event := RulerSuccessionRiskRaisedEvent.new()
			event.kingdom_id = kid
			event.ruler_character_id = state.ruler_character_id
			event.ruler_age_days = age_days
			event.risk_level = risk
			event.day = day
			_event_bus.dispatch(event)


func _compute_risk(age_days: int) -> StringName:
	if age_days >= SUCCESSION_AGE_CRITICAL:
		return &"critical"
	if age_days >= SUCCESSION_AGE_HIGH:
		return &"high"
	if age_days >= SUCCESSION_AGE_MODERATE:
		return &"moderate"
	return &"low"


# --- Public API ---

func get_ruler_state(kingdom_id: StringName) -> RulerState:
	return _ruler_states.get(kingdom_id, null)


func get_runner(kingdom_id: StringName) -> RuleListRunner:
	return _runners.get(kingdom_id, null)


func all_ruler_kingdom_ids() -> Array:
	return _ruler_states.keys()


# --- Save/load ---

func snapshot_state() -> Dictionary:
	var runners_snapshot: Dictionary = {}
	for kid: StringName in _runners:
		runners_snapshot[kid] = _runners[kid].snapshot()
	return {
		"ruler_states": _ruler_states.duplicate(true),
		"runners": runners_snapshot,
	}


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_ruler_states = state.get("ruler_states", {}).duplicate(true)
	var runners_data: Dictionary = state.get("runners", {})
	for kid: StringName in runners_data:
		if not _runners.has(kid):
			_runners[kid] = RuleListRunner.new()
		_runners[kid].apply_snapshot(runners_data[kid])
	_logger.info(LogChannels.RULER_AI, "RulerAI state applied from load")
