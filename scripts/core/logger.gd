extends Node

enum Level { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }

var _LEVEL_NAMES: PackedStringArray = PackedStringArray(["DEBUG", "INFO", "WARN", "ERROR"])

# Per-channel level threshold. Channels not in this dictionary use _default_level.
var _channel_levels: Dictionary = {}

# Default level for channels without an explicit override.
var _default_level: Level = Level.INFO


func _ready() -> void:
	info(LogChannels.DEBUG, "Logger ready")


# --- Public API ---

func debug(channel: StringName, message: String, context: Dictionary = {}) -> void:
	_log(Level.DEBUG, channel, message, context)


func info(channel: StringName, message: String, context: Dictionary = {}) -> void:
	_log(Level.INFO, channel, message, context)


func warn(channel: StringName, message: String, context: Dictionary = {}) -> void:
	_log(Level.WARN, channel, message, context)


func error(channel: StringName, message: String, context: Dictionary = {}) -> void:
	_log(Level.ERROR, channel, message, context)


func enabled_for(channel: StringName, level: Level) -> bool:
	var threshold: Level = _channel_levels.get(channel, _default_level) as Level
	return level >= threshold


func set_channel_level(channel: StringName, level: Level) -> void:
	_channel_levels[channel] = level


func set_default_level(level: Level) -> void:
	_default_level = level


# --- Internal ---

func _log(level: Level, channel: StringName, message: String, context: Dictionary) -> void:
	if not enabled_for(channel, level):
		return

	# Build the timestamp / simulation-context prefix.
	var day_str: String = ""
	var era_str: String = ""
	var tick_str: String = ""

	# TimeKeeper may not exist yet or may still be a stub during early autoload init.
	var tk: Node = get_node_or_null("/root/TimeKeeper")
	if tk and tk.get("current_day") != null:
		day_str = "day=%d " % [tk.current_day]
		era_str = "era=%s " % [tk.current_era]
		if tk.get("_tick_count_today") != null:
			tick_str = "tick_index=%d " % [tk._tick_count_today]

	var level_name: String = _LEVEL_NAMES[level]

	# Context key=value pairs
	var ctx_parts: String = ""
	if not context.is_empty():
		var parts: PackedStringArray = PackedStringArray()
		for key: String in context:
			parts.append("%s=%s" % [key, str(context[key])])
		ctx_parts = " | " + " | ".join(parts)

	var line: String = "[%s] [%s] %s%s%s| %s%s" % [
		level_name,
		channel,
		day_str,
		era_str,
		tick_str,
		message,
		ctx_parts,
	]

	if level >= Level.ERROR:
		printerr(line)
	else:
		print(line)

	# TODO: text file sink (rolling session log)
	# TODO: ring buffer sink (release builds, ~10000 messages)
	# TODO: debug overlay push (development builds)
