class_name InvestigationMechanic
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _trace: Node
var _fingerprint: Node
var _world_registry: Node
var _immortal_registry: Node

var _coverage: Dictionary = {}              # immortal_id -> {province_id -> CoverageAssignment}
var _detected_trace_counts: Dictionary = {} # "investigator:society" -> {count, detected_trace_ids}

const FINGERPRINT_THRESHOLDS: Array = [5, 10, 20, 40, 80]


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_trace = get_node("../Trace")
	_fingerprint = get_node("../Fingerprint")
	_world_registry = get_node("/root/WorldRegistry")
	_immortal_registry = get_node("/root/ImmortalRegistry")
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(&"investigation_state", Callable(self, "snapshot_state"), Callable(self, "apply_state"))
	_event_bus.subscribe(preload("res://scripts/data/events/game_day_ticked_event.gd"), Callable(self, "_on_game_day_ticked"), 250, &"", EndOfTickPhases.PER_IMMORTAL)
	_initialize_default_coverage()
	_logger.info(LogChannels.INVESTIGATION, "Investigation mechanic ready")


func _initialize_default_coverage() -> void:
	for immortal_id: StringName in _immortal_registry.all_immortal_ids():
		var immortal: ImmortalRecord = _immortal_registry.get_immortal(immortal_id)
		var home_province: StringName = &""
		if immortal != null and immortal.character != null:
			var place: PlaceRecord = _world_registry.get_place(immortal.character.current_place)
			if place != null:
				home_province = place.province
		for province_id: StringName in _world_registry.all_province_ids():
			var level: int = 30 if province_id == home_province else 10
			set_coverage(immortal_id, province_id, level)


func _on_game_day_ticked(event: GameDayTickedEvent) -> void:
	var day: int = event.day
	for investigator_id: StringName in _immortal_registry.all_immortal_ids():
		_process_investigator(investigator_id, day)


func _process_investigator(investigator_id: StringName, day: int) -> void:
	var imm_coverage: Dictionary = _coverage.get(investigator_id, {})
	for place_id: StringName in _world_registry.all_place_ids():
		var place: PlaceRecord = _world_registry.get_place(place_id)
		var assignment: CoverageAssignment = imm_coverage.get(place.province, null)
		if assignment == null:
			continue
		var detection_mult: float = assignment.effective_detection_multiplier()
		if detection_mult <= 0.0:
			continue
		var traces: Array = _trace.get_traces_at_place(place_id)
		for trace: TraceRecord in traces:
			if trace.emitting_immortal_id == investigator_id:
				continue
			if trace.emitting_society_id == &"":
				continue
			var threshold: float = place.ambient_activity_baseline / (detection_mult + 0.1)
			var strength: float = trace.current_strength_at(day)
			if strength < threshold:
				continue
			_record_detection(investigator_id, trace.emitting_society_id, trace.id, day)


func _record_detection(investigator_id: StringName, society_id: StringName, trace_id: StringName, day: int) -> void:
	var key: String = "%s:%s" % [investigator_id, society_id]
	if not _detected_trace_counts.has(key):
		_detected_trace_counts[key] = {"count": 0, "detected_trace_ids": {}}
	var entry: Dictionary = _detected_trace_counts[key]
	if entry.detected_trace_ids.has(trace_id):
		return
	entry.detected_trace_ids[trace_id] = day
	entry.count += 1
	if _logger.enabled_for(LogChannels.INVESTIGATION, _LOG_DEBUG):
		_logger.debug(LogChannels.INVESTIGATION, "Trace detected", {
			"investigator": investigator_id, "society": society_id, "count": entry.count,
		})
	var fp_level: int = _fingerprint.get_level(investigator_id, society_id)
	var next_level: int = fp_level + 1
	if next_level <= 5 and next_level <= FINGERPRINT_THRESHOLDS.size():
		if entry.count >= FINGERPRINT_THRESHOLDS[next_level - 1]:
			_fingerprint.advance_level(investigator_id, society_id, next_level, day)


func set_coverage(immortal_id: StringName, province_id: StringName, level: int) -> void:
	level = clampi(level, 0, 100)
	if not _coverage.has(immortal_id):
		_coverage[immortal_id] = {}
	var assignment: CoverageAssignment = _coverage[immortal_id].get(province_id, null)
	if assignment == null:
		assignment = CoverageAssignment.new()
		assignment.immortal_id = immortal_id
		assignment.province_id = province_id
		_coverage[immortal_id][province_id] = assignment
	assignment.coverage_level = level
	assignment.bandwidth_cost = level / 10


func get_coverage(immortal_id: StringName, province_id: StringName) -> int:
	var imm_cov: Dictionary = _coverage.get(immortal_id, {})
	var assignment: CoverageAssignment = imm_cov.get(province_id, null)
	return assignment.coverage_level if assignment != null else 0


func get_detected_count(investigator_id: StringName, society_id: StringName) -> int:
	var key: String = "%s:%s" % [investigator_id, society_id]
	var entry: Dictionary = _detected_trace_counts.get(key, {})
	return entry.get("count", 0)


func snapshot_state() -> Dictionary:
	return {"coverage": _coverage.duplicate(true), "detected_trace_counts": _detected_trace_counts.duplicate(true)}


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_coverage = state.get("coverage", {}).duplicate(true)
	_detected_trace_counts = state.get("detected_trace_counts", {}).duplicate(true)
