extends VBoxContainer

var _log_display: RichTextLabel
var _channel_filter: OptionButton
var _level_filter: OptionButton
var _pause_button: Button
var _paused: bool = false
var _selected_channel: StringName = &""
var _selected_level: int = 0  # DEBUG

var _logger: Node


func _ready() -> void:
	name = "Log Stream"
	_logger = (Engine.get_main_loop() as SceneTree).root.get_node("Logger")

	var toolbar := HBoxContainer.new()
	add_child(toolbar)

	var ch_label := Label.new()
	ch_label.text = "Channel:"
	toolbar.add_child(ch_label)

	_channel_filter = OptionButton.new()
	_channel_filter.add_item("All", 0)
	_channel_filter.item_selected.connect(_on_channel_selected)
	toolbar.add_child(_channel_filter)

	var lv_label := Label.new()
	lv_label.text = "Level:"
	toolbar.add_child(lv_label)

	_level_filter = OptionButton.new()
	_level_filter.add_item("DEBUG", 0)
	_level_filter.add_item("INFO", 1)
	_level_filter.add_item("WARN", 2)
	_level_filter.add_item("ERROR", 3)
	_level_filter.selected = 0
	_level_filter.item_selected.connect(_on_level_selected)
	toolbar.add_child(_level_filter)

	_pause_button = Button.new()
	_pause_button.text = "Pause"
	_pause_button.toggle_mode = true
	_pause_button.toggled.connect(_on_pause_toggled)
	toolbar.add_child(_pause_button)

	_log_display = RichTextLabel.new()
	_log_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_display.scroll_following = true
	_log_display.bbcode_enabled = false
	_log_display.selection_enabled = true
	add_child(_log_display)


func _process(_delta: float) -> void:
	if _paused:
		return
	var entries: Array = _logger.drain_overlay_queue()
	for entry: Dictionary in entries:
		if _selected_channel != &"" and entry.channel != _selected_channel:
			continue
		if entry.level < _selected_level:
			continue
		var level_names: Array = ["DEBUG", "INFO", "WARN", "ERROR"]
		var level_name: String = level_names[entry.level] if entry.level < level_names.size() else "?"
		var line: String = "[%s] [%s] day=%d era=%s | %s" % [
			level_name,
			entry.channel,
			entry.day,
			entry.era,
			entry.message,
		]
		if not entry.context.is_empty():
			var parts: PackedStringArray = PackedStringArray()
			for key: String in entry.context:
				parts.append("%s=%s" % [key, str(entry.context[key])])
			line += " | " + " | ".join(parts)
		_log_display.add_text(line + "\n")


func _on_channel_selected(index: int) -> void:
	if index == 0:
		_selected_channel = &""
	else:
		_selected_channel = StringName(_channel_filter.get_item_text(index))


func _on_level_selected(index: int) -> void:
	_selected_level = index


func _on_pause_toggled(pressed: bool) -> void:
	_paused = pressed
	_pause_button.text = "Resume" if pressed else "Pause"
