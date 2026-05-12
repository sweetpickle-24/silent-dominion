class_name Chain
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _action: Node
var _immortal_registry: Node
var _world_registry: Node
var _tick_subscription  # SubscriptionHandle

# ActionDefinitions loaded from data/action_definitions/.
var _action_definitions: Dictionary = {}   # StringName id -> ActionDefinition

# Default phase durations (fallback when ActionDefinition has no override).
const _DEFAULT_PHASE_DURATIONS: Dictionary = {
	&"dispatched": 2,
	&"acknowledged": 3,
	&"routing": 5,
	&"executing": 20,
}

# Phase progression order.
const _PHASE_ORDER: Dictionary = {
	&"dispatched": &"acknowledged",
	&"acknowledged": &"routing",
	&"routing": &"executing",
	&"executing": &"resolved",
}

# Heat threshold — skip members with heat above this unless no alternative.
const _HEAT_THRESHOLD: int = 70

# Placeholder region-to-language map until Region mechanic at 11.6.
const _REGION_LANGUAGES: Dictionary = {
	&"attica": &"greek", &"laconia": &"greek", &"corinthia": &"greek",
	&"boeotia": &"greek", &"phocis": &"greek", &"ionia": &"greek",
	&"chalcidice": &"greek", &"magna_graecia": &"greek", &"cyrenaica": &"greek",
	&"persis": &"persian", &"elam": &"persian", &"babylonia": &"persian",
	&"media": &"persian", &"phoenicia": &"aramaic",
	&"egypt_lower": &"egyptian", &"africa_punica": &"phoenician",
	&"latium": &"latin",
}


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_action = get_node("../Action")
	_immortal_registry = get_node("/root/ImmortalRegistry")
	_world_registry = get_node("/root/WorldRegistry")
	_load_action_definitions()
	_tick_subscription = _event_bus.subscribe(
		preload("res://scripts/data/events/game_day_ticked_event.gd"),
		Callable(self, "_on_game_day_ticked"),
		50,
		&"",
		EndOfTickPhases.PER_IMMORTAL,
	)
	_logger.info(LogChannels.CHAIN, "Chain mechanic ready", {
		"action_definitions": _action_definitions.size(),
	})


func _load_action_definitions() -> void:
	var dir := DirAccess.open("res://data/action_definitions/")
	if dir == null:
		_logger.warn(LogChannels.CHAIN, "data/action_definitions/ does not exist")
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path: String = "res://data/action_definitions/" + file_name
			var resource = ResourceLoader.load(path)
			if resource is ActionDefinition:
				_action_definitions[resource.id] = resource
		file_name = dir.get_next()
	dir.list_dir_end()


func get_action_definition(action_type: StringName) -> ActionDefinition:
	return _action_definitions.get(action_type, null)


func get_all_action_definitions() -> Dictionary:
	return _action_definitions


func _on_game_day_ticked(event: GameDayTickedEvent) -> void:
	_advance_schemes(event.day)
	_check_chain_breaks(event.day)


# === Phase advancement ===

func _advance_schemes(day: int) -> void:
	# Advance schemes for ALL immortals (player + society founders).
	for immortal_id: StringName in _immortal_registry.all_immortal_ids():
		var schemes: Array = _action.get_active_schemes(immortal_id)
		for scheme: SchemeRecord in schemes:
			_try_advance_scheme(scheme, day)


func _try_advance_scheme(scheme: SchemeRecord, day: int) -> void:
	var next_phase: StringName = _PHASE_ORDER.get(scheme.current_phase, &"")
	if next_phase == &"":
		return
	var duration: int = _compute_phase_duration(scheme)
	var days_in_phase: int = day - scheme.current_phase_entered_at_day
	if days_in_phase < duration:
		return
	# Select chain member for the next phase if needed
	var required_status: StringName = _phase_to_chain_status(next_phase)
	if required_status != &"":
		var candidates: Array = _find_candidates(scheme, required_status, day)
		if candidates.is_empty():
			# Fallback: if no Lieutenant exists, the dispatching immortal acts as their own Lieutenant.
			if required_status == ChainStatusValues.LIEUTENANT:
				var immortal: ImmortalRecord = _immortal_registry.get_immortal(scheme.immortal_id)
				if immortal != null:
					_apply_assignment(scheme, next_phase, immortal.character.id)
				else:
					return
			else:
				_logger.warn(LogChannels.CHAIN, "No candidate for phase", {
					"scheme_id": scheme.id, "phase": next_phase, "required": required_status,
				})
				return
		else:
			var best: CharacterRecord = _pick_best_candidate(candidates, scheme)
			_apply_assignment(scheme, next_phase, best.id)
	# Fire SchemePhaseAdvanced
	var event := SchemePhaseAdvancedEvent.new()
	event.scheme_id = scheme.id
	event.immortal_id = scheme.immortal_id
	event.old_phase = scheme.current_phase
	event.new_phase = next_phase
	event.days_in_old_phase = days_in_phase
	_event_bus.dispatch(event)


func _compute_phase_duration(scheme: SchemeRecord) -> int:
	var action_def: ActionDefinition = _action_definitions.get(scheme.action_type)
	var base_duration: int = _DEFAULT_PHASE_DURATIONS.get(scheme.current_phase, 5)
	if action_def != null:
		var override: int = action_def.phase_timing_overrides.get(scheme.current_phase, -1)
		if override > 0:
			base_duration = override
	var skill_factor: float = _compute_skill_factor(scheme)
	return maxi(1, int(base_duration * skill_factor))


func _compute_skill_factor(scheme: SchemeRecord) -> float:
	var member_id: StringName = _current_phase_member_id(scheme)
	if member_id == &"":
		return 1.0
	var member: CharacterRecord = _immortal_registry.get_character_record_any(member_id)
	if member == null:
		return 1.0
	var skill: float = (member.intellect + member.resilience) / 2.0
	return 1.5 - (skill / 100.0)


func _current_phase_member_id(scheme: SchemeRecord) -> StringName:
	match scheme.current_phase:
		SchemePhases.DISPATCHED, SchemePhases.ACKNOWLEDGED:
			return scheme.assigned_lieutenant_id
		SchemePhases.ROUTING:
			return scheme.assigned_coordinator_id
		SchemePhases.EXECUTING:
			return scheme.assigned_operative_id
		_: return &""


# === Member selection ===

func _phase_to_chain_status(phase: StringName) -> StringName:
	match phase:
		SchemePhases.ACKNOWLEDGED: return ChainStatusValues.LIEUTENANT
		SchemePhases.ROUTING: return ChainStatusValues.COORDINATOR
		SchemePhases.EXECUTING: return ChainStatusValues.WITTING_OPERATIVE
		_: return &""


func _find_candidates(scheme: SchemeRecord, required_status: StringName, day: int = -1) -> Array:
	var candidates: Array = []
	if day < 0:
		var tk: Node = get_node("/root/TimeKeeper")
		if tk:
			day = tk.current_day
		else:
			day = 0
	# Determine which society this scheme belongs to for filtering
	var scheme_society: StringName = &""
	var immortal: ImmortalRecord = _immortal_registry.get_immortal(scheme.immortal_id)
	if immortal != null:
		scheme_society = immortal.society_id
	for char_id: StringName in _immortal_registry.all_character_ids():
		var c: CharacterRecord = _immortal_registry.get_character(char_id)
		if c.chain_status != required_status:
			continue
		# Filter by society — only match characters in the same organisation
		if c.society_id != scheme_society:
			continue
		if not c.is_alive(day):
			continue
		if c.heat > _HEAT_THRESHOLD:
			continue
		if _count_assignments(char_id) >= c.max_concurrent_assignments:
			continue
		candidates.append(c)
	return candidates


func _count_assignments(character_id: StringName) -> int:
	var count: int = 0
	var player: ImmortalRecord = _immortal_registry.get_player()
	if player == null:
		return 0
	for scheme: SchemeRecord in _action.get_active_schemes(player.id):
		if scheme.assigned_lieutenant_id == character_id:
			count += 1
		if scheme.assigned_coordinator_id == character_id:
			count += 1
		if scheme.assigned_operative_id == character_id:
			count += 1
	return count


func _pick_best_candidate(candidates: Array, scheme: SchemeRecord) -> CharacterRecord:
	var best: CharacterRecord = null
	var best_score: float = -1.0
	var target_region: StringName = &""
	var place: PlaceRecord = _world_registry.get_place(scheme.target_place_ref)
	if place != null:
		target_region = place.province
	for c: CharacterRecord in candidates:
		var score: float = 0.0
		# Region match bonus
		if c.province == target_region:
			score += 30.0
		# Language match bonus
		var target_lang: StringName = _REGION_LANGUAGES.get(target_region, &"")
		if target_lang != &"" and target_lang in c.languages:
			score += 20.0
		# Skill bonus
		score += (c.intellect + c.resilience) / 4.0  # 0-50
		# Low heat bonus
		score += (100 - c.heat) / 5.0  # 0-20
		# Available bandwidth bonus
		score += (c.max_concurrent_assignments - _count_assignments(c.id)) * 5.0
		if score > best_score:
			best_score = score
			best = c
	return best


func _apply_assignment(scheme: SchemeRecord, phase: StringName, character_id: StringName) -> void:
	match phase:
		SchemePhases.ACKNOWLEDGED:
			scheme.assigned_lieutenant_id = character_id
		SchemePhases.ROUTING:
			scheme.assigned_coordinator_id = character_id
		SchemePhases.EXECUTING:
			scheme.assigned_operative_id = character_id
			# Update exposure_cost_total with operative's public position
			var op: CharacterRecord = _immortal_registry.get_character_record_any(character_id)
			var action_def: ActionDefinition = _action_definitions.get(scheme.action_type)
			if op != null and action_def != null:
				scheme.exposure_cost_total = action_def.baseline_exposure_cost * PublicPositionValues.EXPOSURE_MULTIPLIER.get(op.public_position_tier, 1.0)
	if _logger.enabled_for(LogChannels.CHAIN, _LOG_DEBUG):
		_logger.debug(LogChannels.CHAIN, "Chain member assigned", {
			"scheme_id": scheme.id, "phase": phase, "member": character_id,
		})


# === Chain-break ===

func _check_chain_breaks(day: int) -> void:
	var player: ImmortalRecord = _immortal_registry.get_player()
	if player == null:
		return
	for scheme: SchemeRecord in _action.get_active_schemes(player.id):
		_verify_scheme_chain(scheme, day)


func _verify_scheme_chain(scheme: SchemeRecord, day: int) -> void:
	var member_ids: Array = [
		scheme.assigned_lieutenant_id,
		scheme.assigned_coordinator_id,
		scheme.assigned_operative_id,
	]
	for member_id: StringName in member_ids:
		if member_id == &"":
			continue
		var member: CharacterRecord = _immortal_registry.get_character_record_any(member_id)
		if member == null or not member.is_alive(day):
			_handle_chain_break(scheme, member_id, day)
			return


func _handle_chain_break(scheme: SchemeRecord, broken_member_id: StringName, day: int) -> void:
	var broken_phase: StringName = _which_phase_is_member_in(scheme, broken_member_id)
	var required_status: StringName = _phase_to_chain_status(broken_phase)
	if required_status == &"":
		_cancel_scheme(scheme, &"chain_break", day)
		return
	var candidates: Array = _find_candidates(scheme, required_status, day)
	if candidates.is_empty():
		_cancel_scheme(scheme, &"chain_break", day)
		return
	var replacement: CharacterRecord = _pick_best_candidate(candidates, scheme)
	_apply_assignment(scheme, broken_phase, replacement.id)
	_logger.warn(LogChannels.CHAIN, "Chain reassigned after break", {
		"scheme_id": scheme.id,
		"broken_member": broken_member_id,
		"replacement": replacement.id,
	})


func _which_phase_is_member_in(scheme: SchemeRecord, member_id: StringName) -> StringName:
	if scheme.assigned_lieutenant_id == member_id:
		return SchemePhases.ACKNOWLEDGED
	if scheme.assigned_coordinator_id == member_id:
		return SchemePhases.ROUTING
	if scheme.assigned_operative_id == member_id:
		return SchemePhases.EXECUTING
	return &""


func _cancel_scheme(scheme: SchemeRecord, reason: StringName, day: int) -> void:
	scheme.outcome = &"cancelled"
	scheme.cancellation_reason = reason
	scheme.resolved_at_day = day
	var event := SchemeCancelledEvent.new()
	event.scheme_id = scheme.id
	event.immortal_id = scheme.immortal_id
	event.reason = reason
	event.day = day
	_event_bus.dispatch(event)
	_logger.info(LogChannels.CHAIN, "Scheme cancelled", {
		"scheme_id": scheme.id, "reason": reason,
	})


# === Debug API ===

func debug_kill_character(character_id: StringName, day: int) -> void:
	var character: CharacterRecord = _immortal_registry.get_character_record_any(character_id)
	if character == null:
		push_error("debug_kill_character: unknown id %s" % character_id)
		return
	character.death_day = day
	_logger.warn(LogChannels.CHAIN, "DEBUG: character killed", {"id": character_id, "day": day})
