class_name PlaceRecord
extends Resource

# Identity (Step 4)
@export var id: StringName
@export var name: String
@export var place_type: StringName
@export var region: StringName
@export var founded_day: int = 0

# Population. Settlements: human inhabitants. Sites: staff count.
@export var population: int = 0

# Infrastructure level (0-100). Roads, walls, public buildings.
@export var infrastructure_level: int = 0

# Factional balance. Floats sum to ~1.0.
# Keys: &"civic", &"military", &"religious", &"mercantile", &"scholarly".
@export var factional_balance: Dictionary = {}

# Ambient activity baseline for trace signal-to-noise per Gap 6.
@export var ambient_activity_baseline: float = 1.0

# Tax yield per day. Computed by Place mechanic from population x infrastructure x era.
@export var tax_yield_per_day: int = 0

# Accumulated yield since last extraction.
@export var accumulated_yield: int = 0

# Site-specific capacity. Mines: remaining ore. Monasteries: scholarly traffic cap.
# -1 means unlimited / not applicable.
@export var site_capacity: int = -1
