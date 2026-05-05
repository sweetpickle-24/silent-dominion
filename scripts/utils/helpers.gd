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


func regions_adjacent(_region_a: StringName, _region_b: StringName) -> bool:
	# TODO: implement when WorldRegistry has region adjacency data
	return false


func regions_same_cultural_sphere(_region_a: StringName, _region_b: StringName) -> bool:
	# TODO: implement when WorldRegistry has cultural sphere data
	return false


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
