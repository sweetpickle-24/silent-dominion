class_name Memoirs
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG
const _GameDayTickedEventScript := preload("res://scripts/data/events/game_day_ticked_event.gd")
const _SchemeResolvedEventScript := preload("res://scripts/data/events/scheme_resolved_event.gd")
const _EraTransitionedEventScript := preload("res://scripts/data/events/era_transitioned_event.gd")

var _event_bus: Node
var _logger: Node
var _time_keeper: Node

# Per-immortal libraries. Keyed by immortal_id. Until ImmortalRegistry is real,
# &"player" is the placeholder.
var _libraries: Dictionary = {}
var _tick_sub  # SubscriptionHandle
var _scheme_resolved_sub  # SubscriptionHandle
var _era_transitioned_sub  # SubscriptionHandle


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_tick_sub = _event_bus.subscribe(
		_GameDayTickedEventScript,
		Callable(self, "_on_game_day_ticked"),
		100,
		&"",
		EndOfTickPhases.WORLD_SHARED,
	)
	var immortal_registry: Node = get_node("/root/ImmortalRegistry")
	var player_immortal: ImmortalRecord = immortal_registry.get_player()
	if player_immortal != null and not _libraries.has(player_immortal.id):
		var lib := MemoirsLibrary.new()
		lib.immortal_id = player_immortal.id
		_libraries[player_immortal.id] = lib
	_scheme_resolved_sub = _event_bus.subscribe(
		_SchemeResolvedEventScript,
		Callable(self, "_on_scheme_resolved"),
		100,
		&"",
		EndOfTickPhases.PER_IMMORTAL,
	)
	_era_transitioned_sub = _event_bus.subscribe(
		_EraTransitionedEventScript,
		Callable(self, "_on_era_transitioned"),
		100,
		&"",
		EndOfTickPhases.WORLD_SHARED,
	)
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"memoirs_libraries",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)
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


# --- SchemeResolved consumer ---

func _on_scheme_resolved(event: SchemeResolvedEvent) -> void:
	if event.outcome != SchemeOutcomes.SUCCESS:
		return
	_learn_from_scheme(event)


func _learn_from_scheme(event: SchemeResolvedEvent) -> void:
	# Step 7 minimal: every successful scheme of a pattern-eligible action_type
	# creates a brand new Pattern. The full C1 algorithm (validate-existing /
	# create-new / variant-update) is deferred.
	var category: StringName = _action_type_to_category(event.action_type)
	if category == &"":
		return
	var library: MemoirsLibrary = _libraries.get(event.immortal_id)
	if library == null:
		return
	var pattern := Pattern.new()
	pattern.id = StringName("learned_%s_%d" % [event.action_type, event.resolved_at_day])
	pattern.name = "Learned from %s on day %d" % [event.target_ref, event.resolved_at_day]
	pattern.category = category
	pattern.description = "Auto-learned pattern (Step 7 placeholder learning)"
	pattern.learned_from_event_id = event.scheme_id
	pattern.learned_at_day = event.resolved_at_day
	var world_registry: Node = get_node("/root/WorldRegistry")
	var place: PlaceRecord = world_registry.get_place(event.target_place_ref)
	if place != null:
		pattern.region_scope = place.region
	pattern.era = _time_keeper.current_era
	pattern.last_validated_day = event.resolved_at_day
	pattern.staleness_state = StalenessValues.FRESH
	pattern.success_count = 1
	library.patterns.append(pattern)
	_logger.info(LogChannels.MEMOIRS, "Pattern learned from scheme", {
		"pattern_id": pattern.id,
		"category": category,
		"from_scheme": event.scheme_id,
	})


func _action_type_to_category(action_type: StringName) -> StringName:
	match action_type:
		ActionTypeValues.PLANT_IDEA: return PatternCategories.PLANT_IDEA
		ActionTypeValues.SEED_RUMOR: return PatternCategories.SEED_RUMOR
		ActionTypeValues.CULTIVATE: return PatternCategories.CULTIVATE
		_: return &""


# --- Era transition consumer ---

func _on_era_transitioned(event: EraTransitionedEvent) -> void:
	# C2 spec: "flags pre-transition patterns as potentially aging."
	# Flag-as-aging mechanic is deferred design. Step 10 logs only.
	var pre_transition_count: int = 0
	for library_id: StringName in _libraries.keys():
		var library: MemoirsLibrary = _libraries[library_id]
		for pattern: Pattern in library.patterns:
			if pattern.era == event.old_era:
				pre_transition_count += 1
	_logger.info(LogChannels.MEMOIRS, "Era transition received", {
		"old_era": event.old_era,
		"new_era": event.new_era,
		"patterns_in_old_era": pre_transition_count,
		"note": "flag-as-aging deferred; patterns logged only",
	})


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
