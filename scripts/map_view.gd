extends Control
## Full-screen overlay for the MapScroll object on the table.
##
## Phase-0 map: no true geography, just a parchment sheet with every
## province rendered as a small card placed at hand-tuned normalised
## co-ordinates that roughly match the ancient Mediterranean. Each
## card's background is coloured by its owning kingdom so the whole
## sheet reads as a political survey at a glance.
##
## Click a province to open a detail pane on the right with its
## terrain, climate, and qualitative production read-out. Sea
## provinces are styled differently and unclaimed.
##
## The map re-renders itself on KingdomEconomy.tick so condition
## changes propagate immediately; the coloured border of each card
## leans harder on red as the owner's treasury degrades.

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

# Hand-tuned normalised positions for each province. 0,0 top-left,
# 1,1 bottom-right of the canvas. Stored (x, y) pairs.
const PROVINCE_COORDS: Dictionary = {
	# Greek world
	"attica":           Vector2(0.52, 0.56),
	"laconia":          Vector2(0.51, 0.66),
	"corinthia":        Vector2(0.49, 0.56),
	"argolis":          Vector2(0.51, 0.60),
	"macedon":          Vector2(0.48, 0.36),
	"thrace":           Vector2(0.56, 0.30),
	# Anatolia / Persia
	"ionia":            Vector2(0.62, 0.50),
	"lydia":            Vector2(0.66, 0.44),
	"media":            Vector2(0.82, 0.42),
	"persis":           Vector2(0.88, 0.56),
	# Egypt / Africa
	"lower_egypt":      Vector2(0.66, 0.70),
	"upper_egypt":      Vector2(0.70, 0.82),
	"africa_proconsularis": Vector2(0.34, 0.72),
	"libya_coast":      Vector2(0.48, 0.82),
	# Italy
	"etruria":          Vector2(0.32, 0.42),
	"latium":           Vector2(0.34, 0.47),
	"campania":         Vector2(0.36, 0.52),
	"sicily":           Vector2(0.38, 0.63),
	# Gaul
	"gallia_belgica":   Vector2(0.18, 0.12),
	"gallia_celtica":   Vector2(0.14, 0.27),
	"massalia":         Vector2(0.22, 0.36),
	# Sea provinces
	"aegean_sea":       Vector2(0.54, 0.48),
	"ionian_sea":       Vector2(0.40, 0.56),
	"tyrrhenian_sea":   Vector2(0.28, 0.55),
	"black_sea_coast":  Vector2(0.64, 0.22),
}

# --- Layout constants --------------------------------------------------------

const SHEET_W: float   = 1020.0
const SHEET_H: float   = 680.0
const PANEL_W: float   = 280.0
const TILE_SIZE: Vector2 = Vector2(116, 40)
const TILE_HOVER_SCALE: Vector2 = Vector2(1.08, 1.08)

# --- Pan / zoom --------------------------------------------------------------
#
# All tiles live on an inner `_map_layer` Control that sits inside the
# clipped `_canvas`. Panning drags that layer; zooming scales it around
# the cursor. The tiles themselves do not know about zoom — they render
# at a fixed 1x pixel size and let the layer's transform do the work.
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
	row.add_child(_canvas)

	# Inner layer that we pan and scale. Tiles are added as children of
	# this layer; the canvas only provides the clipped viewport and
	# catches the gui input for pan/zoom.
	_map_layer = Control.new()
	_map_layer.anchor_right = 0.0
	_map_layer.anchor_bottom = 0.0
	_map_layer.mouse_filter = MOUSE_FILTER_PASS
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


# --- Canvas: province tiles --------------------------------------------------

func _render_canvas() -> void:
	if _map_layer == null:
		return
	for child in _map_layer.get_children():
		child.queue_free()
	# Deferred so _canvas.size has been computed by the layout pass.
	call_deferred("_place_tiles")


func _place_tiles() -> void:
	if _canvas == null or _map_layer == null:
		return
	var rect: Vector2 = _canvas.size
	if rect.x <= 0.0 or rect.y <= 0.0:
		call_deferred("_place_tiles")
		return
	# Size the inner layer to match the viewport so the first frame
	# is centered; pan/zoom then moves it around inside the clip.
	_map_layer.size = rect
	for pid in PROVINCE_COORDS.keys():
		var p: Province = WorldData.get_province(pid)
		if p == null:
			continue
		var pos_norm: Vector2 = PROVINCE_COORDS[pid]
		var tile: Control = _build_tile(p)
		tile.position = Vector2(
			pos_norm.x * rect.x - TILE_SIZE.x * 0.5,
			pos_norm.y * rect.y - TILE_SIZE.y * 0.5
		)
		_map_layer.add_child(tile)
	_apply_transform()


func _build_tile(p: Province) -> Control:
	var btn: Button = Button.new()
	btn.text = ""
	btn.custom_minimum_size = TILE_SIZE
	btn.size = TILE_SIZE
	btn.focus_mode = Control.FOCUS_NONE
	btn.pivot_offset = TILE_SIZE * 0.5
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	var is_sea: bool = p.owning_kingdom.is_empty()
	var base: Color = COLOR_SEA_BG if is_sea else _kingdom_bg(p.owning_kingdom)
	var border: Color = COLOR_SEA_BORDER if is_sea else _kingdom_border(p.owning_kingdom)

	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = base
	sb.border_color = border
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.shadow_color = Color(0, 0, 0, 0.18)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 1)
	btn.add_theme_stylebox_override("normal", sb)

	var hover_sb: StyleBoxFlat = sb.duplicate()
	hover_sb.bg_color = base.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)

	var margin: MarginContainer = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	btn.add_child(margin)

	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	margin.add_child(v)

	var name_l: Label = Label.new()
	name_l.text = p.province_name
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.add_theme_color_override("font_color", _readable_ink(base))
	name_l.add_theme_font_size_override("font_size", 11)
	v.add_child(name_l)

	var owner_l: Label = Label.new()
	owner_l.text = _owner_short(p)
	owner_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	owner_l.add_theme_color_override("font_color", _readable_ink(base).darkened(0.1))
	owner_l.add_theme_font_size_override("font_size", 9)
	v.add_child(owner_l)

	btn.mouse_entered.connect(func() -> void:
		_tile_hover(btn, true)
		_show_cartouche_for(p, btn))
	btn.mouse_exited.connect(func() -> void:
		_tile_hover(btn, false)
		_hide_cartouche_if(btn))
	btn.pressed.connect(func() -> void: _on_tile_clicked(p))
	return btn


func _tile_hover(btn: Button, on: bool) -> void:
	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", TILE_HOVER_SCALE if on else Vector2.ONE, 0.12)


func _on_tile_clicked(p: Province) -> void:
	_selected_province_id = p.id
	_render_detail(p)


# --- Detail panel ------------------------------------------------------------

func _render_placeholder_detail() -> void:
	_clear_detail()
	var l: Label = Label.new()
	l.text = "Select a land."
	l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	l.add_theme_font_size_override("font_size", 12)
	_detail_vbox.add_child(l)

	var note: Label = Label.new()
	note.text = "Every tile is a province. Colour denotes the crown it serves; the dark band along its foot brightens as that crown's coffers degrade."
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

func _on_canvas_resized() -> void:
	# The canvas size is what drives tile positions. On the first
	# layout pass the size can tick from 0 up to its final value in
	# several steps; re-place tiles each time rather than locking in
	# the first (possibly tiny) rect.
	_render_canvas()


func _on_economy_tick(_snap: Array) -> void:
	_render_canvas()
	# If a province is selected, re-render its detail so condition cues refresh.
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
				accept_event()
			else:
				_panning = false
	elif event is InputEventMouseMotion and _panning:
		var mm: InputEventMouseMotion = event
		_pan += mm.relative
		_apply_transform()
		accept_event()


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

	# Force a layout pass before we read the cartouche's own size so
	# we can position it precisely above the tile.
	_cartouche.visible = true
	_cartouche.reset_size()
	call_deferred("_position_cartouche_over", over)


func _position_cartouche_over(over: Control) -> void:
	if _cartouche == null or over == null or not is_instance_valid(over):
		return
	if _cartouche_target != over:
		return   # hover moved to another tile already
	var tile_rect: Rect2 = over.get_global_rect()
	var card_size: Vector2 = _cartouche.size
	var viewport_rect: Rect2 = get_viewport_rect()
	var x: float = tile_rect.position.x + tile_rect.size.x * 0.5 - card_size.x * 0.5
	var y: float = tile_rect.position.y - card_size.y - 8.0
	# If the card would clip off the top of the screen, drop it below
	# the tile instead.
	if y < viewport_rect.position.y + 8.0:
		y = tile_rect.position.y + tile_rect.size.y + 8.0
	# Keep inside viewport horizontally.
	x = clampf(
		x,
		viewport_rect.position.x + 6.0,
		viewport_rect.position.x + viewport_rect.size.x - card_size.x - 6.0,
	)
	_cartouche.position = Vector2(x, y)


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
