class_name Memoirs
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG
const _GameDayTickedEventScript := preload("res://scripts/data/events/game_day_ticked_event.gd")

var _event_bus: Node
var _logger: Node
var _time_keeper: Node

# Per-immortal libraries. Keyed by immortal_id. Until ImmortalRegistry is real,
# &"player" is the placeholder.
var _libraries: Dictionary = {}


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_event_bus.subscribe(
		_GameDayTickedEventScript,
		Callable(self, "_on_game_day_ticked"),
		100,
		&"",
		EndOfTickPhases.WORLD_SHARED,
	)
	if not _libraries.has(&"player"):
		var lib := MemoirsLibrary.new()
		lib.immortal_id = &"player"
		_libraries[&"player"] = lib
	_logger.info(LogChannels.MEMOIRS, "Memoirs mechanic ready", {"library_count": _libraries.size()})


func _on_game_day_ticked(event: GameDayTickedEvent) -> void:
	_check_staleness_transitions(event.day)


func _check_staleness_transitions(day: int) -> void:
	for immortal_id: StringName in _libraries.keys():
		var library: MemoirsLibrary = _libraries[immortal_id]
		for pattern: Pattern in library.patterns:
			var age: int = day - pattern.last_validated_day
			var new_state: StringName
			if age > StalenessValues.STALE_THRESHOLD_DAYS:
				new_state = StalenessValues.STALE
			elif age > StalenessValues.FRESH_THRESHOLD_DAYS:
				new_state = StalenessValues.AGING
			else:
				new_state = StalenessValues.FRESH
			if new_state != pattern.staleness_state:
				var old_state: StringName = pattern.staleness_state
				pattern.staleness_state = new_state
				var staleness_event := PatternStalenessChangedEvent.new()
				staleness_event.pattern_id = pattern.id
				staleness_event.immortal_id = immortal_id
				staleness_event.old_state = old_state
				staleness_event.new_state = new_state
				_event_bus.dispatch(staleness_event)
				_logger.info(LogChannels.MEMOIRS, "Pattern staleness transition", {
					"pattern_id": pattern.id,
					"old": old_state,
					"new": new_state,
				})


# --- Public API ---

func get_library(immortal_id: StringName) -> MemoirsLibrary:
	return _libraries.get(immortal_id, null)


func add_pattern(pattern: Pattern, immortal_id: StringName = &"player") -> void:
	assert(pattern != null and pattern.id != &"", "Pattern requires non-empty id")
	var library: MemoirsLibrary = _libraries.get(immortal_id)
	if library == null:
		library = MemoirsLibrary.new()
		library.immortal_id = immortal_id
		_libraries[immortal_id] = library
	assert(library.get_pattern(pattern.id) == null, "Duplicate pattern id %s" % pattern.id)
	library.patterns.append(pattern)


func validate_pattern(pattern_id: StringName, day: int, immortal_id: StringName = &"player") -> void:
	var library: MemoirsLibrary = _libraries.get(immortal_id)
	if library == null:
		push_error("validate_pattern: no library for immortal_id %s" % immortal_id)
		return
	var pattern: Pattern = library.get_pattern(pattern_id)
	if pattern == null:
		push_error("validate_pattern: no pattern %s" % pattern_id)
		return
	pattern.mark_validated(day)


func find_top_matches(category: StringName, context: RuleContext, n: int = 10, immortal_id: StringName = &"player") -> Array:
	var library: MemoirsLibrary = _libraries.get(immortal_id)
	if library == null:
		return []
	var category_matches: Array[Pattern] = library.patterns_by_category(category)
	var scored: Array = []
	for pattern: Pattern in category_matches:
		var sim: float = Similarity.compute(pattern, context)
		if sim > 0.0:
			scored.append({"pattern": pattern, "similarity": sim})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["similarity"] > b["similarity"])
	if scored.size() > n:
		scored = scored.slice(0, n)
	return scored


# --- Save/load support ---

func snapshot_state() -> Dictionary:
	return _libraries.duplicate(true)


func apply_state(libraries: Dictionary) -> void:
	_libraries = libraries.duplicate(true) if libraries != null else {}
	if not _libraries.has(&"player"):
		var lib := MemoirsLibrary.new()
		lib.immortal_id = &"player"
		_libraries[&"player"] = lib
	_logger.info(LogChannels.MEMOIRS, "Memoirs state applied from load", {"library_count": _libraries.size()})
