extends Control
## Full-screen overlay for the MapScroll object on the table.
##
## The map is rendered by a single-quad shader (see MapRenderer +
## assets/map/map_render.gdshader) sampling baked bitmaps produced by
## scripts/map_bake.gd. No polygons are drawn at runtime.
##
## Layer layout:
##   _dimmer             full-screen backdrop that swallows clicks outside
##   _sheet              parchment framing around the map
##     ├ header          title + flavour
##     ├ row
##     │   ├ _canvas     clipping viewport (handles input)
##     │   │   └ _map_root    child Control that owns the pan/zoom xform
##     │   │         └ _renderer (MapRenderer)
##     │   └ _detail_panel   right-side detail pane
##     └ footer          legend + close button
##   _cartouche          hover tooltip, top-level

signal closed

# --- Visual tokens ----------------------------------------------------------

const COLOR_DIMMER: Color         = Color(0, 0, 0, 0.72)
const COLOR_PARCHMENT: Color      = Color(0.92, 0.86, 0.72, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.40, 0.28, 0.14, 0.75)
const COLOR_INK: Color            = Color(0.14, 0.09, 0.04, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.14, 0.09, 0.04, 0.65)
const COLOR_SEA_WATER: Color      = Color(0.26, 0.40, 0.52, 1.0)
const COLOR_UNCLAIMED: Color      = Color(0.78, 0.72, 0.60, 1.0)

const KINGDOM_COLORS: Dictionary = {
	"athens":          Color(0.60, 0.48, 0.75),
	"sparta":          Color(0.75, 0.28, 0.30),
	"corinth":         Color(0.25, 0.62, 0.60),
	"macedon":         Color(0.82, 0.68, 0.30),
	"persia":          Color(0.28, 0.50, 0.78),
	"egypt":           Color(0.92, 0.86, 0.58),
	"carthage":        Color(0.60, 0.20, 0.22),
	"rome":            Color(0.88, 0.52, 0.30),
	"etruscan_league": Color(0.40, 0.58, 0.32),
	"thebes":          Color(0.55, 0.40, 0.22),
	"syracuse":        Color(0.52, 0.72, 0.62),
	"massalia":        Color(0.42, 0.60, 0.78),
	"odrysia":         Color(0.72, 0.55, 0.32),
	"molossia":        Color(0.60, 0.50, 0.28),
	"colchis":         Color(0.48, 0.58, 0.70),
	"nabatea":         Color(0.74, 0.58, 0.38),
	"kush":            Color(0.55, 0.35, 0.28),
	"cyrene":          Color(0.68, 0.78, 0.52),
	"tartessos":       Color(0.68, 0.42, 0.36),
}

# Major legend kingdoms (tier-1 powers only). Keeps the footer
# readable now that we track 19 kingdoms.
const LEGEND_KINGDOMS: Array = [
	"athens", "sparta", "corinth", "thebes",
	"macedon", "persia", "egypt", "carthage",
	"rome", "etruscan_league", "syracuse",
]

# --- Layout -----------------------------------------------------------------

const SHEET_W: float = 1180.0
const SHEET_H: float = 760.0
const PANEL_W: float = 300.0

# User zoom multiplier bounds. 1.0 = "fit to canvas", up to 10.0 = 10x
# zoomed in. The baked bitmap is 2048×1024 so 10x gives a ~2 mega-
# pixel on-screen crop — sharp enough to matter.
const ZOOM_USER_MIN: float = 1.0
const ZOOM_USER_MAX: float = 10.0
const ZOOM_STEP:     float = 1.18

# --- Node refs --------------------------------------------------------------

var _dimmer: ColorRect
var _sheet: PanelContainer
var _canvas: Panel
var _map_root: Control
var _renderer: MapRenderer
var _labels_layer: Control
var _detail_panel: PanelContainer
var _detail_vbox: VBoxContainer
var _legend: HBoxContainer

var _cartouche: PanelContainer
var _cartouche_vbox: VBoxContainer

# --- State ------------------------------------------------------------------

var _selected_cell_id: int = 0
var _hover_cell_id: int = 0
var _selected_province_id: String = ""

var _fit_zoom: float = 1.0
var _zoom_user: float = 1.0
var _map_offset: Vector2 = Vector2.ZERO   # canvas-space offset of bitmap origin

var _panning: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _press_dragged: bool = false
const _CLICK_SLOP: float = 4.0


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	_build_dimmer()
	_build_sheet()
	_build_cartouche()
	_render_placeholder_detail()
	_render_legend()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.20)

	if MapData.is_ready():
		_on_map_ready()
	else:
		MapData.map_ready.connect(_on_map_ready)

	KingdomEconomy.tick.connect(_on_economy_tick)
	Relations.relation_changed.connect(_on_relation_changed)
	Unrest.province_unrest_changed.connect(_on_unrest_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				close()
				get_viewport().set_input_as_handled()
			KEY_R:
				_reset_view()
				get_viewport().set_input_as_handled()


func close() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func() -> void:
		closed.emit()
		queue_free())


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
	title.text = "The Mediterranean as known"
	title.add_theme_color_override("font_color", COLOR_INK)
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var sub: Label = Label.new()
	sub.text = "Drawn from the reports of a hundred travellers. Do not trust the distances."
	sub.add_theme_color_override("font_color", COLOR_INK_MUTED)
	sub.add_theme_font_size_override("font_size", 11)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(sub)

	# Body row: canvas + detail.
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	_canvas = Panel.new()
	var csb: StyleBoxFlat = StyleBoxFlat.new()
	csb.bg_color = COLOR_SEA_WATER
	csb.border_color = COLOR_PARCHMENT_EDGE
	csb.border_width_left = 1
	csb.border_width_right = 1
	csb.border_width_top = 1
	csb.border_width_bottom = 1
	csb.corner_radius_top_left = 3
	csb.corner_radius_top_right = 3
	csb.corner_radius_bottom_left = 3
	csb.corner_radius_bottom_right = 3
	_canvas.add_theme_stylebox_override("panel", csb)
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.mouse_filter = MOUSE_FILTER_STOP
	_canvas.clip_contents = true
	_canvas.gui_input.connect(_on_canvas_gui_input)
	_canvas.resized.connect(_on_canvas_resized)
	_canvas.mouse_exited.connect(_on_canvas_mouse_exited)
	row.add_child(_canvas)

	_map_root = Control.new()
	_map_root.mouse_filter = MOUSE_FILTER_IGNORE
	_canvas.add_child(_map_root)

	# Labels overlay sits above the renderer inside the transformed
	# root so they pan/zoom with the map, but we keep a font-size
	# compensation that scales back down so the labels stay legible
	# at every zoom.
	_labels_layer = Control.new()
	_labels_layer.mouse_filter = MOUSE_FILTER_IGNORE
	_labels_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(_labels_layer)
	_labels_layer.draw.connect(_draw_labels)

	# Detail pane.
	_detail_panel = PanelContainer.new()
	_detail_panel.custom_minimum_size.x = PANEL_W
	_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var dsb: StyleBoxFlat = StyleBoxFlat.new()
	dsb.bg_color = Color(0.96, 0.92, 0.82, 1.0)
	dsb.border_color = COLOR_PARCHMENT_EDGE
	dsb.border_width_left = 1
	dsb.border_width_right = 1
	dsb.border_width_top = 1
	dsb.border_width_bottom = 1
	dsb.corner_radius_top_left = 3
	dsb.corner_radius_top_right = 3
	dsb.corner_radius_bottom_left = 3
	dsb.corner_radius_bottom_right = 3
	_detail_panel.add_theme_stylebox_override("panel", dsb)
	row.add_child(_detail_panel)

	var detail_margin: MarginContainer = MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 14)
	detail_margin.add_theme_constant_override("margin_right", 14)
	detail_margin.add_theme_constant_override("margin_top", 12)
	detail_margin.add_theme_constant_override("margin_bottom", 12)
	_detail_panel.add_child(detail_margin)
	_detail_vbox = VBoxContainer.new()
	_detail_vbox.add_theme_constant_override("separation", 6)
	detail_margin.add_child(_detail_vbox)

	# Footer.
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	col.add_child(footer)
	_legend = HBoxContainer.new()
	_legend.add_theme_constant_override("separation", 10)
	_legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_legend)
	var close_btn: Button = Button.new()
	close_btn.text = "Fold the map"
	close_btn.custom_minimum_size.y = 28.0
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_color_override("font_color", COLOR_INK)
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.pressed.connect(func() -> void: close())
	footer.add_child(close_btn)


# --- Map ready -------------------------------------------------------------

func _on_map_ready() -> void:
	if _renderer != null:
		return
	_renderer = MapRenderer.new()
	_map_root.add_child(_renderer)
	_fit_view()
	_apply_transform()


# --- Detail -----------------------------------------------------------------

func _render_placeholder_detail() -> void:
	_clear_detail()
	var l: Label = Label.new()
	l.text = "Select a land."
	l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	l.add_theme_font_size_override("font_size", 12)
	_detail_vbox.add_child(l)
	var note: Label = Label.new()
	note.text = "Colour denotes the crown that holds each land; texture denotes its character. Wheel or pinch to zoom, drag to shift the sheet. Press R to recentre. Click any cell to read it."
	note.add_theme_color_override("font_color", COLOR_INK_MUTED)
	note.add_theme_font_size_override("font_size", 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_vbox.add_child(note)


func _render_detail(p: Province) -> void:
	_clear_detail()
	var title: Label = Label.new()
	title.text = p.province_name
	title.add_theme_color_override("font_color", COLOR_INK)
	title.add_theme_font_size_override("font_size", 18)
	_detail_vbox.add_child(title)

	var k: Kingdom = WorldData.get_kingdom(p.owning_kingdom)
	var owner_line: String = "Unclaimed"
	if k != null:
		owner_line = "Of the crown of %s" % k.kingdom_name
	elif not p.owning_kingdom.is_empty():
		owner_line = p.owning_kingdom
	var owner_l: Label = Label.new()
	owner_l.text = owner_line
	owner_l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	owner_l.add_theme_font_size_override("font_size", 12)
	_detail_vbox.add_child(owner_l)

	_detail_vbox.add_child(_make_divider())
	_detail_vbox.add_child(_make_heading("LAND AND WEATHER"))
	_detail_vbox.add_child(_make_line("%s — %s" % [p.terrain_name(), p.climate_name()]))
	_detail_vbox.add_child(_make_heading("SOULS"))
	_detail_vbox.add_child(_make_line(_population_phrase(p.population)))
	if p.population > 0:
		var trend: String = Population.phrase_for(p.id)
		if trend != "":
			_detail_vbox.add_child(_make_line(trend))
		_detail_vbox.add_child(_make_heading("MOOD"))
		_detail_vbox.add_child(_make_line(p.unrest_phrase()))
	_detail_vbox.add_child(_make_heading("WHAT IT PRODUCES"))
	var prod: Array[String] = _production_phrases(p)
	if prod.is_empty():
		_detail_vbox.add_child(_make_line("Little of consequence."))
	else:
		for phrase in prod:
			_detail_vbox.add_child(_make_line("•  %s" % phrase))

	var infra: String = Infrastructure.phrase_for(p.id)
	if infra != "":
		_detail_vbox.add_child(_make_heading("ON THE GROUND"))
		_detail_vbox.add_child(_make_line(infra))

	if k != null:
		_detail_vbox.add_child(_make_divider())
		_detail_vbox.add_child(_make_heading("THE CROWN IT FEEDS"))
		_detail_vbox.add_child(_make_line("%s — %s" % [k.kingdom_name, k.treasury_condition_name()]))
		_detail_vbox.add_child(_make_line(k.tax_level_phrase() + "."))


func _clear_detail() -> void:
	for c in _detail_vbox.get_children():
		c.queue_free()


# --- Legend -----------------------------------------------------------------

func _render_legend() -> void:
	for c in _legend.get_children():
		c.queue_free()
	for id in LEGEND_KINGDOMS:
		var k: Kingdom = WorldData.get_kingdom(String(id))
		if k == null:
			continue
		_legend.add_child(_build_legend_swatch(k))


func _build_legend_swatch(k: Kingdom) -> Control:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var sw: Panel = Panel.new()
	sw.custom_minimum_size = Vector2(10, 10)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = KINGDOM_COLORS.get(k.id, COLOR_UNCLAIMED)
	sb.border_color = sb.bg_color.darkened(0.45)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	sw.add_theme_stylebox_override("panel", sb)
	h.add_child(sw)
	var l: Label = Label.new()
	l.text = k.kingdom_name
	l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	l.add_theme_font_size_override("font_size", 10)
	h.add_child(l)
	return h


# --- Cartouche (hover tooltip) ---------------------------------------------

func _build_cartouche() -> void:
	_cartouche = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.94, 0.84, 0.97)
	sb.border_color = COLOR_PARCHMENT_EDGE
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_cartouche.add_theme_stylebox_override("panel", sb)
	_cartouche.mouse_filter = MOUSE_FILTER_IGNORE
	_cartouche.visible = false
	_cartouche.top_level = true
	_cartouche.z_index = 10
	add_child(_cartouche)
	_cartouche_vbox = VBoxContainer.new()
	_cartouche_vbox.add_theme_constant_override("separation", 2)
	_cartouche_vbox.mouse_filter = MOUSE_FILTER_IGNORE
	_cartouche.add_child(_cartouche_vbox)


func _show_cartouche_for(p: Province) -> void:
	if _cartouche == null:
		return
	for c in _cartouche_vbox.get_children():
		c.queue_free()
	var name_l: Label = Label.new()
	name_l.text = p.province_name
	name_l.add_theme_color_override("font_color", COLOR_INK)
	name_l.add_theme_font_size_override("font_size", 13)
	_cartouche_vbox.add_child(name_l)
	var owner_l: Label = Label.new()
	owner_l.text = _cartouche_owner_line(p)
	owner_l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	owner_l.add_theme_font_size_override("font_size", 11)
	_cartouche_vbox.add_child(owner_l)
	var terrain_l: Label = Label.new()
	terrain_l.text = "%s — %s" % [p.terrain_name().capitalize(), p.climate_name().capitalize()]
	terrain_l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	terrain_l.add_theme_font_size_override("font_size", 11)
	_cartouche_vbox.add_child(terrain_l)
	_cartouche.visible = true
	_cartouche.reset_size()


func _position_cartouche_at(canvas_pt: Vector2) -> void:
	if _cartouche == null or not _cartouche.visible:
		return
	var global_anchor: Vector2 = _canvas.global_position + canvas_pt
	var card_size: Vector2 = _cartouche.size
	var vr: Rect2 = get_viewport_rect()
	var x: float = global_anchor.x - card_size.x * 0.5
	var y: float = global_anchor.y - card_size.y - 14.0
	if y < vr.position.y + 8.0:
		y = global_anchor.y + 18.0
	x = clampf(x, vr.position.x + 6.0, vr.position.x + vr.size.x - card_size.x - 6.0)
	_cartouche.position = Vector2(x, y)


func _cartouche_owner_line(p: Province) -> String:
	if p.owning_kingdom.is_empty():
		return "No crown. Only water."
	var k: Kingdom = WorldData.get_kingdom(p.owning_kingdom)
	if k == null:
		return p.owning_kingdom
	return "Of %s." % k.kingdom_name


# --- Pan / zoom / transform -------------------------------------------------

## Fit the bitmap inside the canvas with aspect-correct letterboxing,
## reset user zoom.
func _fit_view() -> void:
	if _renderer == null:
		return
	var bs: Vector2 = _renderer.bitmap_size()
	var c: Vector2 = _canvas.size
	if bs.x <= 0.0 or bs.y <= 0.0 or c.x <= 0.0 or c.y <= 0.0:
		return
	_fit_zoom = minf(c.x / bs.x, c.y / bs.y)
	_zoom_user = 1.0
	var effective: float = _fit_zoom * _zoom_user
	_map_offset = Vector2(
		(c.x - bs.x * effective) * 0.5,
		(c.y - bs.y * effective) * 0.5,
	)


## Apply the current (_map_offset, _fit_zoom, _zoom_user) to the map
## root's transform, and notify the renderer of the effective view
## zoom so its shader can switch LODs.
func _apply_transform() -> void:
	if _map_root == null or _renderer == null:
		return
	var effective: float = _fit_zoom * _zoom_user
	_map_root.position = _map_offset
	_map_root.scale = Vector2(effective, effective)
	_renderer.set_view_zoom(_zoom_user)
	_labels_layer.queue_redraw()


## User-space zoom, anchored at a canvas-space point.
func _zoom_at(canvas_pt: Vector2, factor: float) -> void:
	var old_user: float = _zoom_user
	var new_user: float = clampf(old_user * factor, ZOOM_USER_MIN, ZOOM_USER_MAX)
	if is_equal_approx(new_user, old_user):
		return
	var old_eff: float = _fit_zoom * old_user
	var new_eff: float = _fit_zoom * new_user
	var before: Vector2 = (canvas_pt - _map_offset) / old_eff
	_zoom_user = new_user
	_map_offset = canvas_pt - before * new_eff
	_clamp_offset()
	_apply_transform()


## Stop the user from dragging the map completely out of view: require
## at least a ~20 % overlap between bitmap and canvas.
func _clamp_offset() -> void:
	if _renderer == null:
		return
	var eff: float = _fit_zoom * _zoom_user
	var bs: Vector2 = _renderer.bitmap_size() * eff
	var c: Vector2 = _canvas.size
	var margin: Vector2 = bs * 0.20
	_map_offset.x = clampf(_map_offset.x, c.x - bs.x - margin.x, margin.x)
	_map_offset.y = clampf(_map_offset.y, c.y - bs.y - margin.y, margin.y)


func _reset_view() -> void:
	_fit_view()
	_apply_transform()


# --- Input handling ---------------------------------------------------------

func _on_canvas_gui_input(event: InputEvent) -> void:
	if _renderer == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, ZOOM_STEP)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / ZOOM_STEP)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_panning = true
				_press_pos = mb.position
				_press_dragged = false
				accept_event()
			else:
				var was_panning: bool = _panning
				_panning = false
				if was_panning and not _press_dragged:
					_handle_click(mb.position)
				accept_event()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _panning:
			if not _press_dragged and mm.position.distance_to(_press_pos) > _CLICK_SLOP:
				_press_dragged = true
			if _press_dragged:
				_map_offset += mm.relative
				_clamp_offset()
				_apply_transform()
		else:
			_handle_hover(mm.position)
		accept_event()
	elif event is InputEventMagnifyGesture:
		var mg: InputEventMagnifyGesture = event
		_zoom_at(mg.position, mg.factor)
		accept_event()
	elif event is InputEventPanGesture:
		var pg: InputEventPanGesture = event
		_map_offset -= pg.delta * 20.0
		_clamp_offset()
		_apply_transform()
		accept_event()


func _canvas_to_uv(canvas_pt: Vector2) -> Vector2:
	if _renderer == null:
		return Vector2(-1.0, -1.0)
	var eff: float = _fit_zoom * _zoom_user
	if eff <= 0.0:
		return Vector2(-1.0, -1.0)
	var bs: Vector2 = _renderer.bitmap_size()
	var px: Vector2 = (canvas_pt - _map_offset) / eff
	return Vector2(px.x / bs.x, px.y / bs.y)


func _handle_hover(canvas_pt: Vector2) -> void:
	var uv: Vector2 = _canvas_to_uv(canvas_pt)
	var new_hover: int = MapData.cell_id_at_uv(uv)
	if new_hover == _hover_cell_id:
		if new_hover > 0:
			_position_cartouche_at(canvas_pt)
		return
	_hover_cell_id = new_hover
	_renderer.set_hover_cell(new_hover)
	if new_hover == 0:
		_cartouche.visible = false
		return
	var cell: MapCell = MapData.get_cell(new_hover)
	if cell == null:
		_cartouche.visible = false
		return
	var p: Province = WorldData.get_province(cell.region_id)
	if p == null:
		_cartouche.visible = false
		return
	_show_cartouche_for(p)
	_position_cartouche_at(canvas_pt)


func _handle_click(canvas_pt: Vector2) -> void:
	var uv: Vector2 = _canvas_to_uv(canvas_pt)
	var cid: int = MapData.cell_id_at_uv(uv)
	if cid == 0:
		return
	var cell: MapCell = MapData.get_cell(cid)
	if cell == null:
		return
	var p: Province = WorldData.get_province(cell.region_id)
	if p == null:
		return
	_selected_cell_id = cid
	_selected_province_id = p.id
	_renderer.set_selected_cell(cid)
	_render_detail(p)


# --- Signal hooks -----------------------------------------------------------

func _on_canvas_mouse_exited() -> void:
	if _hover_cell_id != 0:
		_hover_cell_id = 0
		if _renderer != null:
			_renderer.set_hover_cell(0)
	if _cartouche != null:
		_cartouche.visible = false


func _on_canvas_resized() -> void:
	_fit_view()
	_apply_transform()


func _on_economy_tick(_snap: Array) -> void:
	if _renderer != null:
		_renderer.refresh_palette()
	if not _selected_province_id.is_empty():
		var p: Province = WorldData.get_province(_selected_province_id)
		if p != null:
			_render_detail(p)


func _on_relation_changed(_a: String, _b: String, _s: int) -> void:
	if _selected_province_id.is_empty():
		return
	var p: Province = WorldData.get_province(_selected_province_id)
	if p != null:
		_render_detail(p)


func _on_unrest_changed(province_id: String) -> void:
	if province_id != _selected_province_id:
		return
	var p: Province = WorldData.get_province(province_id)
	if p != null:
		_render_detail(p)


# --- Labels + cities --------------------------------------------------------
#
# Zoom tiers follow the §7.3 "Map and Zoom Levels" doc:
#
#   World    (zoom ~1.0)    kingdom borders, only tier-1 cities + big regions
#   Regional (zoom ~1.8)    region borders, tier-2 cities
#   Province (zoom ~4.0)    every region labelled, tier-3 cities
#   City     (zoom ~7.0+)   city districts drawn around tier-1/2 cities
#
# Everything is drawn in canvas-space on top of the pan/zoom transform,
# so fonts stay readable at every zoom.

const LOD_REGIONAL: float = 1.8
const LOD_PROVINCE: float = 3.5
const LOD_CITY:     float = 6.5

func _draw_labels(_c: Control = null) -> void:
	if _renderer == null:
		return
	_draw_region_labels()
	_draw_cities()
	if _zoom_user >= LOD_CITY:
		_draw_city_districts()


func _draw_region_labels() -> void:
	var font: Font = get_theme_default_font()
	for rid in WorldData.provinces.keys():
		var prov: Province = WorldData.provinces[rid]
		var cell_ids: Array = MapData.cells_in_region(rid)
		if cell_ids.is_empty():
			continue
		var biggest: MapCell = null
		for cid in cell_ids:
			var c: MapCell = MapData.get_cell(int(cid))
			if c == null:
				continue
			if biggest == null or c.pixel_count > biggest.pixel_count:
				biggest = c
		if biggest == null:
			continue
		var bs: Vector2 = _renderer.bitmap_size()
		var eff: float = _fit_zoom * _zoom_user
		var px: Vector2 = Vector2(
			biggest.center_uv.x * bs.x * eff + _map_offset.x,
			biggest.center_uv.y * bs.y * eff + _map_offset.y,
		)
		if px.x < 0 or px.y < 0 or px.x > _canvas.size.x or px.y > _canvas.size.y:
			continue

		# Tier the label by how big the region is.
		var tier: int = 1
		if prov.population < 200:
			tier = 2
		if prov.population < 50:
			tier = 3

		var alpha: float = _region_label_alpha(tier)
		if alpha <= 0.02:
			continue
		var size: int = _region_label_size(tier)
		var txt: String = prov.province_name
		var tsize: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		var pos: Vector2 = Vector2(px.x - tsize.x * 0.5, px.y + tsize.y * 0.4)
		var shadow: Color = Color(0, 0, 0, 0.55 * alpha)
		_labels_layer.draw_string(font, pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, shadow)
		_labels_layer.draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.98, 0.94, 0.84, alpha))


func _region_label_alpha(tier: int) -> float:
	match tier:
		1: return 1.0
		2: return clampf((_zoom_user - 1.4) / 0.8, 0.0, 1.0)
		3: return clampf((_zoom_user - 3.0) / 1.0, 0.0, 1.0)
	return 1.0


func _region_label_size(tier: int) -> int:
	match tier:
		1: return 14
		2: return 12
		3: return 11
	return 12


## City markers. Drawn as small inked circles with shadowed labels.
## Each city has a tier; its visibility fades in as the player zooms
## past that tier's threshold. Capitals (tier ≤ 2) are always on.
func _draw_cities() -> void:
	var font: Font = get_theme_default_font()
	var bs: Vector2 = _renderer.bitmap_size()
	var eff: float = _fit_zoom * _zoom_user
	for cid in MapGeometry.cities().keys():
		var city: Dictionary = MapGeometry.cities()[cid]
		var tier: int = int(city.get("tier", 3))
		var alpha: float = _city_alpha(tier)
		if alpha <= 0.02:
			continue
		var n: Vector2 = MapGeometry.ll_to_norm(float(city.get("lon", 0.0)), float(city.get("lat", 0.0)))
		var px: Vector2 = Vector2(
			n.x * bs.x * eff + _map_offset.x,
			n.y * bs.y * eff + _map_offset.y,
		)
		if px.x < 0 or px.y < 0 or px.x > _canvas.size.x or px.y > _canvas.size.y:
			continue

		var dot_r: float = _city_dot_radius(tier)
		var k_col: Color = KINGDOM_COLORS.get(String(city.get("kingdom", "")), Color(0.92, 0.88, 0.74))
		var ring_col: Color = Color(0, 0, 0, 0.80 * alpha)
		_labels_layer.draw_circle(px, dot_r + 1.2, ring_col)
		_labels_layer.draw_circle(px, dot_r, Color(k_col.r, k_col.g, k_col.b, alpha))
		_labels_layer.draw_circle(px, dot_r * 0.38, Color(0.12, 0.08, 0.04, alpha))

		var txt: String = String(city.get("name", ""))
		if txt.is_empty():
			continue
		var size: int = _city_label_size(tier)
		var tsize: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		var pos: Vector2 = Vector2(px.x - tsize.x * 0.5, px.y - dot_r - 4.0)
		var shadow: Color = Color(0, 0, 0, 0.75 * alpha)
		_labels_layer.draw_string(font, pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, shadow)
		_labels_layer.draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1.0, 0.96, 0.86, alpha))


func _city_alpha(tier: int) -> float:
	match tier:
		1: return 1.0
		2: return clampf((_zoom_user - 1.2) / 0.6, 0.0, 1.0)
		3: return clampf((_zoom_user - LOD_PROVINCE) / 0.8, 0.0, 1.0)
		4: return clampf((_zoom_user - LOD_CITY)    / 0.8, 0.0, 1.0)
	return 1.0


func _city_dot_radius(tier: int) -> float:
	match tier:
		1: return 4.5
		2: return 3.5
		3: return 2.5
		4: return 2.0
	return 2.5


func _city_label_size(tier: int) -> int:
	match tier:
		1: return 13
		2: return 12
		3: return 11
		4: return 10
	return 11


## City districts are the innermost zoom (§8.5). We ring a few
## procedural district polygons around each tier-1/2 city and label
## them. Districts aren't clickable yet — they will feed into the host
## system once §10 lands — but they make the city-zoom feel like the
## docs describe.
const CITY_DISTRICTS: Array = [
	"Administrative", "Financial", "Merchant",
	"Religious", "Scholarly", "Port",
]

func _draw_city_districts() -> void:
	var font: Font = get_theme_default_font()
	var bs: Vector2 = _renderer.bitmap_size()
	var eff: float = _fit_zoom * _zoom_user
	var alpha: float = clampf((_zoom_user - LOD_CITY) / 1.5, 0.0, 1.0)
	if alpha <= 0.02:
		return
	var ring_r: float = 40.0 + eff * 0.6
	for cid in MapGeometry.cities().keys():
		var city: Dictionary = MapGeometry.cities()[cid]
		if int(city.get("tier", 3)) > 2:
			continue
		var n: Vector2 = MapGeometry.ll_to_norm(float(city.get("lon", 0.0)), float(city.get("lat", 0.0)))
		var center: Vector2 = Vector2(
			n.x * bs.x * eff + _map_offset.x,
			n.y * bs.y * eff + _map_offset.y,
		)
		if center.x < -ring_r or center.y < -ring_r:
			continue
		if center.x > _canvas.size.x + ring_r or center.y > _canvas.size.y + ring_r:
			continue

		var n_dist: int = CITY_DISTRICTS.size()
		for i in range(n_dist):
			var t0: float = float(i) / float(n_dist) * TAU
			var t1: float = float(i + 1) / float(n_dist) * TAU
			var wedge: PackedVector2Array = PackedVector2Array()
			wedge.append(center)
			var steps: int = 12
			for s in range(steps + 1):
				var t: float = lerpf(t0, t1, float(s) / float(steps))
				wedge.append(center + Vector2(cos(t), sin(t)) * ring_r)
			var col: Color = _district_color(i)
			col.a *= 0.22 * alpha
			_labels_layer.draw_colored_polygon(wedge, col)
			# Thin border.
			var border: PackedVector2Array = PackedVector2Array()
			border.append(center + Vector2(cos(t0), sin(t0)) * ring_r)
			border.append(center)
			border.append(center + Vector2(cos(t1), sin(t1)) * ring_r)
			_labels_layer.draw_polyline(border, Color(0.08, 0.05, 0.02, 0.55 * alpha), 1.0)
			# Label.
			var tm: float = (t0 + t1) * 0.5
			var label_pos: Vector2 = center + Vector2(cos(tm), sin(tm)) * (ring_r * 0.60)
			var txt: String = CITY_DISTRICTS[i]
			var tsize: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
			_labels_layer.draw_string(
				font,
				label_pos - tsize * 0.5,
				txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Color(0.98, 0.94, 0.84, alpha),
			)
		# Outer ring.
		var ring: PackedVector2Array = PackedVector2Array()
		var steps2: int = 64
		for s in range(steps2 + 1):
			var t: float = float(s) / float(steps2) * TAU
			ring.append(center + Vector2(cos(t), sin(t)) * ring_r)
		_labels_layer.draw_polyline(ring, Color(0.08, 0.05, 0.02, 0.75 * alpha), 1.2)


func _district_color(i: int) -> Color:
	match i:
		0: return Color(0.92, 0.72, 0.32, 1.0)   # admin
		1: return Color(0.38, 0.56, 0.88, 1.0)   # financial
		2: return Color(0.78, 0.52, 0.24, 1.0)   # merchant
		3: return Color(0.72, 0.38, 0.62, 1.0)   # religious
		4: return Color(0.32, 0.68, 0.58, 1.0)   # scholarly
		5: return Color(0.30, 0.48, 0.78, 1.0)   # port
	return Color(0.70, 0.65, 0.52, 1.0)


# --- Helpers ----------------------------------------------------------------

func _population_phrase(pop: int) -> String:
	if pop <= 0:    return "Empty waves."
	if pop < 50:    return "A scattering of villages."
	if pop < 200:   return "A handful of towns and a modest hinterland."
	if pop < 500:   return "A substantial populace."
	if pop < 1200:  return "A populous land."
	return "One of the great concentrations of the world's souls."


func _production_phrases(p: Province) -> Array[String]:
	var out: Array[String] = []
	if p.grain_production > 0.0:
		out.append("grain — %s" % _yield_band(p.grain_production))
	if p.silver_production > 0.0:
		out.append("silver — %s" % _yield_band(p.silver_production))
	if p.iron_production > 0.0:
		out.append("iron — %s" % _yield_band(p.iron_production))
	if p.timber_production > 0.0:
		out.append("timber — %s" % _yield_band(p.timber_production))
	return out


func _yield_band(v: float) -> String:
	if v < 3.0:   return "a trickle"
	if v < 8.0:   return "a modest yield"
	if v < 18.0:  return "a respectable harvest"
	return "one of the region's great sources"


func _make_heading(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	l.add_theme_font_size_override("font_size", 10)
	return l


func _make_line(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_INK)
	l.add_theme_font_size_override("font_size", 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _make_divider() -> HSeparator:
	var s: HSeparator = HSeparator.new()
	s.add_theme_color_override("color", COLOR_PARCHMENT_EDGE)
	return s
