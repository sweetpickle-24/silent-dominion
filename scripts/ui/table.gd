extends Control

var _content_area: MarginContainer
var _current_panel: Node = null
var _compose_button: Button
var _inbox_button: Button
var _map_button: Button


func _ready() -> void:
	# Build the Table UI programmatically.
	var bg := ColorRect.new()
	bg.color = Color("#3d2914")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	# Nav tabs
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	vbox.add_child(nav)

	_compose_button = Button.new()
	_compose_button.text = "Compose"
	_compose_button.pressed.connect(_show_compose)
	nav.add_child(_compose_button)

	_inbox_button = Button.new()
	_inbox_button.text = "Inbox"
	_inbox_button.pressed.connect(_show_inbox)
	nav.add_child(_inbox_button)

	_map_button = Button.new()
	_map_button.text = "Map"
	_map_button.pressed.connect(_show_map)
	nav.add_child(_map_button)

	# Content area
	_content_area = MarginContainer.new()
	_content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_area.add_theme_constant_override("margin_top", 8)
	vbox.add_child(_content_area)

	_show_inbox()


func _show_compose() -> void:
	_swap_panel(_build_compose_panel())


func _show_inbox() -> void:
	_swap_panel(_build_inbox_panel())


func _show_map() -> void:
	_swap_panel(_build_map_panel())


func _swap_panel(new_panel: Control) -> void:
	if _current_panel != null:
		_current_panel.queue_free()
	_current_panel = new_panel
	_content_area.add_child(new_panel)


# --- Panel builders ---

func _build_compose_panel() -> Control:
	var panel := preload("res://scripts/ui/compose_panel.gd").new()
	return panel


func _build_inbox_panel() -> Control:
	var panel := preload("res://scripts/ui/inbox_panel.gd").new()
	return panel


func _build_map_panel() -> Control:
	var panel := preload("res://scripts/ui/map_panel.gd").new()
	return panel
