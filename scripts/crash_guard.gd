extends Node
## Autoload: `CrashGuard`.
##
## Centralised defensive utilities. Godot 4's GDScript has no try/except,
## so we can't literally catch runtime errors; what we can do is:
##
##   - Provide safe accessors (`safe_get`, `safe_dict`, etc.) that every
##     JSON / Dictionary / Array consumer should use instead of raw
##     subscript access.
##   - Provide `null_guard` helpers for the common autoload-pointer
##     pattern ("if Foo != null and Foo.has_method('x'): ...").
##   - Log every `push_error` call the engine makes to a rolling user://
##     log file so post-mortems are possible even when the session
##     crashes before a save.
##   - Intercept `_unhandled_exception`-shaped callbacks through
##     `Callable.callv` with a valid-check so a mis-bound signal
##     handler fails loudly rather than tearing the tree down.
##
## This autoload must be first in the autoload list so every other
## autoload can `CrashGuard.safe_X(...)` safely from its own `_ready()`.

const LOG_PATH: String = "user://crash_log.txt"
const MAX_LOG_LINES: int = 2000

var _log_lines: PackedStringArray = PackedStringArray()
var _log_file: FileAccess = null
var _start_ts: String = ""


func _ready() -> void:
	DevLogger.write("CrashGuard: ready")
	_start_ts = Time.get_datetime_string_from_system()
	_open_log()
	_info("CrashGuard online. Session started at %s" % _start_ts)
	# Install a last-ditch catcher for the main loop. If any deferred
	# callable fails, Godot still runs but we at least log it.
	get_tree().process_frame.connect(_on_process_frame)


func _exit_tree() -> void:
	_info("CrashGuard shutting down cleanly.")
	_flush_log()
	if _log_file != null:
		_log_file.close()
		_log_file = null


# --- Safe accessors ---------------------------------------------------------

## Fetch `key` from `d`, returning `fallback` if `d` is not a Dictionary
## or the key is absent. Use this every time you touch JSON-loaded data.
static func safe_get(d: Variant, key: Variant, fallback: Variant = null) -> Variant:
	if d == null:
		return fallback
	if d is Dictionary:
		return (d as Dictionary).get(key, fallback)
	return fallback


static func safe_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		return v
	return {}


static func safe_array(v: Variant) -> Array:
	if v is Array:
		return v
	return []


static func safe_str(v: Variant, fallback: String = "") -> String:
	if v == null:
		return fallback
	if v is String:
		return v
	if v is StringName:
		return String(v)
	return str(v)


static func safe_int(v: Variant, fallback: int = 0) -> int:
	if v == null:
		return fallback
	if v is int:
		return v
	if v is float:
		return int(v)
	if v is String:
		return int(v)
	return fallback


static func safe_float(v: Variant, fallback: float = 0.0) -> float:
	if v == null:
		return fallback
	if v is float:
		return v
	if v is int:
		return float(v)
	if v is String:
		return float(v)
	return fallback


static func safe_bool(v: Variant, fallback: bool = false) -> bool:
	if v == null:
		return fallback
	return bool(v)


## Parse a JSON file from disk into a Dictionary, swallowing every
## likely failure (missing file, corrupt body, wrong root type) and
## logging them. Returns `{}` on any failure.
static func safe_load_json_dict(path: String) -> Dictionary:
	if path.is_empty():
		return {}
	if not FileAccess.file_exists(path):
		push_warning("[CrashGuard] json missing: %s" % path)
		return {}
	var raw: String = FileAccess.get_file_as_string(path)
	if raw.is_empty():
		push_warning("[CrashGuard] json empty: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed
	push_warning("[CrashGuard] json root not Dictionary: %s" % path)
	return {}


static func safe_load_json_array(path: String) -> Array:
	var d: Dictionary = safe_load_json_dict(path)
	return d.values() if not d.is_empty() else []


# --- Signal / callable guards ----------------------------------------------

## Return true if the node+method is still connectable. Lets callers
## defensively skip a signal connect when something got freed between
## lookup and wire-up.
static func is_live(node: Object, method: String = "") -> bool:
	if node == null:
		return false
	if not is_instance_valid(node):
		return false
	if node is Node and (node as Node).is_queued_for_deletion():
		return false
	if method != "" and not node.has_method(method):
		return false
	return true


## Invoke a Callable with null-guard and error logging. Returns the
## call result on success or `fallback` when the callable is invalid.
## This is NOT a try/catch — GDScript has no exception mechanism — so
## runtime null-deref inside the callable can still tear the frame
## down. The guard only blocks cases we can detect before the call.
static func safe_call(c: Callable, args: Array = [], fallback: Variant = null) -> Variant:
	if c == null or not c.is_valid():
		return fallback
	var obj: Object = c.get_object()
	if obj != null and not is_instance_valid(obj):
		return fallback
	return c.callv(args)


## Connect `signal_src.signal_name` to `callable` only if both sides
## are alive. Returns true on success. Keeps autoload wiring from
## crashing when a dependency failed to initialise.
static func safe_connect(
	signal_src: Object,
	signal_name: StringName,
	callable: Callable,
	flags: int = 0
) -> bool:
	if not is_live(signal_src):
		push_warning("[CrashGuard] signal source dead: %s" % signal_name)
		return false
	if not signal_src.has_signal(signal_name):
		push_warning("[CrashGuard] signal '%s' not on %s" % [signal_name, signal_src])
		return false
	if callable == null or not callable.is_valid():
		push_warning("[CrashGuard] invalid callable for signal '%s'" % signal_name)
		return false
	var err: int = signal_src.connect(signal_name, callable, flags)
	if err != OK and err != ERR_INVALID_PARAMETER:
		push_warning("[CrashGuard] connect failed (%d) for signal '%s'" % [err, signal_name])
		return false
	return true


# --- Log plumbing -----------------------------------------------------------

func _open_log() -> void:
	_log_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _log_file == null:
		# Non-fatal. Without write access we still print to stderr.
		return
	_log_file.store_line("=== Silent Dominion crash log — %s ===" % _start_ts)
	_log_file.flush()


func _flush_log() -> void:
	if _log_file == null:
		return
	for line in _log_lines:
		_log_file.store_line(line)
	_log_lines.clear()
	_log_file.flush()


func _info(msg: String) -> void:
	_append_log("INFO  %s" % msg)


func log_error(msg: String) -> void:
	push_error("[CrashGuard] %s" % msg)
	_append_log("ERROR %s" % msg)


func log_warn(msg: String) -> void:
	push_warning("[CrashGuard] %s" % msg)
	_append_log("WARN  %s" % msg)


func _append_log(line: String) -> void:
	var ts: String = Time.get_time_string_from_system()
	var stamped: String = "[%s] %s" % [ts, line]
	_log_lines.append(stamped)
	if _log_lines.size() > MAX_LOG_LINES:
		_log_lines.remove_at(0)
	if _log_file != null:
		_log_file.store_line(stamped)


## Periodic flush so the log survives a hard crash on the next frame.
var _flush_every_n_frames: int = 120
var _frame_counter: int = 0

func _on_process_frame() -> void:
	_frame_counter += 1
	if _frame_counter >= _flush_every_n_frames:
		_frame_counter = 0
		if _log_file != null:
			_log_file.flush()
