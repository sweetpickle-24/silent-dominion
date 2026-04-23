class_name StyleTokens
extends RefCounted
## Static helpers that pull per-era tokens from `EraTheme` and apply them
## to common Control types. Keeps every view free of hand-rolled colour
## math. All helpers are no-ops when `EraTheme` is nil.

static func t() -> Node:
	return Engine.get_singleton("EraTheme") if Engine.has_singleton("EraTheme") else null


static func _theme():
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("EraTheme")


static func palette(key: String, default_col: Color = Color(0.22, 0.14, 0.06, 1.0)) -> Color:
	var th = _theme()
	if th == null:
		return default_col
	return th.palette_color(key, default_col)


static func map_tint(key: String, default_col: Color = Color(0.76, 0.68, 0.40, 1.0)) -> Color:
	var th = _theme()
	if th == null:
		return default_col
	return th.map_tint_color(key, default_col)


static func apply_title_label(l: Label) -> void:
	if l == null:
		return
	l.add_theme_color_override("font_color", palette("ink"))
	var th = _theme()
	var size: int = 22
	if th != null:
		size = int(th.typography().get("title_size", 22))
	l.add_theme_font_size_override("font_size", size)


static func apply_body_label(l: Label) -> void:
	if l == null:
		return
	l.add_theme_color_override("font_color", palette("ink"))
	var th = _theme()
	var size: int = 13
	if th != null:
		size = int(th.typography().get("body_size", 13))
	l.add_theme_font_size_override("font_size", size)


static func apply_muted_label(l: Label) -> void:
	if l == null:
		return
	l.add_theme_color_override("font_color", palette("ink_muted", Color(0.22, 0.14, 0.06, 0.65)))


static func apply_panel(p: PanelContainer) -> void:
	if p == null:
		return
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = palette("paper", Color(0.96, 0.92, 0.82, 1.0))
	sb.border_color = palette("paper_edge", Color(0.55, 0.42, 0.28, 0.70))
	sb.corner_radius_top_left = 18
	sb.corner_radius_top_right = 18
	sb.corner_radius_bottom_left = 18
	sb.corner_radius_bottom_right = 18
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.shadow_color = palette("shadow", Color(0, 0, 0, 0.35))
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 6)
	p.add_theme_stylebox_override("panel", sb)


static func apply_primary_button(b: Button) -> void:
	if b == null:
		return
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = palette("accent", Color(0.44, 0.36, 0.14, 1.0))
	sb.corner_radius_top_left = 20
	sb.corner_radius_top_right = 20
	sb.corner_radius_bottom_left = 20
	sb.corner_radius_bottom_right = 20
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_color_override("font_color", palette("paper", Color(0.96, 0.92, 0.82, 1.0)))


static func apply_secondary_button(b: Button) -> void:
	if b == null:
		return
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(palette("paper"), 0.24)
	sb.border_color = palette("paper_edge", Color(0.55, 0.42, 0.28, 0.70))
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.corner_radius_top_left = 20
	sb.corner_radius_top_right = 20
	sb.corner_radius_bottom_left = 20
	sb.corner_radius_bottom_right = 20
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_color_override("font_color", palette("ink"))


static func focus_stylebox(strong: bool = false) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.draw_center = false
	var col: Color = palette("accent", Color(0.10, 0.52, 1.0, 1.0))
	sb.border_color = col
	var w: int = 3 if strong else 2
	sb.border_width_top = w
	sb.border_width_bottom = w
	sb.border_width_left = w
	sb.border_width_right = w
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	return sb
