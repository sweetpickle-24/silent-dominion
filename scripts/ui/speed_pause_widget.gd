extends MarginContainer

var _era_label: Label
var _date_label: Label
var _speed_label: Label
var _time_keeper: Node


func _ready() -> void:
	_time_keeper = (Engine.get_main_loop() as SceneTree).root.get_node("TimeKeeper")

	offset_left = 10
	offset_top = 10

	var vbox := VBoxContainer.new()
	add_child(vbox)

	_era_label = Label.new()
	_era_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_era_label)

	_date_label = Label.new()
	_date_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_date_label)

	_speed_label = Label.new()
	_speed_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_speed_label)

	_time_keeper.speed_changed.connect(_on_speed_changed)
	_time_keeper.pause_changed.connect(_on_pause_changed)
	_time_keeper.era_about_to_transition.connect(_on_era_about_to_transition)

	_refresh_display()


func _process(_delta: float) -> void:
	_date_label.text = _time_keeper.get_display_date()


func _refresh_display() -> void:
	_era_label.text = EraValues.DISPLAY_NAMES.get(_time_keeper.current_era, str(_time_keeper.current_era))
	_date_label.text = _time_keeper.get_display_date()
	_speed_label.text = _format_speed()


func _format_speed() -> String:
	if _time_keeper.is_paused:
		return "|| Paused"
	return "> %s" % _time_keeper.current_speed


func _on_speed_changed(_new_speed: StringName) -> void:
	_speed_label.text = _format_speed()


func _on_pause_changed(_now_paused: bool) -> void:
	_speed_label.text = _format_speed()


func _on_era_about_to_transition(_old_era: StringName, new_era: StringName) -> void:
	_era_label.text = EraValues.DISPLAY_NAMES.get(new_era, str(new_era))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_pause"):
		_time_keeper.set_paused(not _time_keeper.is_paused, &"player")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_x1"):
		_time_keeper.set_speed(SpeedValues.X1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_x2"):
		_time_keeper.set_speed(SpeedValues.X2)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_x4"):
		_time_keeper.set_speed(SpeedValues.X4)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_x16"):
		_time_keeper.set_speed(SpeedValues.X16)
		get_viewport().set_input_as_handled()
