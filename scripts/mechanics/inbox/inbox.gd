class_name Inbox
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG
const _GameDayTickedEventScript := preload("res://scripts/data/events/game_day_ticked_event.gd")

var _logger: Node
var _time_keeper: Node
var _immortal_registry: Node
var _event_bus: Node
var _tick_subscription  # SubscriptionHandle

var _inboxes: Dictionary = {}   # StringName immortal_id -> InboxState

const ARCHIVE_AFTER_DAYS: int = 90


func _ready() -> void:
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_immortal_registry = get_node("/root/ImmortalRegistry")
	_event_bus = get_node("/root/EventBus")
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"inbox_state",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)
	var player: ImmortalRecord = _immortal_registry.get_player()
	if player != null:
		_ensure_inbox(player.id)
	_tick_subscription = _event_bus.subscribe(
		_GameDayTickedEventScript,
		Callable(self, "_on_game_day_ticked"),
		200,
		&"",
		EndOfTickPhases.UI,
	)
	_logger.info(LogChannels.INBOX, "Inbox mechanic ready")


func _on_game_day_ticked(event: GameDayTickedEvent) -> void:
	var current_day: int = event.day
	for immortal_id: StringName in _inboxes.keys():
		var state: InboxState = _inboxes[immortal_id]
		for letter: Letter in state.letters:
			if letter.tier == &"active" and (current_day - letter.day_received) > ARCHIVE_AFTER_DAYS:
				letter.tier = &"archive"


# --- Public API ---

func add_letter(letter: Letter) -> void:
	var state: InboxState = _ensure_inbox(letter.immortal_id)
	state.letters.append(letter)


func next_letter_id() -> StringName:
	var player: ImmortalRecord = _immortal_registry.get_player()
	var state: InboxState = _ensure_inbox(player.id)
	var seq: int = state.next_letter_seq
	state.next_letter_seq += 1
	return StringName("letter_%d" % seq)


func get_inbox(immortal_id: StringName) -> InboxState:
	return _inboxes.get(immortal_id, null)


func get_active_letters(immortal_id: StringName = &"") -> Array:
	if immortal_id == &"":
		var player: ImmortalRecord = _immortal_registry.get_player()
		if player == null:
			return []
		immortal_id = player.id
	var state: InboxState = _inboxes.get(immortal_id)
	if state == null:
		return []
	return state.get_active_letters()


func mark_read(letter_id: StringName, immortal_id: StringName = &"") -> void:
	if immortal_id == &"":
		var player: ImmortalRecord = _immortal_registry.get_player()
		if player == null:
			return
		immortal_id = player.id
	var state: InboxState = _inboxes.get(immortal_id)
	if state == null:
		return
	var letter: Letter = state.find_letter(letter_id)
	if letter != null:
		letter.mark_read(_time_keeper.current_day)


func _ensure_inbox(immortal_id: StringName) -> InboxState:
	if not _inboxes.has(immortal_id):
		var state := InboxState.new()
		state.immortal_id = immortal_id
		_inboxes[immortal_id] = state
	return _inboxes[immortal_id]


# --- Save/load ---

func snapshot_state() -> Dictionary:
	return {"inboxes": _inboxes.duplicate(true)}


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_inboxes = state.get("inboxes", {}).duplicate(true)
	var player: ImmortalRecord = _immortal_registry.get_player()
	if player != null and not _inboxes.has(player.id):
		_ensure_inbox(player.id)
	_logger.info(LogChannels.INBOX, "Inbox state applied from load")
