extends Control
## Top-left chrome tag for the shadow figure's legend per §10.
##
## Shows the era-appropriate epithet (hidden until the legend has
## accumulated enough to be named) and, when applicable, a small
## "N hunter on your trail" secondary line that pulses the moment a
## new hunter emerges. Hover tooltip surfaces the numeric legend and
## per-kingdom awareness summary; deliberately tucked away so the
## table chrome stays quiet until the legend is loud.

const PAD: float = 10.0

const COLOR_PARCHMENT: Color = Color(0.96, 0.92, 0.82, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.55, 0.42, 0.28, 0.7)
const COLOR_INK: Color = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color = Color(0.22, 0.14, 0.06, 0.65)
const COLOR_HUNTER: Color = Color(0.62, 0.18, 0.12, 1.0)

# Dot color ramps with legend tier (0..100).
const COLOR_DOT_NONE: Color = Color(0.18, 0.34, 0.22, 1.0)
const COLOR_DOT_LOW:  Color = Color(0.40, 0.36, 0.14, 1.0)
const COLOR_DOT_MID:  Color = Color(0.62, 0.45, 0.10, 1.0)
const COLOR_DOT_HIGH: Color = Color(0.72, 0.28, 0.12, 1.0)
const COLOR_DOT_MAX:  Color = Color(0.55, 0.08, 0.08, 1.0)

var _panel: PanelContainer
var _epithet_label: Label
var _hunter_label: Label
var _dot: Panel


func _ready() -> void:
	custom_minimum_size = Vector2(260, 34)
	mouse_filter = MOUSE_FILTER_PASS
	_build()
	_refresh()
	Shadow.legend_changed.connect(_on_legend_changed)
	Shadow.hunter_emerged.connect(_on_hunter_emerged)
	Shadow.hunter_resolved.connect(_on_hunter_resolved)
	Shadow.awareness_changed.connect(_on_awareness_changed)


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

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	vbox.add_child(row)

	var prefix: Label = Label.new()
	prefix.text = "LEGEND:"
	prefix.add_theme_color_override("font_color", COLOR_INK_MUTED)
	prefix.add_theme_font_size_override("font_size", 10)
	row.add_child(prefix)

	_epithet_label = Label.new()
	_epithet_label.add_theme_color_override("font_color", COLOR_INK)
	_epithet_label.add_theme_font_size_override("font_size", 13)
	_epithet_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_epithet_label)

	_dot = Panel.new()
	_dot.custom_minimum_size = Vector2(10, 10)
	row.add_child(_dot)

	_hunter_label = Label.new()
	_hunter_label.add_theme_color_override("font_color", COLOR_HUNTER)
	_hunter_label.add_theme_font_size_override("font_size", 10)
	_hunter_label.visible = false
	vbox.add_child(_hunter_label)


func _refresh() -> void:
	var epithet: String = Shadow.epithet()
	if epithet.is_empty():
		_epithet_label.text = "— nothing yet —"
		_epithet_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
	else:
		_epithet_label.text = epithet
		_epithet_label.add_theme_color_override("font_color", COLOR_INK)

	_refresh_dot()
	_refresh_hunter_line()
	_refresh_tooltip()


func _refresh_dot() -> void:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	var lg: int = Shadow.legend
	if lg < 15:
		sb.bg_color = COLOR_DOT_NONE
	elif lg < 35:
		sb.bg_color = COLOR_DOT_LOW
	elif lg < 60:
		sb.bg_color = COLOR_DOT_MID
	elif lg < 85:
		sb.bg_color = COLOR_DOT_HIGH
	else:
		sb.bg_color = COLOR_DOT_MAX
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	_dot.add_theme_stylebox_override("panel", sb)


func _refresh_hunter_line() -> void:
	var n: int = Shadow.hunters.size()
	if n <= 0:
		_hunter_label.visible = false
		return
	_hunter_label.visible = true
	_hunter_label.text = ("%d hunter on your trail" % n) if n == 1 \
		else ("%d hunters on your trail" % n)


func _refresh_tooltip() -> void:
	var lg: int = Shadow.legend
	var parts: Array[String] = []
	parts.append("Legend: %d / 100" % lg)
	var named: int = 0
	for kid in Shadow.awareness_heat.keys():
		var tier: int = Shadow.awareness_tier_in(String(kid))
		if tier <= 0:
			continue
		named += 1
	if named > 0:
		parts.append("%d region%s with active awareness" % [named, "" if named == 1 else "s"])
	if Shadow.hunters.size() > 0:
		parts.append("Hunters do not sleep while this tag is up.")
	_panel.tooltip_text = "\n".join(parts)


# --- Signals ---------------------------------------------------------------

func _on_legend_changed(_v: int) -> void:
	_refresh()


func _on_awareness_changed(_kid: String, _tier: int) -> void:
	_refresh_tooltip()


func _on_hunter_emerged(_h: Dictionary) -> void:
	_refresh_hunter_line()
	_refresh_tooltip()
	if Prefs.reduced_motion:
		return
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(_panel, "scale", Vector2(1.08, 1.08), 0.10)
	tw.chain().tween_property(_panel, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_hunter_resolved(_id: String) -> void:
	_refresh_hunter_line()
	_refresh_tooltip()
