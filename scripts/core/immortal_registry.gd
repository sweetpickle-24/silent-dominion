extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")

var _logger: Node

var _immortals: Dictionary = {}    # StringName id -> ImmortalRecord
var _characters: Dictionary = {}   # StringName id -> CharacterRecord


func _ready() -> void:
	_logger = get_node("/root/Logger")
	_load_immortals("res://data/immortals/")
	_load_characters("res://data/characters/")
	_logger.info(LogChannels.IMMORTAL_REGISTRY, "ImmortalRegistry loaded", {
		"immortals": _immortals.size(),
		"characters": _characters.size(),
	})


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
		if file_name.ends_with(".tres"):
			var path: String = dir_path + file_name
			var resource = ResourceLoader.load(path)
			if resource != null:
				var id: Variant = resource.get("id")
				if id != null and id is StringName and id != &"":
					assert(not target.has(id), "Duplicate id %s in %s" % [id, dir_path])
					target[id] = resource
		file_name = dir.get_next()
	dir.list_dir_end()
