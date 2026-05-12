extends Control

var _content_area: PanelContainer
var _current_panel: Node = null
var _compose_button: Button
var _inbox_button: Button
var _map_button: Button
var _active_tab: Button = null
var _era_label: Label
var _date_label: Label
var _speed_label: Label
var _time_keeper: Node

const _SEAL_RED := Color("#8b3a2a")
const _DESK_LIGHT := Color("#5a4530")
const _DESK_TEXT := Color("#d4c5a8")
const _DESK_TEXT_SEC := Color("#9a8a70")


func _ready() -> void:
	_time_keeper = (Engine.get_main_loop() as SceneTree).root.get_node("TimeKeeper")

	# Apply theme
	var table_theme: Theme = load("res://data/themes/table_theme.tres")
	if table_theme:
		theme = table_theme

	# Background
	var bg := ColorRect.new()
	bg.color = Color("#2a1f17")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# === TopBar ===
	var topbar := HBoxContainer.new()
	topbar.custom_minimum_size.y = 40
	topbar.add_theme_constant_override("separation", 16)
	vbox.add_child(topbar)

	var serif_font: Font = load("res://data/fonts/EBGaramond-Regular.ttf")

	_era_label = Label.new()
	_era_label.text = EraValues.DISPLAY_NAMES.get(_time_keeper.current_era, "")
	if serif_font:
		_era_label.add_theme_font_override("font", serif_font)
	_era_label.add_theme_font_size_override("font_size", 22)
	_era_label.add_theme_color_override("font_color", _DESK_TEXT)
	topbar.add_child(_era_label)

	_date_label = Label.new()
	_date_label.text = _time_keeper.get_display_date()
	_date_label.add_theme_color_override("font_color", _DESK_TEXT_SEC)
	topbar.add_child(_date_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topbar.add_child(spacer)

	_speed_label = Label.new()
	_speed_label.add_theme_color_override("font_color", _DESK_TEXT)
	_speed_label.add_theme_font_size_override("font_size", 16)
	topbar.add_child(_speed_label)
	_update_speed_display()

	_time_keeper.speed_changed.connect(func(_s): _update_speed_display())
	_time_keeper.pause_changed.connect(func(_p): _update_speed_display())
	_time_keeper.era_about_to_transition.connect(func(_o, n): _era_label.text = EraValues.DISPLAY_NAMES.get(n, str(n)))

	# === Nav Tabs ===
	var nav := HBoxContainer.new()
	nav.custom_minimum_size.y = 48
	nav.add_theme_constant_override("separation", 8)
	vbox.add_child(nav)

	_compose_button = _make_tab_button("Compose")
	_compose_button.pressed.connect(_show_compose)
	nav.add_child(_compose_button)

	_inbox_button = _make_tab_button("Inbox")
	_inbox_button.pressed.connect(_show_inbox)
	nav.add_child(_inbox_button)

	_map_button = _make_tab_button("Map")
	_map_button.pressed.connect(_show_map)
	nav.add_child(_map_button)

	# === Content Area ===
	_content_area = PanelContainer.new()
	_content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_content_area)

	_show_inbox()


func _process(_delta: float) -> void:
	_date_label.text = _time_keeper.get_display_date()


func _make_tab_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", _DESK_TEXT_SEC)
	return btn


func _set_active_tab(btn: Button) -> void:
	if _active_tab != null:
		_active_tab.add_theme_color_override("font_color", _DESK_TEXT_SEC)
	_active_tab = btn
	btn.add_theme_color_override("font_color", _DESK_TEXT)


func _update_speed_display() -> void:
	if _time_keeper.is_paused:
		_speed_label.text = "|| Paused"
	else:
		_speed_label.text = "> %s" % _time_keeper.current_speed


func _show_compose() -> void:
	_set_active_tab(_compose_button)
	_swap_panel(preload("res://scripts/ui/compose_panel.gd").new())


func _show_inbox() -> void:
	_set_active_tab(_inbox_button)
	_swap_panel(preload("res://scripts/ui/inbox_panel.gd").new())


func _show_map() -> void:
	_set_active_tab(_map_button)
	_swap_panel(preload("res://scripts/ui/map_panel.gd").new())


func _swap_panel(new_panel: Control) -> void:
	if _current_panel != null:
		_current_panel.queue_free()
	_current_panel = new_panel
	_content_area.add_child(new_panel)


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
