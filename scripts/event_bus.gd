extends Node
## Global signal hub. Autoloaded as `EventBus`.
##
## Systems that want to broadcast or listen to cross-cutting events do it
## here instead of holding direct references to each other. This keeps the
## simulation, UI, and persistence layers decoupled.
##
## Rules of thumb:
##  - If a signal is owned by one system (e.g. GameClock ticks, Inbox
##    letters changed), emit it from that system directly.
##  - If a signal crosses system boundaries (a simulation tick wants to
##    reach the UI, an action wants to reach the inbox), route it here.

# --- Simulation-wide lifecycle ------------------------------------------------

signal world_loaded
signal simulation_started
signal simulation_paused

# --- Action / result channel --------------------------------------------------
#
# Fired when the player queues an action from the table. Consumed by the
# simulation to schedule resolution, and by the UI for optimistic feedback.
signal action_issued(action_id: StringName, payload: Dictionary)

# Fired when a pending action resolves, regardless of success/failure.
# `result` typically contains at least { "success": bool, "summary": String }.
signal action_resolved(action_id: StringName, result: Dictionary)

# --- Intelligence / inbox channel ---------------------------------------------
#
# Fired when any simulation system wants to deliver a letter to the player.
# InboxManager listens to this and appends to the stack.
signal letter_delivered(letter: Letter)

# Broadcast when a world-tier event occurs that should be widely known.
# PublicNews (future) will render these; intelligence systems may mutate
# them into letters from operatives.
signal public_event(event: Dictionary)

# Fired by WorldAI whenever an actor's death is registered — natural or
# otherwise. Other systems (Whispers, Actors registry, Notifications)
# listen to tidy up state that referenced the dead actor.
#   actor_id:    StringName — the deceased
#   was_host:    bool        — whether they were above the host threshold
#   cause:       StringName — &"age", &"assassination", etc.
signal actor_died(actor_id: StringName, was_host: bool, cause: StringName)

# --- Save / load --------------------------------------------------------------

signal save_requested(path: String)
signal save_completed(path: String)
signal load_requested(path: String)
signal load_completed(path: String)


func _ready() -> void:
	# EventBus itself does nothing; it only carries signals. Logging here
	# makes debugging signal storms easier during development.
	if OS.is_debug_build():
		action_issued.connect(_log_action_issued)
		action_resolved.connect(_log_action_resolved)


func _log_action_issued(action_id: StringName, payload: Dictionary) -> void:
	print("[EventBus] action_issued: %s  payload=%s" % [action_id, payload])


func _log_action_resolved(action_id: StringName, result: Dictionary) -> void:
	print("[EventBus] action_resolved: %s  result=%s" % [action_id, result])
