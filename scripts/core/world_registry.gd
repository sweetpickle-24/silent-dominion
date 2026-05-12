extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")

var _logger: Node

# Loaded at _ready, then read-only for the rest of the game.
var places: Dictionary = {}          # StringName id -> PlaceRecord
var place_types: Dictionary = {}     # StringName id -> PlaceTypeDefinition
var provinces: Dictionary = {}       # StringName id -> ProvinceRecord
var routes: Dictionary = {}          # StringName id -> RouteRecord


func _ready() -> void:
	_logger = get_node("/root/Logger")
	_load_place_types("res://data/place_types/")
	_load_resources_from_dir("res://data/provinces/", provinces, "ProvinceRecord", false)
	_load_resources_from_dir("res://data/routes/", routes, "RouteRecord", false)
	_load_places("res://data/places/")
	_logger.info(LogChannels.WORLD_REGISTRY, "WorldRegistry loaded", {
		"place_types": place_types.size(),
		"provinces": provinces.size(),
		"routes": routes.size(),
		"places": places.size(),
	})


# --- Public read-only query API ---

func get_place(id: StringName) -> PlaceRecord:
	return places.get(id, null)


func get_place_type(id: StringName) -> PlaceTypeDefinition:
	return place_types.get(id, null)


func all_place_ids() -> Array:
	return places.keys()


func place_count() -> int:
	return places.size()


func get_province(id: StringName) -> ProvinceRecord:
	return provinces.get(id, null)


func get_route(id: StringName) -> RouteRecord:
	return routes.get(id, null)


func all_province_ids() -> Array:
	return provinces.keys()


func all_route_ids() -> Array:
	return routes.keys()


func places_in_province(province_id: StringName) -> Array:
	var matches: Array = []
	for place_id: StringName in places.keys():
		var place: PlaceRecord = places[place_id]
		if place.province == province_id:
			matches.append(place)
	return matches


# --- Internal loading ---

func _load_place_types(dir_path: String) -> void:
	_load_resources_from_dir(dir_path, place_types, "PlaceTypeDefinition", false)


func _load_places(dir_path: String) -> void:
	_load_resources_from_dir(dir_path, places, "PlaceRecord", true)
	# Validate: every place's place_type must reference a known PlaceTypeDefinition.
	for id: StringName in places:
		var record: PlaceRecord = places[id]
		if not place_types.has(record.place_type):
			_logger.error(LogChannels.WORLD_REGISTRY, "PlaceRecord references unknown place_type", {
				"place_id": id,
				"place_type": record.place_type,
			})
			assert(false, "Unknown place_type '%s' in place '%s'" % [record.place_type, id])


func _load_resources_from_dir(dir_path: String, target: Dictionary, expected_class: String, recurse: bool) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_logger.warn(LogChannels.WORLD_REGISTRY, "Directory not found: %s" % dir_path)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		var full_path: String = dir_path.path_join(file_name)
		if dir.current_is_dir():
			if recurse and not file_name.begins_with("."):
				_load_resources_from_dir(full_path + "/", target, expected_class, true)
		elif file_name.ends_with(".tres"):
			var res: Resource = ResourceLoader.load(full_path)
			if res == null:
				_logger.error(LogChannels.WORLD_REGISTRY, "Failed to load resource: %s" % full_path)
			elif res.get_class() != "Resource" and res.get_script() == null:
				_logger.error(LogChannels.WORLD_REGISTRY, "Resource has no script: %s" % full_path)
			else:
				var id: Variant = res.get("id")
				if id == null or (id is StringName and id == &""):
					_logger.error(LogChannels.WORLD_REGISTRY, "Resource missing id field: %s" % full_path)
				elif target.has(id):
					_logger.error(LogChannels.WORLD_REGISTRY, "Duplicate resource id", {
						"id": id,
						"path": full_path,
					})
					assert(false, "Duplicate resource id '%s' at %s" % [id, full_path])
				else:
					target[id] = res
		file_name = dir.get_next()
	dir.list_dir_end()
