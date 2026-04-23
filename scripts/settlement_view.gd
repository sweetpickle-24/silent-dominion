extends Control
class_name SettlementView
## Dedicated settlement zoom level (§D4 revision).
##
## Opened when the player clicks a settlement dot on the main map. We
## intentionally do NOT replace the main MapView — this overlays on top
## of it so the player sees they dove into one city, can zoom back out
## with a single click, and the world map keeps its own selection state.
##
## Layout:
##   - Dimmer (clicking outside closes).
##   - A circular "street plan" with wedges per district. Wedge colour
##     matches the district kind; wedge opacity reflects the player's
##     coverage (fog → dim).
##   - A right-hand detail panel listing districts with fog phrases and
##     per-district contextual actions.
##
## This is the ONLY place district geometry is drawn — the main map no
## longer spins procedural wedges around every tier-1 city.

signal closed
## Same contract as `MapView.compose_here_requested`: the table layer
## takes it, opens ComposeView pre-filtered to the kingdom owning this
## settlement.
signal compose_here_requested(kingdom_id: String, province_id: String)

const SHEET_W: float = 840.0
const SHEET_H: float = 620.0

const COLOR_DIMMER: Color         = Color(0, 0, 0, 0.72)
const COLOR_PARCHMENT: Color      = Color(0.92, 0.86, 0.72, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.40, 0.28, 0.14, 0.75)
const COLOR_INK: Color            = Color(0.14, 0.09, 0.04, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.14, 0.09, 0.04, 0.65)

var _dimmer: ColorRect = null
var _sheet: PanelContainer = null
var _map_panel: Panel = null
var _detail_vbox: VBoxContainer = null

var _city_id: String = ""
var _province: Province = null
var _city: City = null
var _kingdom_id: String = ""

var _hover_district_index: int = -1
var _selected_district_index: int = -1


func configure(city_id: String) -> void:
	_city_id = city_id
	_resolve_from_geometry()


func _resolve_from_geometry() -> void:
	var dict: Dictionary = CrashGuard.safe_dict(MapGeometry.cities().get(_city_id, {}))
	var region_id: String = CrashGuard.safe_str(dict.get("region", ""))
	_province = WorldData.get_province(region_id) if not region_id.is_empty() else null
	_city = null
	if _province != null:
		_city = _province.city
		_kingdom_id = _province.owning_kingdom
	# Fallback: if the province has no City resource, synthesise a
	# minimal one so the view still has something to render. Better
	# to show the dot + "a rumour, no more" than to crash.
	if _city == null:
		_city = City.new()
		_city.display_name = CrashGuard.safe_str(dict.get("name", "unnamed"))
		_city.districts = [
			{"kind": int(City.DistrictKind.PALACE),    "fog": 100},
			{"kind": int(City.DistrictKind.TEMPLE),    "fog": 100},
			{"kind": int(City.DistrictKind.MARKET),    "fog": 100},
			{"kind": int(City.DistrictKind.DOCKS),     "fog": 100},
			{"kind": int(City.DistrictKind.WORKSHOPS), "fog": 100},
		]


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP
	_build_dimmer()
	_build_sheet()
	_render_detail()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, Prefs.anim_duration(0.20))


func close() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, Prefs.anim_duration(0.15))
	tw.tween_callback(func() -> void:
		closed.emit()
		queue_free())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# --- Chrome -----------------------------------------------------------------

func _build_dimmer() -> void:
	_dimmer = ColorRect.new()
	_dimmer.color = COLOR_DIMMER
	_dimmer.anchor_right = 1.0
	_dimmer.anchor_bottom = 1.0
	_dimmer.mouse_filter = MOUSE_FILTER_STOP
	_dimmer.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(_dimmer)


func _build_sheet() -> void:
	_sheet = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = COLOR_PARCHMENT
	sb.border_color = COLOR_PARCHMENT_EDGE
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.shadow_color = Color(0, 0, 0, 0.60)
	sb.shadow_size = 32
	sb.shadow_offset = Vector2(0, 14)
	_sheet.add_theme_stylebox_override("panel", sb)
	_sheet.anchor_left = 0.5
	_sheet.anchor_top = 0.5
	_sheet.anchor_right = 0.5
	_sheet.anchor_bottom = 0.5
	_sheet.offset_left   = -SHEET_W * 0.5
	_sheet.offset_right  =  SHEET_W * 0.5
	_sheet.offset_top    = -SHEET_H * 0.5
	_sheet.offset_bottom =  SHEET_H * 0.5
	_sheet.mouse_filter = MOUSE_FILTER_STOP
	add_child(_sheet)

	var root_margin: MarginContainer = MarginContainer.new()
	root_margin.add_theme_constant_override("margin_left", 18)
	root_margin.add_theme_constant_override("margin_right", 18)
	root_margin.add_theme_constant_override("margin_top", 14)
	root_margin.add_theme_constant_override("margin_bottom", 14)
	_sheet.add_child(root_margin)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	root_margin.add_child(col)

	# Header.
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	col.add_child(header)
	var title: Label = Label.new()
	title.text = CrashGuard.safe_str(_city.display_name, "settlement").capitalize()
	title.add_theme_color_override("font_color", COLOR_INK)
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var sub: Label = Label.new()
	var prov_name: String = _province.province_name if _province != null else ""
	sub.text = "The quarters of %s." % prov_name if not prov_name.is_empty() else "The quarters."
	sub.add_theme_color_override("font_color", COLOR_INK_MUTED)
	sub.add_theme_font_size_override("font_size", 11)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(sub)

	# Body row: street plan + detail.
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	_map_panel = Panel.new()
	var mb: StyleBoxFlat = StyleBoxFlat.new()
	mb.bg_color = Color(0.88, 0.82, 0.66, 1.0)
	mb.border_color = COLOR_PARCHMENT_EDGE
	mb.border_width_left = 1
	mb.border_width_right = 1
	mb.border_width_top = 1
	mb.border_width_bottom = 1
	mb.corner_radius_top_left = 3
	mb.corner_radius_top_right = 3
	mb.corner_radius_bottom_left = 3
	mb.corner_radius_bottom_right = 3
	_map_panel.add_theme_stylebox_override("panel", mb)
	_map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_panel.custom_minimum_size = Vector2(460, 420)
	_map_panel.mouse_filter = MOUSE_FILTER_STOP
	_map_panel.gui_input.connect(_on_map_input)
	_map_panel.draw.connect(_draw_street_plan)
	row.add_child(_map_panel)

	# Right detail panel.
	var detail: PanelContainer = PanelContainer.new()
	detail.custom_minimum_size.x = 300.0
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var db: StyleBoxFlat = StyleBoxFlat.new()
	db.bg_color = Color(0.96, 0.92, 0.82, 1.0)
	db.border_color = COLOR_PARCHMENT_EDGE
	db.border_width_left = 1
	db.border_width_right = 1
	db.border_width_top = 1
	db.border_width_bottom = 1
	db.corner_radius_top_left = 3
	db.corner_radius_top_right = 3
	db.corner_radius_bottom_left = 3
	db.corner_radius_bottom_right = 3
	detail.add_theme_stylebox_override("panel", db)
	row.add_child(detail)

	var dm: MarginContainer = MarginContainer.new()
	dm.add_theme_constant_override("margin_left", 14)
	dm.add_theme_constant_override("margin_right", 14)
	dm.add_theme_constant_override("margin_top", 12)
	dm.add_theme_constant_override("margin_bottom", 12)
	detail.add_child(dm)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dm.add_child(scroll)

	_detail_vbox = VBoxContainer.new()
	_detail_vbox.add_theme_constant_override("separation", 6)
	_detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_detail_vbox)

	# Footer.
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	col.add_child(footer)

	var compose_btn: Button = Button.new()
	compose_btn.text = "Compose action here…"
	compose_btn.custom_minimum_size.y = 28.0
	compose_btn.focus_mode = Control.FOCUS_NONE
	compose_btn.add_theme_color_override("font_color", COLOR_INK)
	compose_btn.add_theme_font_size_override("font_size", 12)
	compose_btn.pressed.connect(_on_compose_here_pressed)
	footer.add_child(compose_btn)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var close_btn: Button = Button.new()
	close_btn.text = "Back to the map"
	close_btn.custom_minimum_size.y = 28.0
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_color_override("font_color", COLOR_INK)
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.pressed.connect(func() -> void: close())
	footer.add_child(close_btn)


# --- Rendering --------------------------------------------------------------

func _district_color(kind: int) -> Color:
	match kind:
		int(City.DistrictKind.PALACE):    return Color(0.92, 0.72, 0.32)
		int(City.DistrictKind.TEMPLE):    return Color(0.72, 0.38, 0.62)
		int(City.DistrictKind.MARKET):    return Color(0.78, 0.52, 0.24)
		int(City.DistrictKind.DOCKS):     return Color(0.30, 0.48, 0.78)
		int(City.DistrictKind.WORKSHOPS): return Color(0.48, 0.58, 0.32)
	return Color(0.70, 0.65, 0.52)


func _draw_street_plan() -> void:
	if _map_panel == null or _city == null:
		return
	var font: Font = get_theme_default_font()
	var rect: Rect2 = Rect2(Vector2.ZERO, _map_panel.size)
	var center: Vector2 = rect.size * 0.5
	var radius: float = minf(rect.size.x, rect.size.y) * 0.40
	var n: int = _city.districts.size()
	if n <= 0:
		return
	# Sand backdrop ring so the plan reads against the panel.
	_map_panel.draw_circle(center, radius + 8.0, Color(0.82, 0.74, 0.56, 0.85))
	_map_panel.draw_circle(center, radius + 6.0, Color(0.92, 0.86, 0.70, 1.0))
	var steps: int = 28
	for i in range(n):
		var t0: float = float(i) / float(n) * TAU - TAU * 0.25
		var t1: float = float(i + 1) / float(n) * TAU - TAU * 0.25
		var district: Dictionary = CrashGuard.safe_dict(_city.districts[i])
		var kind: int = int(CrashGuard.safe_get(district, "kind", 0))
		var fog: int = int(CrashGuard.safe_get(district, "fog", 100))
		var wedge: PackedVector2Array = PackedVector2Array()
		wedge.append(center)
		for s in range(steps + 1):
			var t: float = lerpf(t0, t1, float(s) / float(steps))
			wedge.append(center + Vector2(cos(t), sin(t)) * radius)
		var base: Color = _district_color(kind)
		# Fog darkens and desaturates the wedge. 100 fog → near-black;
		# 0 fog → full colour.
		var fog_f: float = clampf(float(fog) / 100.0, 0.0, 1.0)
		var col: Color = base.lerp(Color(0.35, 0.32, 0.28), fog_f)
		col.a = 0.55 + 0.35 * (1.0 - fog_f)
		if i == _selected_district_index:
			col = col.lightened(0.15)
		elif i == _hover_district_index:
			col = col.lightened(0.08)
		_map_panel.draw_colored_polygon(wedge, col)
		# Wedge border.
		var border: PackedVector2Array = PackedVector2Array()
		border.append(center)
		border.append(center + Vector2(cos(t0), sin(t0)) * radius)
		for s in range(steps + 1):
			var t2: float = lerpf(t0, t1, float(s) / float(steps))
			border.append(center + Vector2(cos(t2), sin(t2)) * radius)
		border.append(center)
		_map_panel.draw_polyline(border, Color(0.10, 0.06, 0.02, 0.75), 1.2)
		# Label.
		var tm: float = (t0 + t1) * 0.5
		var label_pos: Vector2 = center + Vector2(cos(tm), sin(tm)) * (radius * 0.62)
		var txt: String = _city.district_kind_name(kind).capitalize()
		var tsize: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		_map_panel.draw_string(
			font,
			label_pos - tsize * 0.5 + Vector2(1, 1),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0, 0, 0, 0.55),
		)
		_map_panel.draw_string(
			font,
			label_pos - tsize * 0.5,
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.98, 0.94, 0.84, 1.0),
		)
	# Outer ring.
	var ring: PackedVector2Array = PackedVector2Array()
	var rsteps: int = 96
	for s in range(rsteps + 1):
		var t: float = float(s) / float(rsteps) * TAU
		ring.append(center + Vector2(cos(t), sin(t)) * radius)
	_map_panel.draw_polyline(ring, Color(0.08, 0.05, 0.02, 0.85), 1.5)
	# Forum dot in the centre.
	_map_panel.draw_circle(center, 6.0, Color(0.22, 0.14, 0.08, 1.0))
	_map_panel.draw_circle(center, 3.0, Color(0.98, 0.88, 0.58, 1.0))


func _on_map_input(event: InputEvent) -> void:
	if _map_panel == null or _city == null:
		return
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		var idx: int = _district_index_at(mm.position)
		if idx != _hover_district_index:
			_hover_district_index = idx
			_map_panel.queue_redraw()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var idx2: int = _district_index_at(mb.position)
			if idx2 >= 0:
				_selected_district_index = idx2
				_map_panel.queue_redraw()
				_render_detail()


func _district_index_at(p: Vector2) -> int:
	if _map_panel == null or _city == null:
		return -1
	var center: Vector2 = _map_panel.size * 0.5
	var radius: float = minf(_map_panel.size.x, _map_panel.size.y) * 0.40
	var d: Vector2 = p - center
	var dist: float = d.length()
	if dist > radius or dist < 3.0:
		return -1
	var n: int = _city.districts.size()
	if n <= 0:
		return -1
	var ang: float = atan2(d.y, d.x)
	# Rotate so wedge 0 starts at the top.
	ang = fposmod(ang + TAU * 0.25, TAU)
	return int(floorf(ang / TAU * float(n))) % n


func _render_detail() -> void:
	for c in _detail_vbox.get_children():
		c.queue_free()
	var k: Kingdom = WorldData.get_kingdom(_kingdom_id) if not _kingdom_id.is_empty() else null
	var owner_line: String = ""
	if k != null:
		owner_line = "Of the crown of %s" % k.kingdom_name
	var owner_l: Label = Label.new()
	owner_l.text = owner_line
	owner_l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	owner_l.add_theme_font_size_override("font_size", 12)
	_detail_vbox.add_child(owner_l)

	var cov_line: String = _coverage_phrase()
	if cov_line != "":
		var cl: Label = Label.new()
		cl.text = cov_line
		cl.add_theme_color_override("font_color", COLOR_INK_MUTED)
		cl.add_theme_font_size_override("font_size", 11)
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail_vbox.add_child(cl)

	_detail_vbox.add_child(_make_divider())
	_detail_vbox.add_child(_make_heading("DISTRICTS"))
	for i in range(_city.districts.size()):
		var d: Dictionary = CrashGuard.safe_dict(_city.districts[i])
		var kind: int = int(CrashGuard.safe_get(d, "kind", 0))
		var fog: int = int(CrashGuard.safe_get(d, "fog", 100))
		var swatch_row: HBoxContainer = HBoxContainer.new()
		swatch_row.add_theme_constant_override("separation", 6)
		var sw: Panel = Panel.new()
		sw.custom_minimum_size = Vector2(10, 10)
		var ssb: StyleBoxFlat = StyleBoxFlat.new()
		ssb.bg_color = _district_color(kind)
		ssb.border_color = ssb.bg_color.darkened(0.4)
		ssb.border_width_left = 1
		ssb.border_width_right = 1
		ssb.border_width_top = 1
		ssb.border_width_bottom = 1
		sw.add_theme_stylebox_override("panel", ssb)
		swatch_row.add_child(sw)
		var l: Label = Label.new()
		l.text = "%s — %s" % [
			_city.district_kind_name(kind).capitalize(),
			_fog_phrase(fog),
		]
		l.add_theme_color_override("font_color", COLOR_INK)
		l.add_theme_font_size_override("font_size", 12)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		swatch_row.add_child(l)
		_detail_vbox.add_child(swatch_row)


func _coverage_phrase() -> String:
	if Org == null or _kingdom_id.is_empty():
		return ""
	var cov: OrgMember = Org.coverage_for(_kingdom_id)
	if cov == null:
		return "No hand of yours in this city. The quarters are rumour until a coordinator walks them."
	return "A coordinator of yours walks here; the quarters come clear with time."


func _fog_phrase(fog: int) -> String:
	if fog >= 80: return "a rumour, no more"
	if fog >= 50: return "walked at a distance"
	if fog >= 25: return "known well enough to move through"
	return "quarters you could name a man in"


func _on_compose_here_pressed() -> void:
	var prov_id: String = _province.id if _province != null else ""
	compose_here_requested.emit(_kingdom_id, prov_id)


func _make_heading(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	l.add_theme_font_size_override("font_size", 10)
	return l


func _make_divider() -> HSeparator:
	var s: HSeparator = HSeparator.new()
	s.add_theme_color_override("color", COLOR_PARCHMENT_EDGE)
	return s
