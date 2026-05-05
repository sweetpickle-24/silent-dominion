# Autoloads accessed via SceneTree root because GDScript class_name scripts
# can't reference autoload globals directly. C3's API is preserved.
class_name WorldView
extends RefCounted

# Time (pinned at construction — consistent within a single evaluation)
var day: int = 0
var year: int = 0
var era: StringName = &""
var season: StringName = &""

# Registries (read-only pass-through references — no deep copy)
var places: Dictionary = {}       # StringName -> PlaceRecord (populated when WorldRegistry is wired, Step 4+)
var kingdoms: Dictionary = {}     # StringName -> KingdomRecord
var characters: Dictionary = {}   # StringName -> CharacterRecord
var societies: Dictionary = {}    # StringName -> SocietyCharacterRecord
var religions: Dictionary = {}    # StringName -> ReligionRecord


func place(id: StringName) -> Resource:
	return places.get(id)


func kingdom(id: StringName) -> Resource:
	return kingdoms.get(id)


func character(id: StringName) -> Resource:
	return characters.get(id)


func society(id: StringName) -> Resource:
	return societies.get(id)


static func _get_autoload(name: StringName) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(NodePath(name))


# Snapshot the current world state.
static func snapshot() -> WorldView:
	var time_keeper: Node = _get_autoload(&"TimeKeeper")
	var world_registry: Node = _get_autoload(&"WorldRegistry")
	var view := WorldView.new()
	view.day = time_keeper.current_day
	view.year = time_keeper.current_year
	view.era = time_keeper.current_era
	view.season = time_keeper.current_season
	# Pass-through references — rules read live data, don't copy.
	if world_registry.get("places") != null:
		view.places = world_registry.places
	if world_registry.get("kingdoms") != null:
		view.kingdoms = world_registry.kingdoms
	if world_registry.get("characters") != null:
		view.characters = world_registry.characters
	if world_registry.get("societies") != null:
		view.societies = world_registry.societies
	if world_registry.get("religions") != null:
		view.religions = world_registry.religions
	return view


# Snapshot for a specified day/era (non-event evaluations like era transitions).
static func snapshot_for(day: int, era: StringName) -> WorldView:
	var view := snapshot()
	view.day = day
	view.era = era
	return view
