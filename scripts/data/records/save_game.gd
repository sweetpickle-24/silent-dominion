class_name SaveGame
extends Resource

@export var save_version: int = 4
@export var save_mode: StringName = &"standard"

# Per-mechanic state. Primary storage from v2 onwards.
# Keyed by state_key registered with SaveSystem.
@export var mechanic_states: Dictionary = {}

# Deprecated v1 fields. Kept for v1->v2 migration. New saves leave these
# at defaults. Will be removed in v3.
@export var game_day: int = 0
@export var current_year: int = 0
@export var current_era: StringName = &"ancient"
@export var current_season: StringName = &"spring"
@export var memoirs_libraries: Dictionary = {}
@export var action_state: Dictionary = {}
@export var society_character_state: Dictionary = {}

# TODO: @export var world: WorldState
# TODO: @export var immortals: Array[ImmortalState] = []
# TODO: @export var coordination: CoordinationState
# TODO: @export var chronicle: ChronicleRecord
# TODO: @export var session_metadata: SessionMetadata
