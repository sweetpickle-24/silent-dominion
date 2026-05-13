class_name FingerprintMechanic
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _immortal_registry: Node

var _fingerprints: Dictionary = {}   # "investigator:society" -> FingerprintRecord
var _first_contacts: Dictionary = {} # "a:b" -> true (tracks fired contacts)


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_immortal_registry = get_node("/root/ImmortalRegistry")
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(&"fingerprint_state", Callable(self, "snapshot_state"), Callable(self, "apply_state"))
	_logger.info(LogChannels.FINGERPRINT, "Fingerprint mechanic ready")


func get_level(investigator_id: StringName, society_id: StringName) -> int:
	var key: String = "%s:%s" % [investigator_id, society_id]
	var fp: FingerprintRecord = _fingerprints.get(key, null)
	return fp.current_level if fp != null else 0


func get_fingerprint(investigator_id: StringName, society_id: StringName) -> FingerprintRecord:
	var key: String = "%s:%s" % [investigator_id, society_id]
	return _fingerprints.get(key, null)


func advance_level(investigator_id: StringName, society_id: StringName, new_level: int, day: int) -> void:
	var key: String = "%s:%s" % [investigator_id, society_id]
	var fp: FingerprintRecord = _fingerprints.get(key, null)
	if fp == null:
		fp = FingerprintRecord.new()
		fp.investigator_immortal_id = investigator_id
		fp.target_society_id = society_id
		fp.first_detected_at_day = day
		_fingerprints[key] = fp
	var old_level: int = fp.current_level
	fp.current_level = new_level
	fp.last_advanced_at_day = day

	var event := FingerprintLevelAdvancedEvent.new()
	event.investigator_immortal_id = investigator_id
	event.target_society_id = society_id
	event.old_level = old_level
	event.new_level = new_level
	event.day = day
	_event_bus.dispatch(event)

	_logger.info(LogChannels.FINGERPRINT, "Fingerprint level advanced", {
		"investigator": investigator_id, "target_society": society_id,
		"old_level": old_level, "new_level": new_level,
	})

	if new_level == 1 and old_level == 0:
		_fire_first_contact(investigator_id, society_id, day)


func _fire_first_contact(investigator_id: StringName, society_id: StringName, day: int) -> void:
	var society_immortal_id: StringName = &""
	for imm_id: StringName in _immortal_registry.all_immortal_ids():
		var imm: ImmortalRecord = _immortal_registry.get_immortal(imm_id)
		if imm != null and imm.society_id == society_id:
			society_immortal_id = imm_id
			break
	if society_immortal_id == &"":
		return
	# Once-per-pair check
	var inv_society: StringName = &""
	var inv_imm: ImmortalRecord = _immortal_registry.get_immortal(investigator_id)
	if inv_imm != null:
		inv_society = inv_imm.society_id
	var contact_key_a: String = "fc:%s:%s" % [investigator_id, society_id]
	var contact_key_b: String = "fc:%s:%s" % [society_immortal_id, inv_society]
	if _first_contacts.has(contact_key_a) or _first_contacts.has(contact_key_b):
		return
	var event := FirstContactEvent.new()
	event.detecting_immortal_id = investigator_id
	event.detected_society_id = society_id
	event.detected_immortal_id = society_immortal_id
	event.day = day
	_event_bus.dispatch(event)
	_first_contacts[contact_key_a] = true
	_logger.info(LogChannels.FINGERPRINT, "First contact established", {
		"detector": investigator_id, "detected_society": society_id,
	})


func snapshot_state() -> Dictionary:
	return {"fingerprints": _fingerprints.duplicate(true), "first_contacts": _first_contacts.duplicate(true)}


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_fingerprints = state.get("fingerprints", {}).duplicate(true)
	_first_contacts = state.get("first_contacts", {}).duplicate(true)
