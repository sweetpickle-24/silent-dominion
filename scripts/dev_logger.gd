extends Node

var _log_path: String
var _file: FileAccess

func _ready() -> void:
	_log_path = ProjectSettings.globalize_path("res://") + "godot_output.txt"
	_file = FileAccess.open(_log_path, FileAccess.WRITE)
	if _file:
		write("=== Session started %s ===" % Time.get_datetime_string_from_system())
		write("Log path: " + _log_path)
	else:
		push_error("DevLogger: failed to open log file at " + _log_path)

func write(msg: String) -> void:
	var line = "[%s] %s" % [Time.get_datetime_string_from_system(), msg]
	print(line)
	if _file:
		_file.store_line(line)
		_file.flush()

# Backwards-compatible alias so callsites using DevLogger.log() keep working.
# Name is `log_line` instead of `log` because the latter shadows the built-in
# natural-log math function and fails to resolve inside this class body.
func log_line(msg: String) -> void:
	write(msg)

func error(msg: String) -> void:
	write("ERROR: " + msg)
	push_error(msg)

func warn(msg: String) -> void:
	write("WARN: " + msg)
	push_warning(msg)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		write("=== Session ended ===")
		if _file:
			_file.close()
