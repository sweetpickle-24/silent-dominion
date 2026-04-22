extends Control
## Full-screen overlay for the MapScroll object on the table.
##
## The map is drawn as real polygons: each province is a hand-authored
## ring in normalised [0,1] coordinates, rendered via a dedicated
## `MapCanvas` child that delegates `_draw()` back to this view. The
## polygons sit on top of a few broader "landmass" silhouettes so that
## gaps between adjacent provinces read as land, not sea. The whole
## drawing layer is pan- and zoom-transformed from the outer clipped
## canvas, which handles all input (wheel for zoom, left-drag on empty
## area to pan, left-click on a province to select it).
##
## Visual contract (cf. docs/07-interface/map-and-zoom.md,
## docs/08-map-and-provinces/provinces.md):
##   - era-appropriate papyrus aesthetic — not a modern satellite view.
##   - provinces coloured by owning kingdom; seas styled distinctly.
##   - province border reddens as the owner's treasury degrades.
##   - selecting a province opens a detail pane on the right.

signal closed

# --- Visual tokens -----------------------------------------------------------

const COLOR_DIMMER: Color         = Color(0, 0, 0, 0.72)
const COLOR_PARCHMENT: Color      = Color(0.92, 0.86, 0.72, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.40, 0.28, 0.14, 0.75)
const COLOR_INK: Color            = Color(0.14, 0.09, 0.04, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.14, 0.09, 0.04, 0.65)
const COLOR_SEA_BG: Color         = Color(0.63, 0.73, 0.77, 0.55)
const COLOR_SEA_BORDER: Color     = Color(0.32, 0.45, 0.55, 0.8)
const COLOR_UNCLAIMED: Color      = Color(0.78, 0.72, 0.60, 1.0)

const KINGDOM_COLORS: Dictionary = {
	"athens":          Color(0.44, 0.36, 0.70, 1.0),
	"sparta":          Color(0.55, 0.22, 0.22, 1.0),
	"corinth":         Color(0.16, 0.54, 0.55, 1.0),
	"macedon":         Color(0.70, 0.55, 0.30, 1.0),
	"persia":          Color(0.20, 0.32, 0.62, 1.0),
	"egypt":           Color(0.80, 0.62, 0.35, 1.0),
	"carthage":        Color(0.48, 0.18, 0.18, 1.0),
	"rome":            Color(0.70, 0.36, 0.18, 1.0),
	"etruscan_league": Color(0.44, 0.48, 0.24, 1.0),
}

# Preloaded basemap texture. The map image is an aged papyrus view
# of the Mediterranean world circa 500 BCE with real coastlines and
# no text. Province polygons overlay tinted political colours on top,
# CK3-style, so the underlying geography stays readable.
const BASEMAP_PATH: String = "res://assets/map/mediterranean_500bce.png"
const BASEMAP_ASPECT: float = 1.5  # natural aspect ratio (w/h) of the generated image

# Overlay alpha — province fill uses this for the colour tint so the
# underlying coastline reads through. Borders are drawn at full alpha.
const OVERLAY_ALPHA: float       = 0.42
const OVERLAY_ALPHA_HOVER: float = 0.56
const OVERLAY_ALPHA_SELECT: float = 0.62

# Province polygons are built procedurally in `_ready()` because
# GDScript disallows PackedVector2Array in `const`. Every province
# is a hexagon placed at a hand-tuned centre in the basemap's
# normalised space (0..1 on each axis, origin top-left). Centres
# are calibrated against the generated basemap, NOT perfect lat/lon.
var PROVINCE_POLYGONS: Dictionary = {}

# Retained only to silence an earlier reference; superseded by the
# basemap image. Kept as an empty array so older code paths that
# iterate it stay safe.
var LANDMASS_POLYGONS: Array = []

# Source-of-truth province centres + hex radii (in basemap normalised
# space). Translated into polygons on ready. Keep this tuned against
# the generated basemap; if you regenerate the basemap, retune here.
var _PROVINCE_SPEC: Dictionary = {
	# --- Greek / Aegean -----------------------------------------------------
	"macedon":              [Vector2(0.470, 0.348), Vector2(0.026, 0.022), 0.0],
	"thrace":               [Vector2(0.522, 0.302), Vector2(0.028, 0.020), 0.0],
	"attica":               [Vector2(0.498, 0.475), Vector2(0.020, 0.020), 0.0],
	"corinthia":            [Vector2(0.478, 0.502), Vector2(0.018, 0.018), 0.0],
	"argolis":              [Vector2(0.498, 0.522), Vector2(0.018, 0.018), 0.0],
	"laconia":              [Vector2(0.482, 0.560), Vector2(0.022, 0.022), 0.0],
	# --- Anatolia / Persia --------------------------------------------------
	"ionia":                [Vector2(0.558, 0.440), Vector2(0.026, 0.022), 0.0],
	"lydia":                [Vector2(0.592, 0.388), Vector2(0.028, 0.024), 0.0],
	"media":                [Vector2(0.790, 0.350), Vector2(0.040, 0.032), 0.0],
	"persis":               [Vector2(0.860, 0.500), Vector2(0.038, 0.032), 0.0],
	# --- Egypt / North Africa ----------------------------------------------
	"lower_egypt":          [Vector2(0.650, 0.585), Vector2(0.028, 0.024), 0.0],
	"upper_egypt":          [Vector2(0.675, 0.760), Vector2(0.026, 0.055), 0.0],
	"africa_proconsularis": [Vector2(0.288, 0.608), Vector2(0.030, 0.028), 0.0],
	"libya_coast":          [Vector2(0.478, 0.680), Vector2(0.042, 0.028), 0.0],
	# --- Italy --------------------------------------------------------------
	"etruria":              [Vector2(0.302, 0.322), Vector2(0.022, 0.028), 0.0],
	"latium":               [Vector2(0.322, 0.380), Vector2(0.020, 0.025), 0.0],
	"campania":             [Vector2(0.344, 0.448), Vector2(0.022, 0.028), 0.0],
	"sicily":               [Vector2(0.372, 0.580), Vector2(0.030, 0.022), 0.0],
	# --- Gaul ---------------------------------------------------------------
	"gallia_belgica":       [Vector2(0.222, 0.108), Vector2(0.044, 0.036), 0.0],
	"gallia_celtica":       [Vector2(0.180, 0.222), Vector2(0.046, 0.042), 0.0],
	"massalia":             [Vector2(0.228, 0.302), Vector2(0.030, 0.024), 0.0],
	# --- Seas ---------------------------------------------------------------
	"aegean_sea":           [Vector2(0.532, 0.442), Vector2(0.024, 0.020), 0.0],
	"ionian_sea":           [Vector2(0.418, 0.502), Vector2(0.030, 0.024), 0.0],
	"tyrrhenian_sea":       [Vector2(0.258, 0.420), Vector2(0.028, 0.026), 0.0],
	"black_sea_coast":      [Vector2(0.615, 0.228), Vector2(0.048, 0.028), 0.0],
}


# --- Layout constants --------------------------------------------------------

const SHEET_W: float   = 1020.0
const SHEET_H: float   = 680.0
const PANEL_W: float   = 280.0

# --- Pan / zoom --------------------------------------------------------------
#
# The polygon drawing lives on an inner `_map_layer` (a `MapCanvas`)
# sitting inside the clipped `_canvas`. That layer is `MOUSE_FILTER_IGNORE`
# so every mouse event bubbles through to `_canvas.gui_input`, which is
# the single source of truth for pan / zoom / click. Zoom is anchored
# on the cursor; pan is left-click-drag on empty sea; a short click
# hit-tests against polygon geometry to select a province.
const ZOOM_MIN:   float = 0.60
const ZOOM_MAX:   float = 3.00
const ZOOM_STEP:  float = 1.15

# --- Nodes / state -----------------------------------------------------------

var _dimmer: ColorRect
var _sheet: PanelContainer
var _canvas: Panel
var _map_layer: Control
var _detail_panel: PanelContainer
var _detail_vbox: VBoxContainer
var _legend: HBoxContainer
var _selected_province_id: String = ""

var _zoom: float = 1.0
var _pan:  Vector2 = Vector2.ZERO
var _panning: bool = false
var _pan_anchor: Vector2 = Vector2.ZERO

## A single floating PanelContainer that follows the cursor to show a
## small "cartouche" of info about the hovered province. Reused across
## tiles instead of being instanced per-tile.
var _cartouche: PanelContainer
var _cartouche_vbox: VBoxContainer
var _cartouche_target: Control


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	_build_polygons_from_spec()
	_basemap = _load_basemap()
	_build_dimmer()
	_build_sheet()
	_build_cartouche()
	_render_canvas()
	_render_placeholder_detail()
	_render_legend()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.20)

	KingdomEconomy.tick.connect(_on_economy_tick)
	Relations.relation_changed.connect(_on_relation_changed)
	Unrest.province_unrest_changed.connect(_on_unrest_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()


func close() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func() -> void:
		closed.emit()
		queue_free())


# --- Chrome ------------------------------------------------------------------

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

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	# Canvas on the left.
	_canvas = Panel.new()
	var csb: StyleBoxFlat = StyleBoxFlat.new()
	csb.bg_color = Color(0.88, 0.82, 0.68, 1.0)
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

	# Inner layer that pans and scales. This is a custom Control
	# whose `_draw()` delegates back to us (`draw_map_canvas`). It
	# ignores mouse events so every click / drag / wheel reaches the
	# clipped `_canvas` above, which does the actual input work.
	_map_layer = MapCanvas.new()
	(_map_layer as MapCanvas).drawer = self
	_map_layer.anchor_right = 0.0
	_map_layer.anchor_bottom = 0.0
	_map_layer.mouse_filter = MOUSE_FILTER_IGNORE
	_canvas.add_child(_map_layer)

	# Detail column on the right.
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

	# Legend + close button row.
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


# --- Canvas: province polygons ----------------------------------------------

## Cache of cached pixel-space polygons keyed by province id. Recomputed
## whenever the canvas resizes. Used by both `_draw()` and the
## point-in-polygon hit tester so both agree on geometry.
var _pixel_polys: Dictionary = {}
var _pixel_landmasses: Array = []
var _hovered_province_id: String = ""

## Rect inside the _map_layer where the basemap image is drawn,
## letterboxed to preserve aspect ratio. Polygon coordinates are
## mapped into this rect so they line up with the drawn geography.
var _map_rect: Rect2 = Rect2()
var _basemap: Texture2D = null


func _build_polygons_from_spec() -> void:
	PROVINCE_POLYGONS.clear()
	for pid in _PROVINCE_SPEC.keys():
		var entry: Array = _PROVINCE_SPEC[pid]
		var centre: Vector2 = entry[0]
		var radius: Vector2 = entry[1]
		var rotation: float = float(entry[2]) if entry.size() > 2 else 0.0
		PROVINCE_POLYGONS[pid] = _hex_polygon(centre, radius, rotation)


static func _hex_polygon(centre: Vector2, radius: Vector2, rotation: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i in range(6):
		var a: float = rotation + float(i) * (PI / 3.0)
		out.append(Vector2(
			centre.x + cos(a) * radius.x,
			centre.y + sin(a) * radius.y,
		))
	return out


func _load_basemap() -> Texture2D:
	var tex: Texture2D = load(BASEMAP_PATH) as Texture2D
	if tex != null:
		return tex
	var img: Image = Image.new()
	if img.load(BASEMAP_PATH) == OK:
		return ImageTexture.create_from_image(img)
	push_warning("[MapView] basemap missing at %s" % BASEMAP_PATH)
	return null


func _render_canvas() -> void:
	if _map_layer == null:
		return
	call_deferred("_refresh_map")


func _refresh_map() -> void:
	if _canvas == null or _map_layer == null:
		return
	var rect: Vector2 = _canvas.size
	if rect.x <= 0.0 or rect.y <= 0.0:
		call_deferred("_refresh_map")
		return
	# Letterbox the basemap inside the canvas so the drawn geography
	# never gets horizontally or vertically squashed. Polygons live in
	# the letterboxed rect's local space.
	var fit_w: float = rect.x
	var fit_h: float = rect.x / BASEMAP_ASPECT
	if fit_h > rect.y:
		fit_h = rect.y
		fit_w = rect.y * BASEMAP_ASPECT
	var off: Vector2 = Vector2((rect.x - fit_w) * 0.5, (rect.y - fit_h) * 0.5)
	_map_rect = Rect2(off, Vector2(fit_w, fit_h))
	_map_layer.size = rect
	_rebuild_pixel_polys(_map_rect)
	(_map_layer as MapCanvas).queue_redraw()
	_apply_transform()


func _rebuild_pixel_polys(rect: Rect2) -> void:
	_pixel_polys.clear()
	for pid in PROVINCE_POLYGONS.keys():
		_pixel_polys[pid] = _norm_poly_to_px(PROVINCE_POLYGONS[pid], rect)


func _norm_poly_to_px(norm: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for p in norm:
		out.append(Vector2(
			rect.position.x + p.x * rect.size.x,
			rect.position.y + p.y * rect.size.y,
		))
	return out


## Called by `MapCanvas._draw()`. All coordinates are in the layer's
## local space. The pan/zoom transform is applied by the layer's
## `scale` and `position`, not here.
func draw_map_canvas(c: Control) -> void:
	if _map_rect.size == Vector2.ZERO:
		return

	# 1. Deep-water wash behind the basemap — only visible in the
	# letterbox bands when the canvas aspect differs from the image.
	c.draw_rect(
		Rect2(Vector2.ZERO, c.size),
		Color(0.48, 0.58, 0.64, 0.40),
		true
	)

	# 2. The real basemap — geography (coastlines, rivers, mountains)
	# drawn once, covering the letterboxed rect.
	if _basemap != null:
		c.draw_texture_rect(_basemap, _map_rect, false)

	# 3. Political overlay — each province tints its region with the
	# owning kingdom's colour. Alpha is deliberately low so the map
	# reads through, CK3-style. Sea provinces keep a cooler tint.
	for pid in _pixel_polys.keys():
		var p: Province = WorldData.get_province(pid)
		if p == null:
			continue
		var poly: PackedVector2Array = _pixel_polys[pid]
		var is_sea: bool = p.owning_kingdom.is_empty()
		var base: Color = COLOR_SEA_BG if is_sea else _kingdom_bg(p.owning_kingdom)
		var border: Color = COLOR_SEA_BORDER if is_sea else _kingdom_border(p.owning_kingdom)
		var alpha: float = OVERLAY_ALPHA
		if pid == _selected_province_id:
			alpha = OVERLAY_ALPHA_SELECT
		elif pid == _hovered_province_id:
			alpha = OVERLAY_ALPHA_HOVER
		var fill: Color = Color(base.r, base.g, base.b, alpha)
		c.draw_colored_polygon(poly, fill)
		_draw_closed_polyline(c, poly, border, 1.6 if pid == _selected_province_id else 1.1)

	# 4. Labels — province name at polygon centroid, owner tag below
	# for land provinces. Sizes scale inversely with zoom so they
	# stay legible at any zoom level.
	var font: Font = ThemeDB.fallback_font
	var base_size: float = 11.0
	var label_size: int = int(clampf(base_size / max(_zoom, 0.6), 9.0, 14.0))
	var owner_size: int = int(clampf(9.0 / max(_zoom, 0.6), 8.0, 12.0))
	for pid in _pixel_polys.keys():
		var p: Province = WorldData.get_province(pid)
		if p == null:
			continue
		var poly: PackedVector2Array = _pixel_polys[pid]
		var is_sea: bool = p.owning_kingdom.is_empty()
		var centroid: Vector2 = _poly_centroid(poly)
		# Labels use dark sepia ink so they read against both the
		# papyrus basemap and the kingdom tint.
		var ink: Color = Color(0.16, 0.10, 0.05, 0.95) if not is_sea else Color(0.10, 0.18, 0.25, 0.9)
		# Draw a tiny offset "shadow" for legibility over busy map detail.
		var halo: Color = Color(1.0, 0.96, 0.88, 0.70) if not is_sea else Color(0.92, 0.96, 1.0, 0.65)
		var name_w: float = font.get_string_size(
			p.province_name, HORIZONTAL_ALIGNMENT_CENTER, -1, label_size
		).x
		var name_pos: Vector2 = Vector2(centroid.x - name_w * 0.5, centroid.y)
		c.draw_string(font, name_pos + Vector2(1, 1), p.province_name,
			HORIZONTAL_ALIGNMENT_CENTER, -1, label_size, halo)
		c.draw_string(font, name_pos, p.province_name,
			HORIZONTAL_ALIGNMENT_CENTER, -1, label_size, ink)
		if not is_sea:
			var owner_text: String = _owner_short(p)
			if owner_text != "" and owner_text != "—":
				var ow: float = font.get_string_size(
					owner_text, HORIZONTAL_ALIGNMENT_CENTER, -1, owner_size
				).x
				var owner_pos: Vector2 = Vector2(
					centroid.x - ow * 0.5,
					centroid.y + label_size + 1.0,
				)
				c.draw_string(font, owner_pos + Vector2(1, 1), owner_text,
					HORIZONTAL_ALIGNMENT_CENTER, -1, owner_size, halo)
				c.draw_string(font, owner_pos, owner_text,
					HORIZONTAL_ALIGNMENT_CENTER, -1, owner_size, ink.darkened(0.05))


func _draw_closed_polyline(c: Control, poly: PackedVector2Array, col: Color, width: float) -> void:
	if poly.size() < 2:
		return
	var closed: PackedVector2Array = poly.duplicate()
	closed.append(poly[0])
	c.draw_polyline(closed, col, width, true)


func _poly_centroid(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var acc: Vector2 = Vector2.ZERO
	for p in poly:
		acc += p
	return acc / float(poly.size())


## Convert a canvas-local point (the mouse position as received in
## `_canvas.gui_input`) to the layer's own coordinate space, where the
## polygon geometry lives.
func _canvas_to_layer(canvas_pt: Vector2) -> Vector2:
	if _zoom <= 0.0001:
		return canvas_pt - _pan
	return (canvas_pt - _pan) / _zoom


func _find_province_at(canvas_pt: Vector2) -> Province:
	var layer_pt: Vector2 = _canvas_to_layer(canvas_pt)
	for pid in _pixel_polys.keys():
		if Geometry2D.is_point_in_polygon(layer_pt, _pixel_polys[pid]):
			var p: Province = WorldData.get_province(pid)
			if p != null:
				return p
	return null


func _on_province_clicked(p: Province) -> void:
	_selected_province_id = p.id
	_render_detail(p)
	(_map_layer as MapCanvas).queue_redraw()


# --- Detail panel ------------------------------------------------------------

func _render_placeholder_detail() -> void:
	_clear_detail()
	var l: Label = Label.new()
	l.text = "Select a land."
	l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	l.add_theme_font_size_override("font_size", 12)
	_detail_vbox.add_child(l)

	var note: Label = Label.new()
	note.text = "Colour washes denote the crown that holds each land. Wheel to zoom, drag on empty sea to shift the sheet. Click a land to read it."
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
	elif p.owning_kingdom.is_empty():
		owner_line = "No crown holds this water"
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
		_detail_vbox.add_child(_make_heading("MOOD"))
		_detail_vbox.add_child(_make_line(p.unrest_phrase()))

	_detail_vbox.add_child(_make_heading("WHAT IT PRODUCES"))
	var prod: Array[String] = _production_phrases(p)
	if prod.is_empty():
		_detail_vbox.add_child(_make_line("Little of consequence."))
	else:
		for phrase in prod:
			_detail_vbox.add_child(_make_line("•  %s" % phrase))

	if k != null:
		_detail_vbox.add_child(_make_divider())
		_detail_vbox.add_child(_make_heading("THE CROWN IT FEEDS"))
		_detail_vbox.add_child(_make_line(
			"%s — %s" % [k.kingdom_name, k.treasury_condition_name()]
		))
		_detail_vbox.add_child(_make_line(k.tax_level_phrase() + "."))

		var at_war: Array[String] = Relations.ids_in_state(k.id, int(Relations.RelationState.AT_WAR))
		var hostile: Array[String] = Relations.ids_in_state(k.id, int(Relations.RelationState.HOSTILE))
		var friendly: Array[String] = Relations.ids_in_state(k.id, int(Relations.RelationState.FRIENDLY))
		var allied: Array[String] = Relations.ids_in_state(k.id, int(Relations.RelationState.ALLIED))

		if not (at_war.is_empty() and hostile.is_empty() and friendly.is_empty() and allied.is_empty()):
			_detail_vbox.add_child(_make_divider())
			_detail_vbox.add_child(_make_heading("HOW IT STANDS WITH ITS NEIGHBOURS"))
			if not at_war.is_empty():
				_detail_vbox.add_child(_make_line("•  At war with %s." % _join_kingdom_names(at_war)))
			if not hostile.is_empty():
				_detail_vbox.add_child(_make_line("•  Cold with %s." % _join_kingdom_names(hostile)))
			if not friendly.is_empty():
				_detail_vbox.add_child(_make_line("•  Warm with %s." % _join_kingdom_names(friendly)))
			if not allied.is_empty():
				_detail_vbox.add_child(_make_line("•  Sworn to %s." % _join_kingdom_names(allied)))


func _join_kingdom_names(ids: Array[String]) -> String:
	var names: Array[String] = []
	for id in ids:
		var k: Kingdom = WorldData.get_kingdom(id)
		names.append(k.kingdom_name if k != null else id)
	if names.size() == 1:
		return names[0]
	if names.size() == 2:
		return "%s and %s" % [names[0], names[1]]
	var last: String = names.pop_back()
	return "%s, and %s" % [", ".join(names), last]


func _clear_detail() -> void:
	for c in _detail_vbox.get_children():
		c.queue_free()


# --- Legend ------------------------------------------------------------------

func _render_legend() -> void:
	for c in _legend.get_children():
		c.queue_free()
	var ids: Array = KINGDOM_COLORS.keys()
	ids.sort()
	for id in ids:
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
	sb.bg_color = _kingdom_bg(k.id)
	sb.border_color = _kingdom_border(k.id)
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


# --- Hooks -------------------------------------------------------------------

func _on_canvas_mouse_exited() -> void:
	if _hovered_province_id != "":
		_hovered_province_id = ""
		if _cartouche != null:
			_cartouche.visible = false
			_cartouche_target = null
		if _map_layer != null:
			(_map_layer as MapCanvas).queue_redraw()


func _on_canvas_resized() -> void:
	# The canvas size drives pixel polygon geometry. Rebuild on every
	# resize so the map fills the current viewport rather than being
	# stuck to the first (often tiny) layout pass.
	_refresh_map()


func _on_economy_tick(_snap: Array) -> void:
	_refresh_map()
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
	if _map_layer != null:
		(_map_layer as MapCanvas).queue_redraw()
	if province_id != _selected_province_id:
		return
	var p: Province = WorldData.get_province(province_id)
	if p != null:
		_render_detail(p)


# --- Helpers -----------------------------------------------------------------

func _kingdom_bg(id: String) -> Color:
	var base: Color = KINGDOM_COLORS.get(id, COLOR_UNCLAIMED)
	return base.lightened(0.15)


func _kingdom_border(id: String) -> Color:
	var k: Kingdom = WorldData.get_kingdom(id)
	var base: Color = KINGDOM_COLORS.get(id, COLOR_UNCLAIMED)
	# Border leans redder as the treasury degrades — a subtle "bleed"
	# cue the player can read at a glance.
	if k == null:
		return base.darkened(0.35)
	match k.treasury_condition:
		Kingdom.TreasuryCondition.FLUSH:    return base.darkened(0.35)
		Kingdom.TreasuryCondition.STABLE:   return base.darkened(0.30)
		Kingdom.TreasuryCondition.STRAINED: return Color(0.62, 0.45, 0.10, 1.0)
		Kingdom.TreasuryCondition.INDEBTED: return Color(0.72, 0.28, 0.12, 1.0)
		Kingdom.TreasuryCondition.BROKE:    return Color(0.55, 0.08, 0.08, 1.0)
		_:                                  return base.darkened(0.35)


func _owner_short(p: Province) -> String:
	if p.owning_kingdom.is_empty():
		return "—"
	var k: Kingdom = WorldData.get_kingdom(p.owning_kingdom)
	if k == null:
		return p.owning_kingdom
	return k.kingdom_name


func _readable_ink(bg: Color) -> Color:
	# Human eye luminance. Flip to parchment on a dark kingdom tile.
	var lum: float = 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b
	return Color(0.98, 0.94, 0.84, 1.0) if lum < 0.55 else COLOR_INK


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


# --- Pan / zoom --------------------------------------------------------------
#
# Pan: left-click-drag on empty canvas area (tiles eat their own clicks).
# Zoom: mouse wheel anchored on the cursor, so zooming in keeps the
# province under the pointer roughly under the pointer.

var _press_pos: Vector2 = Vector2.ZERO
var _press_dragged: bool = false
const _CLICK_SLOP: float = 4.0


func _on_canvas_gui_input(event: InputEvent) -> void:
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
				_pan_anchor = mb.position
				_press_pos = mb.position
				_press_dragged = false
				accept_event()
			else:
				# On release: if the cursor didn't travel far, treat it
				# as a click and hit-test against province polygons.
				# Otherwise it was a pan drag and we swallow it.
				var was_panning: bool = _panning
				_panning = false
				if was_panning and not _press_dragged:
					var p: Province = _find_province_at(mb.position)
					if p != null:
						_on_province_clicked(p)
				accept_event()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _panning:
			if not _press_dragged and mm.position.distance_to(_press_pos) > _CLICK_SLOP:
				_press_dragged = true
			if _press_dragged:
				_pan += mm.relative
				_apply_transform()
		else:
			_update_hover(mm.position)
		accept_event()


func _update_hover(canvas_pt: Vector2) -> void:
	var p: Province = _find_province_at(canvas_pt)
	var new_id: String = "" if p == null else p.id
	if new_id == _hovered_province_id:
		if p != null:
			_position_cartouche_at_mouse(canvas_pt)
		return
	_hovered_province_id = new_id
	if p == null:
		if _cartouche != null:
			_cartouche.visible = false
			_cartouche_target = null
	else:
		_show_cartouche_at(p, canvas_pt)
	if _map_layer != null:
		(_map_layer as MapCanvas).queue_redraw()


func _zoom_at(canvas_pt: Vector2, factor: float) -> void:
	var new_zoom: float = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(new_zoom, _zoom):
		return
	# Keep the point under the cursor stable: translate so that the
	# canvas-space anchor maps to the same layer-space point before
	# and after the scale change.
	var before: Vector2 = (canvas_pt - _pan) / _zoom
	_zoom = new_zoom
	_pan = canvas_pt - before * _zoom
	_apply_transform()


func _apply_transform() -> void:
	if _map_layer == null:
		return
	_map_layer.scale = Vector2(_zoom, _zoom)
	_map_layer.position = _pan


func _reset_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	_apply_transform()


# --- Cartouche ---------------------------------------------------------------
#
# A small floating parchment tag that hovers above the currently hovered
# province tile. Shows three lines:
#   1. the province name
#   2. the crown that holds it
#   3. its current disturbance (war / revolt / plague / famine), or a
#      neutral phrase if nothing is troubling it
#
# The cartouche is built once and re-used — we just re-populate it and
# re-position it on each hover.

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


func _show_cartouche_at(p: Province, canvas_pt: Vector2) -> void:
	_show_cartouche_for(p, null)
	_position_cartouche_at_mouse(canvas_pt)


func _position_cartouche_at_mouse(canvas_pt: Vector2) -> void:
	if _cartouche == null or not _cartouche.visible:
		return
	# `canvas_pt` is in _canvas-local space; translate to global.
	var global_anchor: Vector2 = _canvas.global_position + canvas_pt
	var card_size: Vector2 = _cartouche.size
	var viewport_rect: Rect2 = get_viewport_rect()
	var x: float = global_anchor.x - card_size.x * 0.5
	var y: float = global_anchor.y - card_size.y - 14.0
	if y < viewport_rect.position.y + 8.0:
		y = global_anchor.y + 18.0
	x = clampf(
		x,
		viewport_rect.position.x + 6.0,
		viewport_rect.position.x + viewport_rect.size.x - card_size.x - 6.0,
	)
	_cartouche.position = Vector2(x, y)


func _show_cartouche_for(p: Province, over: Control) -> void:
	if _cartouche == null:
		return
	_cartouche_target = over
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

	var disturbance: String = _cartouche_disturbance_line(p)
	if disturbance != "":
		var dist_l: Label = Label.new()
		dist_l.text = disturbance
		dist_l.add_theme_color_override("font_color", COLOR_INK)
		dist_l.add_theme_font_size_override("font_size", 11)
		_cartouche_vbox.add_child(dist_l)

	# Force a layout pass so `_cartouche.size` is current; the caller
	# then positions it (over a node or at the mouse).
	_cartouche.visible = true
	_cartouche.reset_size()


func _hide_cartouche_if(over: Control) -> void:
	if _cartouche == null:
		return
	if _cartouche_target == over:
		_cartouche.visible = false
		_cartouche_target = null


func _cartouche_owner_line(p: Province) -> String:
	if p.owning_kingdom.is_empty():
		return "No crown. Only water."
	var k: Kingdom = WorldData.get_kingdom(p.owning_kingdom)
	if k == null:
		return p.owning_kingdom
	return "Of %s." % k.kingdom_name


func _cartouche_disturbance_line(p: Province) -> String:
	# Priority order: open hostilities > active disaster > prolonged revolt
	# > current mood band (only if noteworthy) > nothing to report.

	# 1. Disaster on this tile.
	if p.has_meta("prod_modifier"):
		var meta: Dictionary = p.get_meta("prod_modifier")
		var cause: String = String(meta.get("cause", ""))
		match cause:
			"plague":     return "Fever in the streets."
			"famine":     return "The grain did not come."
			"earthquake": return "The ground has moved."

	# 2. Kingdom is at war.
	if not p.owning_kingdom.is_empty():
		var at_war: Array[String] = Relations.ids_in_state(
			p.owning_kingdom, int(Relations.RelationState.AT_WAR)
		)
		if not at_war.is_empty():
			return "Under arms."

	# 3. Active unrest worth naming.
	if p.population > 0:
		match String(p.unrest_band()):
			"in revolt": return "In open revolt."
			"seething":  return "Seething."
			"restless":  return "Restless."

	return ""
