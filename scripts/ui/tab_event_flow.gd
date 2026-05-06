extends VBoxContainer

var _event_display: RichTextLabel
var _logger: Node


func _ready() -> void:
	name = "Event Flow"
	_logger = (Engine.get_main_loop() as SceneTree).root.get_node("Logger")

	_event_display = RichTextLabel.new()
	_event_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_event_display.scroll_following = true
	_event_display.bbcode_enabled = false
	_event_display.selection_enabled = true
	add_child(_event_display)


func _process(_delta: float) -> void:
	var entries: Array = _logger.drain_overlay_queue()
	for entry: Dictionary in entries:
		if entry.channel != &"event_bus":
			continue
		var line: String = "day=%d tick=%d | %s" % [
			entry.day,
			entry.tick_index,
			entry.message,
		]
		if not entry.context.is_empty():
			var parts: PackedStringArray = PackedStringArray()
			for key: String in entry.context:
				parts.append("%s=%s" % [key, str(entry.context[key])])
			line += " | " + " | ".join(parts)
		_event_display.add_text(line + "\n")
