class_name SaveGame
extends Resource

@export var save_version: int = 1
@export var save_mode: StringName = &"standard"
@export var game_day: int = 0
@export var current_year: int = 0
@export var current_era: StringName = &"ancient"
@export var current_season: StringName = &"spring"
@export var memoirs_libraries: Dictionary = {}   # StringName immortal_id -> MemoirsLibrary

# TODO: @export var world: WorldState
# TODO: @export var immortals: Array[ImmortalState] = []
# TODO: @export var coordination: CoordinationState
# TODO: @export var chronicle: ChronicleRecord
# TODO: @export var session_metadata: SessionMetadata
