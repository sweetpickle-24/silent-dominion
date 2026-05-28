extends Node

var _recent_history_queries: RecentHistoryQueries = RecentHistoryQueries.new()

var _logger: Node
var _time_keeper: Node


func _ready() -> void:
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_logger.info(LogChannels.DEBUG, "Helpers ready")


# --- Time helpers ---

func days_since(reference_day: int) -> int:
	return _time_keeper.current_day - reference_day


func days_until(target_day: int) -> int:
	return target_day - _time_keeper.current_day


func years_since(reference_day: int) -> float:
	return (_time_keeper.current_day - reference_day) / 365.0


# --- Recency / history helpers ---

func recent_history() -> RecentHistoryQueries:
	return _recent_history_queries


# --- Distance and geography helpers ---

func distance_between_places(_place_a: StringName, _place_b: StringName) -> float:
	# TODO: implement when Distance utility exists
	return 0.0


# Named regions_* for backward compat (Step 3). Operates on province ids.
func regions_adjacent(province_a: StringName, province_b: StringName) -> bool:
	var wr: Node = get_node("/root/WorldRegistry")
	var prov: ProvinceRecord = wr.get_province(province_a)
	if prov == null:
		return false
	return prov.is_adjacent_to(province_b)


func regions_same_cultural_sphere(province_a: StringName, province_b: StringName) -> bool:
	var wr: Node = get_node("/root/WorldRegistry")
	var prov_a: ProvinceRecord = wr.get_province(province_a)
	var prov_b: ProvinceRecord = wr.get_province(province_b)
	if prov_a == null or prov_b == null:
		return false
	return prov_a.shares_cultural_sphere_with(prov_b)


# --- Coverage / awareness helpers ---

func has_coverage(_immortal_ref: StringName, _place: StringName) -> bool:
	# TODO: implement when ImmortalRegistry is populated
	return false


func awareness_of(_immortal_ref: StringName, _target_ref: StringName) -> StringName:
	# TODO: implement when ImmortalRegistry is populated
	return &"none"


# --- Curated set helpers ---

func scholar_professions() -> Array[StringName]:
	return [&"scholar", &"librarian", &"philosopher", &"academy_master"]


func institutional_kinds() -> Array[StringName]:
	return [&"library", &"academy", &"monastery", &"temple", &"council_house"]


# --- Compound trait pattern detection (§24.2) ---

const COMPOUND_TRAIT_THRESHOLD: int = 70
const COMPOUND_TRAIT_LOW_THRESHOLD: int = 30

# Six compound trait patterns from §24.2. Returns true if the character
# exhibits the named pattern based on trait thresholds.
func has_compound_trait_pattern(character: CharacterRecord, pattern_kind: StringName) -> bool:
	if character == null:
		return false
	match pattern_kind:
		&"dangerous_ruler":
			# High ambition + high paranoia
			return character.ambition >= COMPOUND_TRAIT_THRESHOLD and character.paranoia >= COMPOUND_TRAIT_THRESHOLD
		&"hunter":
			# High intellect + high curiosity
			return character.intellect >= COMPOUND_TRAIT_THRESHOLD and character.curiosity >= COMPOUND_TRAIT_THRESHOLD
		&"lieutenant_ideal":
			# High loyalty + high resilience
			return character.loyalty >= COMPOUND_TRAIT_THRESHOLD and character.resilience >= COMPOUND_TRAIT_THRESHOLD
		&"corruption_profile":
			# High greed + low loyalty
			return character.greed >= COMPOUND_TRAIT_THRESHOLD and character.loyalty <= COMPOUND_TRAIT_LOW_THRESHOLD
		&"religious_catalyst":
			# High piety + high charisma
			return character.piety >= COMPOUND_TRAIT_THRESHOLD and character.charisma >= COMPOUND_TRAIT_THRESHOLD
		&"apex_predator":
			# High paranoia + high ruthlessness + maximal public position
			return (character.paranoia >= COMPOUND_TRAIT_THRESHOLD
				and character.ruthlessness >= COMPOUND_TRAIT_THRESHOLD
				and character.public_position_tier == PublicPositionValues.MAXIMAL)
		_:
			push_error("Unknown compound trait pattern: %s" % pattern_kind)
			return false
