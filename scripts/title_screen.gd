extends Control
## Title scene for Silent Dominion.
##
## Deliberately spare: parchment, a title, a subtitle, three choices,
## a small dateline. No splash animation, no studio logo. The aesthetic
## is the same one the table wears — same font stack, same color
## palette, same soft drop shadows.

const TABLE_SCENE: String = "res://scenes/table/table.tscn"

## Keep in sync with SlotsView. The quicksave slot is listed first, then
## named slots in order, so the most-recently-used convention is obvious.
const SLOT_IDS: Array[String] = ["autosave", "quicksave", "slot_1", "slot_2", "slot_3"]
const SLOT_LABELS: Dictionary = {
	"autosave":  "Last fold (auto)",
	"quicksave": "Quick fold",
	"slot_1":    "The first fold",
	"slot_2":    "The second fold",
	"slot_3":    "The third fold",
}

const COLOR_PARCHMENT: Color      = Color(0.96, 0.92, 0.82, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.55, 0.42, 0.28, 0.7)
const COLOR_INK: Color            = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.22, 0.14, 0.06, 0.65)
const COLOR_ACCENT: Color         = Color(0.55, 0.08, 0.08, 1.0)
const COLOR_WOOD_TOP: Color       = Color(0.18, 0.12, 0.08, 1.0)
const COLOR_WOOD_BOT: Color       = Color(0.10, 0.06, 0.04, 1.0)

var _sheet: PanelContainer
var _vbox: VBoxContainer


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	_build_background()
	_build_sheet()
	_populate()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, Prefs.anim_duration(0.45))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
			get_viewport().set_input_as_handled()


# --- Chrome ------------------------------------------------------------------

func _build_background() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = COLOR_WOOD_BOT
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	var grad: Gradient = Gradient.new()
	grad.set_color(0, COLOR_WOOD_TOP)
	grad.set_color(1, COLOR_WOOD_BOT)
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to   = Vector2(0.5, 1.0)
	var tex_rect: TextureRect = TextureRect.new()
	tex_rect.texture = tex
	tex_rect.anchor_right = 1.0
	tex_rect.anchor_bottom = 1.0
	tex_rect.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(tex_rect)

	# Vignette edge
	var vgrad: Gradient = Gradient.new()
	vgrad.set_color(0, Color(0, 0, 0, 0))
	vgrad.set_color(1, Color(0, 0, 0, 0.55))
	var vtex: GradientTexture2D = GradientTexture2D.new()
	vtex.gradient = vgrad
	vtex.fill = GradientTexture2D.FILL_RADIAL
	vtex.fill_from = Vector2(0.5, 0.5)
	vtex.fill_to   = Vector2(1.0, 0.5)
	var vignette: TextureRect = TextureRect.new()
	vignette.texture = vtex
	vignette.anchor_right = 1.0
	vignette.anchor_bottom = 1.0
	vignette.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(vignette)


func _build_sheet() -> void:
	_sheet = PanelContainer.new()
	_sheet.anchor_left = 0.5
	_sheet.anchor_top = 0.5
	_sheet.anchor_right = 0.5
	_sheet.anchor_bottom = 0.5
	_sheet.offset_left = -300.0
	_sheet.offset_right = 300.0
	_sheet.offset_top = -260.0
	_sheet.offset_bottom = 260.0
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = COLOR_PARCHMENT
	sb.border_color = COLOR_PARCHMENT_EDGE
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 34
	sb.shadow_offset = Vector2(0, 14)
	_sheet.add_theme_stylebox_override("panel", sb)
	add_child(_sheet)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	_sheet.add_child(margin)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 8)
	_vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(_vbox)


# --- Content -----------------------------------------------------------------

func _populate() -> void:
	var title: Label = Label.new()
	title.text = "Silent Dominion"
	title.add_theme_color_override("font_color", COLOR_INK)
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "The Mediterranean, 500 before the common era."
	subtitle.add_theme_color_override("font_color", COLOR_INK_MUTED)
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(subtitle)

	var spacer1: Control = Control.new()
	spacer1.custom_minimum_size.y = 14.0
	_vbox.add_child(spacer1)

	var blurb: Label = Label.new()
	blurb.text = "You sit at a table. You do not sit on a throne. The world runs on courts and grain and weather; you run on letters. Take your time."
	blurb.add_theme_color_override("font_color", COLOR_INK)
	blurb.add_theme_font_size_override("font_size", 13)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(blurb)

	var spacer2: Control = Control.new()
	spacer2.custom_minimum_size.y = 24.0
	_vbox.add_child(spacer2)

	_vbox.add_child(_make_primary_button("Begin a new season", _on_begin))

	if Session.any_save_exists():
		var label_spacer: Control = Control.new()
		label_spacer.custom_minimum_size.y = 8.0
		_vbox.add_child(label_spacer)

		var heading: Label = Label.new()
		heading.text = "OR RETURN TO A STORED SEASON"
		heading.add_theme_color_override("font_color", COLOR_INK_MUTED)
		heading.add_theme_font_size_override("font_size", 10)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_vbox.add_child(heading)

		for slot in SLOT_IDS:
			var info: Dictionary = SaveManager.slot_info(slot)
			if info.is_empty():
				continue
			_vbox.add_child(_make_slot_row(slot, info))

	_vbox.add_child(_make_ghost_button("Leave the table", _on_quit))

	var spacer3: Control = Control.new()
	spacer3.custom_minimum_size.y = 18.0
	_vbox.add_child(spacer3)

	var credit: Label = Label.new()
	credit.text = "ESC to leave.  Once the table is before you, F10 opens the archive."
	credit.add_theme_color_override("font_color", COLOR_INK_MUTED)
	credit.add_theme_font_size_override("font_size", 10)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(credit)


func _make_primary_button(text: String, cb: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size.y = 40.0
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.85, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(0.96, 0.92, 0.82, 0.9))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_stylebox_override("normal", _primary_bg(0))
	b.add_theme_stylebox_override("hover", _primary_bg(1))
	b.add_theme_stylebox_override("pressed", _primary_bg(2))
	b.add_theme_stylebox_override("focus", _primary_bg(1))
	b.pressed.connect(cb)
	return b


func _make_secondary_button(text: String, cb: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size.y = 36.0
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_color_override("font_color", COLOR_INK)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_stylebox_override("normal", _ghost_bg(0))
	b.add_theme_stylebox_override("hover", _ghost_bg(1))
	b.add_theme_stylebox_override("pressed", _ghost_bg(2))
	b.add_theme_stylebox_override("focus", _ghost_bg(1))
	b.pressed.connect(cb)
	return b


func _make_ghost_button(text: String, cb: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size.y = 32.0
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_color_override("font_color", COLOR_INK_MUTED)
	b.add_theme_color_override("font_hover_color", COLOR_INK)
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	return b


func _primary_bg(state: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	match state:
		0: sb.bg_color = COLOR_ACCENT
		1: sb.bg_color = COLOR_ACCENT.lightened(0.08)
		_: sb.bg_color = COLOR_ACCENT.darkened(0.08)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _ghost_bg(state: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	match state:
		0: sb.bg_color = Color(0.92, 0.86, 0.72, 1.0)
		1: sb.bg_color = Color(0.95, 0.90, 0.78, 1.0)
		_: sb.bg_color = Color(0.88, 0.82, 0.68, 1.0)
	sb.border_color = COLOR_PARCHMENT_EDGE
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


# --- Actions -----------------------------------------------------------------

func _on_begin() -> void:
	Session.pending_load_slot = ""
	_go_to_table()


func _on_slot_pressed(slot: String) -> void:
	if not SaveManager.slot_exists(slot):
		_on_begin()
		return
	Session.pending_load_slot = slot
	_go_to_table()


func _make_slot_row(slot: String, info: Dictionary) -> Control:
	var btn: Button = Button.new()
	btn.custom_minimum_size.y = 42.0
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_stylebox_override("normal", _ghost_bg(0))
	btn.add_theme_stylebox_override("hover", _ghost_bg(1))
	btn.add_theme_stylebox_override("pressed", _ghost_bg(2))
	btn.add_theme_stylebox_override("focus", _ghost_bg(1))
	btn.pressed.connect(func() -> void: _on_slot_pressed(slot))

	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hb)

	var label_name: Label = Label.new()
	label_name.text = String(SLOT_LABELS.get(slot, slot))
	label_name.add_theme_color_override("font_color", COLOR_INK)
	label_name.add_theme_font_size_override("font_size", 13)
	label_name.custom_minimum_size.x = 130.0
	hb.add_child(label_name)

	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 1)
	hb.add_child(col)

	var ingame: Label = Label.new()
	ingame.text = _format_ingame(info)
	ingame.add_theme_color_override("font_color", COLOR_INK)
	ingame.add_theme_font_size_override("font_size", 12)
	col.add_child(ingame)

	var saved_at: String = String(info.get("saved_at", ""))
	if saved_at != "":
		var saved_label: Label = Label.new()
		saved_label.text = "saved %s" % saved_at
		saved_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
		saved_label.add_theme_font_size_override("font_size", 10)
		col.add_child(saved_label)

	return btn


func _format_ingame(info: Dictionary) -> String:
	var abs_day: int = GameClock.absolute_day_of(
		int(info.get("year", 0)),
		int(info.get("month", 1)),
		int(info.get("day", 1))
	)
	return GameClock.format_absolute(abs_day)


func _on_quit() -> void:
	get_tree().quit()


func _go_to_table() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, Prefs.anim_duration(0.20))
	tw.tween_callback(func() -> void:
		get_tree().change_scene_to_file(TABLE_SCENE))
