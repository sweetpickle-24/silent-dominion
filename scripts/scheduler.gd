extends Node
## Autoloaded as `Scheduler`. Fires tasks at a specific future game-day.
##
## Two kinds of deferred work are supported:
##
##  1. **Callable tasks** — engine-internal, transient. Not serialised. Use
##     for short-lived UI-side animations keyed to game time, or tests.
##
##  2. **Task descriptors** — a Dictionary with at least { "kind": StringName }.
##     These ARE serialised by the save system. When due, the scheduler
##     emits `task_due(descriptor)` and whoever cares (the action system,
##     a future plague system, etc.) responds.
##
## Day indexing uses `GameClock.absolute_day()` so month/year rollovers and
## deep-time gaps (decade speed) are handled for free.

signal task_due(descriptor: Dictionary)

const INVALID_HANDLE: int = -1

var _next_handle: int = 1

# Each entry:
# {
#   "handle":     int,
#   "fire_day":   int,
#   "descriptor": Dictionary | null,   # null for callable tasks
#   "callable":   Callable | null,
# }
var _tasks: Array = []


func _ready() -> void:
	DevLogger.write("Scheduler: ready")
	GameClock.day_passed.connect(_on_day_passed)


# --- Public API --------------------------------------------------------------

## Schedule a callable to fire `days` game-days from now. `days` of 0 fires
## on the very next day tick. Returns a handle that can be cancelled.
func schedule_in_days(days: int, callable: Callable) -> int:
	return _schedule(GameClock.absolute_day() + max(0, days), null, callable)


## Schedule a serialisable task descriptor. When the fire day arrives,
## `task_due(descriptor)` is emitted.
func schedule_task_in_days(days: int, descriptor: Dictionary) -> int:
	return _schedule(GameClock.absolute_day() + max(0, days), descriptor.duplicate(true), Callable())


## Same as above, but fires on an absolute game-day (useful for loaded
## saves that already know the target day).
func schedule_task_on_day(fire_day: int, descriptor: Dictionary) -> int:
	return _schedule(fire_day, descriptor.duplicate(true), Callable())


func cancel(handle: int) -> bool:
	for i in range(_tasks.size()):
		if int(_tasks[i]["handle"]) == handle:
			_tasks.remove_at(i)
			return true
	return false


func pending_count() -> int:
	return _tasks.size()


## Returns a snapshot of all serialisable pending tasks as plain data.
## Used by the save system. Transient callable tasks are intentionally
## omitted: they belong to the current process only.
func snapshot() -> Array:
	var out: Array = []
	for t in _tasks:
		if t["descriptor"] == null:
			continue
		out.append({
			"fire_day":   int(t["fire_day"]),
			"descriptor": (t["descriptor"] as Dictionary).duplicate(true),
		})
	return out


## Restore from a `snapshot()` array. Clears any existing pending tasks
## first. Fire-days are preserved verbatim; tasks already in the past
## relative to the current clock fire on the next day tick.
func restore(snap: Array) -> void:
	_tasks.clear()
	for entry in snap:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var fire_day: int = int(entry.get("fire_day", GameClock.absolute_day()))
		var desc_raw: Variant = entry.get("descriptor", {})
		var desc: Dictionary = (desc_raw as Dictionary).duplicate(true) if desc_raw is Dictionary else {}
		_schedule(fire_day, desc, Callable())


# --- Internals ---------------------------------------------------------------

func _schedule(fire_day: int, descriptor, callable: Callable) -> int:
	var handle: int = _next_handle
	_next_handle += 1
	_tasks.append({
		"handle":     handle,
		"fire_day":   fire_day,
		"descriptor": descriptor,
		"callable":   callable,
	})
	return handle


func _on_day_passed(_y: int, _m: int, _d: int) -> void:
	var today: int = GameClock.absolute_day()

	# Collect everything due this tick; mutate `_tasks` after, because a
	# fired task may itself enqueue new tasks and we don't want to double-
	# fire them in the same day.
	var due: Array = []
	var remaining: Array = []
	for t in _tasks:
		if int(t["fire_day"]) <= today:
			due.append(t)
		else:
			remaining.append(t)
	_tasks = remaining

	for t in due:
		if t["descriptor"] != null:
			task_due.emit((t["descriptor"] as Dictionary).duplicate(true))
		var c: Callable = t["callable"]
		if c.is_valid():
			c.call()
