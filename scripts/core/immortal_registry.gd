extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")

var _logger: Node

var _immortals: Dictionary = {}    # StringName id -> ImmortalRecord
var _characters: Dictionary = {}   # StringName id -> CharacterRecord


func _ready() -> void:
	_logger = get_node("/root/Logger")
	_load_immortals("res://data/immortals/")
	_load_characters("res://data/characters/")
	call_deferred("_register_save_handlers")
	_logger.info(LogChannels.IMMORTAL_REGISTRY, "ImmortalRegistry loaded", {
		"immortals": _immortals.size(),
		"characters": _characters.size(),
	})


func _register_save_handlers() -> void:
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"immortal_registry_state",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)


func snapshot_state() -> Dictionary:
	var character_states: Dictionary = {}
	for char_id: StringName in _characters.keys():
		var ch: CharacterRecord = _characters[char_id]
		character_states[char_id] = {
			"heat": ch.heat, "trust_score": ch.trust_score,
			"chain_status": ch.chain_status, "society_id": ch.society_id,
			"current_place": ch.current_place, "death_day": ch.death_day,
		}
	var immortal_states: Dictionary = {}
	for imm_id: StringName in _immortals.keys():
		var imm: ImmortalRecord = _immortals[imm_id]
		immortal_states[imm_id] = {
			"current_cover_identity": imm.current_cover_identity,
			"accumulated_legend": imm.accumulated_legend,
			"society_id": imm.society_id,
		}
	return {"characters": character_states, "immortals": immortal_states}


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	for char_id: StringName in state.get("characters", {}).keys():
		var ch: CharacterRecord = _characters.get(char_id, null)
		if ch == null:
			continue
		var mut: Dictionary = state["characters"][char_id]
		ch.heat = mut.get("heat", ch.heat)
		ch.trust_score = mut.get("trust_score", ch.trust_score)
		ch.chain_status = mut.get("chain_status", ch.chain_status)
		ch.society_id = mut.get("society_id", ch.society_id)
		ch.current_place = mut.get("current_place", ch.current_place)
		ch.death_day = mut.get("death_day", ch.death_day)
	for imm_id: StringName in state.get("immortals", {}).keys():
		var imm: ImmortalRecord = _immortals.get(imm_id, null)
		if imm == null:
			continue
		var mut: Dictionary = state["immortals"][imm_id]
		imm.current_cover_identity = mut.get("current_cover_identity", imm.current_cover_identity)
		imm.accumulated_legend = mut.get("accumulated_legend", imm.accumulated_legend)
		imm.society_id = mut.get("society_id", imm.society_id)


# --- Public read-only query API ---

func get_immortal(id: StringName) -> ImmortalRecord:
	return _immortals.get(id, null)


func get_character(id: StringName) -> CharacterRecord:
	return _characters.get(id, null)


func get_player() -> ImmortalRecord:
	return _immortals.get(&"player", null)


func all_immortal_ids() -> Array:
	return _immortals.keys()


func all_character_ids() -> Array:
	return _characters.keys()


func get_character_record_any(id: StringName) -> CharacterRecord:
	var character: CharacterRecord = _characters.get(id, null)
	if character != null:
		return character
	var immortal: ImmortalRecord = _immortals.get(id, null)
	if immortal != null:
		return immortal.character
	return null


func characters_at_place(place_id: StringName) -> Array:
	var matches: Array = []
	for character_id: StringName in _characters.keys():
		var character: CharacterRecord = _characters[character_id]
		if character.current_place == place_id:
			matches.append(character)
	return matches


func immortal_count() -> int:
	return _immortals.size()


func character_count() -> int:
	return _characters.size()


# --- Internal loading ---

func _load_immortals(dir_path: String) -> void:
	_load_resources_from_dir(dir_path, _immortals)


func _load_characters(dir_path: String) -> void:
	_load_resources_from_dir(dir_path, _characters)


func _load_resources_from_dir(dir_path: String, target: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_logger.warn(LogChannels.IMMORTAL_REGISTRY, "%s does not exist; nothing loaded" % dir_path)
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		var full_path: String = dir_path + file_name
		if dir.current_is_dir() and not file_name.begins_with("."):
			_load_resources_from_dir(full_path + "/", target)
		elif file_name.ends_with(".tres"):
			var resource = ResourceLoader.load(full_path)
			if resource != null:
				var id: Variant = resource.get("id")
				if id != null and id is StringName and id != &"":
					assert(not target.has(id), "Duplicate id %s in %s" % [id, dir_path])
					target[id] = resource
		file_name = dir.get_next()
	dir.list_dir_end()
