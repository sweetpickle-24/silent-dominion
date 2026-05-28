class_name DiplomacyDetail
extends Control

# Diplomacy detail panel — shows known societies, treaties, reputation, channels.
# Added at substep 11.10. Visual polish at 11.21.

var _treaty: Node
var _first_contact: Node
var _society_character: Node
var _fingerprint: Node
var _logger: Node


func _ready() -> void:
	_logger = get_node("/root/Logger")
	_treaty = get_node_or_null("/root/Main/Mechanics/Treaty")
	_first_contact = get_node_or_null("/root/Main/Mechanics/FirstContact")
	_society_character = get_node_or_null("/root/Main/Mechanics/SocietyCharacter")
	_fingerprint = get_node_or_null("/root/Main/Mechanics/Fingerprint")
	_logger.info(LogChannels.DIPLOMACY, "DiplomacyDetail panel ready")


# --- Public API for UI queries ---

func get_known_societies(player_immortal_id: StringName) -> Array[Dictionary]:
	# Returns array of {society_id, display_name, awareness_level, disposition, channel_stage}
	# for each society the player is aware of (Fingerprint Level 1+)
	var result: Array[Dictionary] = []
	if _fingerprint == null:
		return result
	var ir: Node = get_node("/root/ImmortalRegistry")
	for immortal_id: StringName in ir.all_immortal_ids():
		var immortal: ImmortalRecord = ir.get_immortal(immortal_id)
		if immortal == null or immortal.is_player():
			continue
		var fp_level: int = _fingerprint.get_level(player_immortal_id, immortal.society_id)
		if fp_level < 1:
			continue
		var entry: Dictionary = {
			"society_id": immortal.society_id,
			"immortal_id": immortal_id,
			"display_name": _get_display_name(immortal.society_id, fp_level),
			"awareness_level": fp_level,
			"disposition": _get_disposition(immortal.society_id, player_immortal_id),
			"channel_stage": _get_channel_stage(player_immortal_id, immortal_id),
			"active_treaties": _get_active_treaties(player_immortal_id),
			"reputation": _get_reputation(player_immortal_id),
		}
		result.append(entry)
	return result


func _get_display_name(society_id: StringName, fp_level: int) -> String:
	if fp_level >= 4 and _society_character != null:
		var sc: SocietyCharacterRecord = _society_character.get_society(society_id)
		if sc != null:
			return sc.display_name
	return "An unknown organisation"


func _get_disposition(society_id: StringName, player_id: StringName) -> int:
	if _society_character == null:
		return 0
	return _society_character.get_disposition(society_id, player_id)


func _get_channel_stage(player_id: StringName, other_id: StringName) -> StringName:
	if _first_contact == null:
		return &"unaware"
	var state: FirstContactState = _first_contact.get_contact_state(player_id, other_id)
	if state == null:
		return &"unaware"
	return state.stage


func _get_active_treaties(immortal_id: StringName) -> Array:
	if _treaty == null:
		return []
	return _treaty.get_active_treaties_for(immortal_id)


func _get_reputation(immortal_id: StringName) -> int:
	if _treaty == null:
		return 50
	var rep: ReputationRecord = _treaty.get_reputation(immortal_id)
	return rep.reputation_score
