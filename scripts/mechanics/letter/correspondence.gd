class_name Correspondence
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _immortal_registry: Node
var _world_registry: Node

var _templates: Dictionary = {}   # StringName triggering_event_class -> Array[LetterTemplate]
var _subscriptions: Array = []


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_immortal_registry = get_node("/root/ImmortalRegistry")
	_world_registry = get_node("/root/WorldRegistry")
	_load_templates()
	_wire_subscriptions()
	var total: int = 0
	for key: StringName in _templates:
		total += _templates[key].size()
	_logger.info(LogChannels.LETTER, "Correspondence mechanic ready", {"templates_loaded": total})


func _load_templates() -> void:
	var dir := DirAccess.open("res://data/letter_templates/")
	if dir == null:
		_logger.warn(LogChannels.LETTER, "data/letter_templates/ does not exist")
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path: String = "res://data/letter_templates/" + file_name
			var resource = ResourceLoader.load(path)
			if resource is LetterTemplate:
				if not _templates.has(resource.triggering_event_class):
					_templates[resource.triggering_event_class] = []
				_templates[resource.triggering_event_class].append(resource)
		file_name = dir.get_next()
	dir.list_dir_end()


func _wire_subscriptions() -> void:
	var subs: Array = [
		[preload("res://scripts/data/events/scheme_dispatched_event.gd"), "_on_scheme_dispatched"],
		[preload("res://scripts/data/events/scheme_phase_advanced_event.gd"), "_on_scheme_phase_advanced"],
		[preload("res://scripts/data/events/scheme_resolved_event.gd"), "_on_scheme_resolved"],
		[preload("res://scripts/data/events/scheme_cancelled_event.gd"), "_on_scheme_cancelled"],
		[preload("res://scripts/data/events/era_transitioned_event.gd"), "_on_era_transitioned"],
		[preload("res://scripts/data/events/disposition_rule_fired_event.gd"), "_on_disposition_rule_fired"],
		[preload("res://scripts/data/events/pattern_staleness_changed_event.gd"), "_on_pattern_staleness_changed"],
	]
	for sub in subs:
		_subscriptions.append(_event_bus.subscribe(
			sub[0], Callable(self, sub[1]), 150, &"", EndOfTickPhases.UI,
		))


# === Event handlers ===

func _on_scheme_dispatched(event: SchemeDispatchedEvent) -> void:
	var chain: Node = get_node_or_null("../Chain")
	if chain == null:
		return
	var action_def: ActionDefinition = chain.get_action_definition(event.action_type)
	if action_def == null or action_def.tier < 2:
		return
	_generate_and_file(&"SchemeDispatchedEvent", {
		"scheme_id": event.scheme_id,
		"action_display_name": action_def.display_name if action_def else str(event.action_type),
		"target_ref": event.target_ref,
		"day_text": str(event.fired_at_day),
		"lieutenant_name": _resolve_name(event.get("assigned_lieutenant_id")),
	}, event)


func _on_scheme_phase_advanced(event: SchemePhaseAdvancedEvent) -> void:
	if event.new_phase != SchemePhases.EXECUTING:
		return
	var chain: Node = get_node_or_null("../Chain")
	var action_def: ActionDefinition = chain.get_action_definition(
		_get_scheme_action_type(event.scheme_id, event.immortal_id)) if chain else null
	_generate_and_file(&"SchemePhaseAdvancedEvent", {
		"action_display_name": action_def.display_name if action_def else "operation",
		"target_place_name": _get_scheme_target_place(event.scheme_id, event.immortal_id),
		"operative_name": _get_scheme_operative_name(event.scheme_id, event.immortal_id),
		"coordinator_name": _get_scheme_coordinator_name(event.scheme_id, event.immortal_id),
	}, event)


func _on_scheme_resolved(event: SchemeResolvedEvent) -> void:
	var chain: Node = get_node_or_null("../Chain")
	var action_def: ActionDefinition = chain.get_action_definition(event.action_type) if chain else null
	var place: PlaceRecord = _world_registry.get_place(event.target_place_ref)
	_generate_and_file(&"SchemeResolvedEvent", {
		"scheme_id": event.scheme_id,
		"action_display_name": action_def.display_name if action_def else str(event.action_type),
		"target_place_name": place.name if place else str(event.target_place_ref),
		"operative_name": _get_scheme_operative_name(event.scheme_id, event.immortal_id),
		"coordinator_name": _get_scheme_coordinator_name(event.scheme_id, event.immortal_id),
		"outcome": event.outcome,
	}, event)


func _on_scheme_cancelled(event: SchemeCancelledEvent) -> void:
	var action_node: Node = get_node_or_null("../Action")
	var action_type: StringName = &""
	var target_place_name: String = ""
	# Scheme may already be removed from active; use event fields
	_generate_and_file(&"SchemeCancelledEvent", {
		"action_display_name": str(event.reason),
		"target_place_name": target_place_name,
		"handler_name": "your Lieutenant",
	}, event)


func _on_era_transitioned(event: EraTransitionedEvent) -> void:
	_generate_and_file(&"EraTransitionedEvent", {
		"old_era_display": EraValues.DISPLAY_NAMES.get(event.old_era, str(event.old_era)),
		"new_era_display": EraValues.DISPLAY_NAMES.get(event.new_era, str(event.new_era)),
		"description": event.description,
		"day_text": str(event.transition_day),
	}, event)


func _on_disposition_rule_fired(event: DispositionRuleFiredEvent) -> void:
	if absi(event.scaled_delta) < 20:
		return
	var society: Node = get_node_or_null("../SocietyCharacter")
	var society_name: String = str(event.source_society_id)
	if society:
		var rec = society.get_society(event.source_society_id)
		if rec:
			society_name = rec.display_name
	_generate_and_file(&"DispositionRuleFiredEvent", {
		"source_society_name": society_name,
		"delta": str(event.scaled_delta),
		"attribution_tag": str(event.attribution_tag),
	}, event)


func _on_pattern_staleness_changed(event: PatternStalenessChangedEvent) -> void:
	if event.new_state != StalenessValues.STALE:
		return
	_generate_and_file(&"PatternStalenessChangedEvent", {
		"pattern_id": str(event.pattern_id),
	}, event)


# === Template rendering ===

func _generate_and_file(event_class_name: StringName, slots: Dictionary, source_event: EventBase) -> void:
	var template_list: Array = _templates.get(event_class_name, [])
	var template: LetterTemplate = null
	if not template_list.is_empty():
		template = template_list[randi() % template_list.size()]
	else:
		var fallback_list: Array = _templates.get(&"_fallback", [])
		if not fallback_list.is_empty():
			template = fallback_list[0]
	if template == null:
		return

	var letter := Letter.new()
	var inbox_node: Node = get_node_or_null("../Inbox")
	if inbox_node == null:
		return
	letter.id = inbox_node.next_letter_id()
	letter.immortal_id = _resolve_recipient(source_event)
	letter.subject = _fill_slots(_pick_variant(template.subject_variants), slots)
	letter.body = _fill_slots(_pick_variant(template.body_variants), slots)
	letter.content_category = template.content_category
	letter.day_received = _time_keeper.current_day
	letter.triggering_event_class = event_class_name
	letter.sender_kind = template.sender_kind
	letter.sender_ref = _resolve_sender(template, source_event)
	letter.action_ref = source_event.get("scheme_id") if source_event.get("scheme_id") != null else &""
	letter.tier = &"active"
	letter.is_read = false

	inbox_node.add_letter(letter)

	var arrived := LetterArrivedInInboxEvent.new()
	arrived.letter_id = letter.id
	arrived.immortal_id = letter.immortal_id
	arrived.subject = letter.subject
	arrived.day_received = letter.day_received
	_event_bus.dispatch(arrived)

	if _logger.enabled_for(LogChannels.LETTER, _LOG_DEBUG):
		_logger.debug(LogChannels.LETTER, "Letter filed", {
			"letter_id": letter.id, "subject": letter.subject,
		})


func _fill_slots(text: String, slots: Dictionary) -> String:
	var result: String = text
	for key: String in slots.keys():
		result = result.replace("{%s}" % key, str(slots[key]))
	return result


func _pick_variant(variants: Array) -> String:
	if variants.is_empty():
		return ""
	return variants[randi() % variants.size()]


func _resolve_recipient(event: EventBase) -> StringName:
	var immortal_id: Variant = event.get("immortal_id")
	if immortal_id != null and immortal_id is StringName and immortal_id != &"":
		return immortal_id
	var player: ImmortalRecord = _immortal_registry.get_player()
	return player.id if player else &"player"


func _resolve_sender(template: LetterTemplate, event: EventBase) -> StringName:
	if template.sender_kind == &"system":
		return &"system"
	# For character senders, try to find a chain member from the scheme
	var scheme_id: Variant = event.get("scheme_id")
	if scheme_id != null and scheme_id is StringName:
		var action_node: Node = get_node_or_null("../Action")
		if action_node:
			var immortal_id: Variant = event.get("immortal_id")
			if immortal_id is StringName:
				var scheme: SchemeRecord = action_node.get_scheme(scheme_id, immortal_id)
				if scheme != null and scheme.assigned_coordinator_id != &"":
					return scheme.assigned_coordinator_id
				if scheme != null and scheme.assigned_lieutenant_id != &"":
					return scheme.assigned_lieutenant_id
	return &"system"


func _resolve_name(ref: Variant) -> String:
	if ref == null or not (ref is StringName) or ref == &"":
		return "unknown"
	var c: CharacterRecord = _immortal_registry.get_character_record_any(ref)
	return c.name if c else str(ref)


func _get_scheme_action_type(scheme_id: StringName, immortal_id: StringName) -> StringName:
	var action_node: Node = get_node_or_null("../Action")
	if action_node:
		var scheme: SchemeRecord = action_node.get_scheme(scheme_id, immortal_id)
		if scheme:
			return scheme.action_type
	return &""


func _get_scheme_target_place(scheme_id: StringName, immortal_id: StringName) -> String:
	var action_node: Node = get_node_or_null("../Action")
	if action_node:
		var scheme: SchemeRecord = action_node.get_scheme(scheme_id, immortal_id)
		if scheme:
			var place: PlaceRecord = _world_registry.get_place(scheme.target_place_ref)
			return place.name if place else str(scheme.target_place_ref)
	return "unknown"


func _get_scheme_operative_name(scheme_id: StringName, immortal_id: StringName) -> String:
	var action_node: Node = get_node_or_null("../Action")
	if action_node:
		var scheme: SchemeRecord = action_node.get_scheme(scheme_id, immortal_id)
		if scheme and scheme.assigned_operative_id != &"":
			return _resolve_name(scheme.assigned_operative_id)
	return "the operative"


func _get_scheme_coordinator_name(scheme_id: StringName, immortal_id: StringName) -> String:
	var action_node: Node = get_node_or_null("../Action")
	if action_node:
		var scheme: SchemeRecord = action_node.get_scheme(scheme_id, immortal_id)
		if scheme and scheme.assigned_coordinator_id != &"":
			return _resolve_name(scheme.assigned_coordinator_id)
	return "your coordinator"
