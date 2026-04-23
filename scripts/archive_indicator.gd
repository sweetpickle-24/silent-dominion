extends Control
## Small parchment tag beside Exposure/Purse. Clicking it opens the
## Archive (save slots) overlay. Also shows the F10 shortcut hint.

signal pressed

const HEIGHT: float = 30.0

const COLOR_PARCHMENT: Color      = Color(0.96, 0.92, 0.82, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.55, 0.42, 0.28, 0.7)
const COLOR_INK: Color            = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.22, 0.14, 0.06, 0.65)

var _panel: PanelContainer


func _ready() -> void:
	custom_minimum_size = Vector2(230, HEIGHT)
	mouse_filter = MOUSE_FILTER_PASS
	_build()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.mouse_filter = MOUSE_FILTER_STOP
	_panel.tooltip_text = "Open the archive — save or return to a stored season. (F10)"
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = COLOR_PARCHMENT
	sb.border_color = COLOR_PARCHMENT_EDGE
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.gui_input.connect(_on_gui_input)
	add_child(_panel)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	_panel.add_child(row)

	var prefix: Label = Label.new()
	prefix.text = "ARCHIVE:"
	prefix.add_theme_color_override("font_color", COLOR_INK_MUTED)
	prefix.add_theme_font_size_override("font_size", 10)
	row.add_child(prefix)

	var value: Label = Label.new()
	value.text = "Open"
	value.add_theme_color_override("font_color", COLOR_INK)
	value.add_theme_font_size_override("font_size", 13)
	row.add_child(value)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var hint: Label = Label.new()
	hint.text = "F10"
	hint.add_theme_color_override("font_color", COLOR_INK_MUTED)
	hint.add_theme_font_size_override("font_size", 10)
	row.add_child(hint)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not Prefs.reduced_motion:
			var tw: Tween = create_tween()
			tw.tween_property(_panel, "scale", Vector2(0.96, 0.96), 0.06)
			tw.tween_property(_panel, "scale", Vector2.ONE, 0.10)
		pressed.emit()
