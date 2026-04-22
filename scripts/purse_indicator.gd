extends Control
## Small parchment tag sitting beside the Exposure indicator. Reports
## the player's current purse state as a qualitative band only (§7.6).
##
## No number is shown. Hover for the short blurb.

const HEIGHT: float = 30.0

const COLOR_PARCHMENT: Color      = Color(0.96, 0.92, 0.82, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.55, 0.42, 0.28, 0.7)
const COLOR_INK: Color            = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.22, 0.14, 0.06, 0.65)

const BAND_COLORS: Dictionary = {
	&"bone_dry":    Color(0.55, 0.08, 0.08, 1.0),
	&"thin":        Color(0.72, 0.28, 0.12, 1.0),
	&"lean":        Color(0.62, 0.45, 0.10, 1.0),
	&"comfortable": Color(0.40, 0.36, 0.14, 1.0),
	&"deep":        Color(0.18, 0.34, 0.22, 1.0),
	&"bottomless":  Color(0.18, 0.34, 0.22, 1.0),
}

var _panel: PanelContainer
var _dot: Panel
var _label_prefix: Label
var _label_band: Label


func _ready() -> void:
	custom_minimum_size = Vector2(230, HEIGHT)
	mouse_filter = MOUSE_FILTER_PASS
	_build()
	_refresh()
	Purse.band_changed.connect(_on_band_changed)
	Purse.value_changed.connect(_on_value_changed)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.mouse_filter = MOUSE_FILTER_STOP
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
	add_child(_panel)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	_panel.add_child(row)

	_label_prefix = Label.new()
	_label_prefix.text = "PURSE:"
	_label_prefix.add_theme_color_override("font_color", COLOR_INK_MUTED)
	_label_prefix.add_theme_font_size_override("font_size", 10)
	row.add_child(_label_prefix)

	_label_band = Label.new()
	_label_band.add_theme_color_override("font_color", COLOR_INK)
	_label_band.add_theme_font_size_override("font_size", 13)
	row.add_child(_label_band)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_dot = Panel.new()
	_dot.custom_minimum_size = Vector2(10, 10)
	row.add_child(_dot)


func _refresh() -> void:
	_label_band.text = Purse.band_name()
	_panel.tooltip_text = Purse.band_blurb()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = BAND_COLORS.get(Purse.band(), COLOR_INK)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	_dot.add_theme_stylebox_override("panel", sb)


func _on_band_changed(_band: StringName) -> void:
	_refresh()
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(_panel, "scale", Vector2(1.06, 1.06), 0.10)
	tw.chain().tween_property(_panel, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_value_changed(_v: int) -> void:
	_panel.tooltip_text = Purse.band_blurb()
