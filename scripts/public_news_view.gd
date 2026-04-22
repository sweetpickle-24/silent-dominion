extends Control
## Full-screen overlay for the Public Dispatches scroll on the table.
##
## Shows everything PublicNews has collected in reverse-chronological
## order. Headlines are bold; bodies are period-voice prose with
## BBCode actor links (same tag format as letters, so clicking a name
## opens the dossier).
##
## Closes on ESC or outside click. Emits `closed` when dismissed.
## Emits `actor_link_clicked(id)` so the table can route the name
## click into DossierView (matching LetterView's contract).

signal closed
signal actor_link_clicked(actor_id: StringName)
signal codebook_link_clicked(anchor: StringName)

# --- Visual tokens -----------------------------------------------------------

const COLOR_DIMMER: Color         = Color(0, 0, 0, 0.62)
const COLOR_PARCHMENT: Color      = Color(0.96, 0.92, 0.82, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.55, 0.42, 0.28, 0.7)
const COLOR_INK: Color            = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.22, 0.14, 0.06, 0.65)
const COLOR_HEADLINE: Color       = Color(0.15, 0.09, 0.04, 1.0)

# Per-event-kind accent for the small left margin dot.
const KIND_DOTS: Dictionary = {
	&"ruler_decree":          Color(0.40, 0.36, 0.14, 1.0),
	&"treasury_crisis":       Color(0.72, 0.28, 0.12, 1.0),
	&"death":                 Color(0.22, 0.14, 0.06, 1.0),
	&"assassination":         Color(0.55, 0.08, 0.08, 1.0),
	&"assassination_attempt": Color(0.55, 0.08, 0.08, 1.0),
	&"war_declaration":       Color(0.55, 0.08, 0.08, 1.0),
	&"succession":            Color(0.44, 0.36, 0.70, 1.0),
	&"regency":               Color(0.62, 0.45, 0.10, 1.0),
	&"host_won":              Color(0.18, 0.34, 0.22, 1.0),
	&"tax_change":            Color(0.62, 0.45, 0.10, 1.0),
	&"peace_declaration":     Color(0.18, 0.34, 0.22, 1.0),
	&"rumour":                Color(0.44, 0.36, 0.70, 1.0),
	&"idea_planted":          Color(0.44, 0.36, 0.70, 1.0),
	&"unrest":                Color(0.72, 0.28, 0.12, 1.0),
	&"misc":                  Color(0.22, 0.14, 0.06, 0.7),
}

# --- Nodes -------------------------------------------------------------------

var _dimmer: ColorRect
var _sheet: PanelContainer
var _body_margin: MarginContainer
var _body_vbox: VBoxContainer
var _scroll: ScrollContainer
var _list: VBoxContainer


# --- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	_build_dimmer()
	_build_sheet()
	_render_list()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)

	PublicNews.news_changed.connect(_render_list)
	PublicNews.mark_all_read()


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
	_dimmer.gui_input.connect(_on_dimmer_input)
	add_child(_dimmer)


func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


func _build_sheet() -> void:
	_sheet = PanelContainer.new()
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
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 28
	sb.shadow_offset = Vector2(0, 10)
	_sheet.add_theme_stylebox_override("panel", sb)
	_sheet.anchor_left = 0.5
	_sheet.anchor_top = 0.5
	_sheet.anchor_right = 0.5
	_sheet.anchor_bottom = 0.5
	_sheet.offset_left = -400.0
	_sheet.offset_right = 400.0
	_sheet.offset_top = -310.0
	_sheet.offset_bottom = 310.0
	_sheet.mouse_filter = MOUSE_FILTER_STOP
	add_child(_sheet)

	_body_margin = MarginContainer.new()
	_body_margin.add_theme_constant_override("margin_left", 32)
	_body_margin.add_theme_constant_override("margin_right", 32)
	_body_margin.add_theme_constant_override("margin_top", 24)
	_body_margin.add_theme_constant_override("margin_bottom", 24)
	_sheet.add_child(_body_margin)

	_body_vbox = VBoxContainer.new()
	_body_vbox.add_theme_constant_override("separation", 10)
	_body_margin.add_child(_body_vbox)


# --- List --------------------------------------------------------------------

func _render_list() -> void:
	for child in _body_vbox.get_children():
		child.queue_free()

	_body_vbox.add_child(_make_title("Public Dispatches"))
	_body_vbox.add_child(_make_subtitle(
		"Word as it reaches the markets, the gates, and the courts. Read only: these hands wrote it, not yours."
	))
	_body_vbox.add_child(_make_divider())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size.y = 460.0
	_body_vbox.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	var items: Array = PublicNews.events.duplicate()
	items.reverse()

	if items.is_empty():
		var empty: Label = Label.new()
		empty.text = "No word yet. The world is quieter than a thousand sleeping courts."
		empty.add_theme_color_override("font_color", COLOR_INK_MUTED)
		empty.add_theme_font_size_override("font_size", 13)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
	else:
		for e in items:
			_list.add_child(_build_dispatch(e))

	_body_vbox.add_child(_make_close_button("Set aside", func() -> void: close()))


func _build_dispatch(event: Dictionary) -> Control:
	var kind: StringName = StringName(String(event.get("kind", "misc")))
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)

	# Left margin dot, same visual language as the exposure indicator.
	var dot: Panel = Panel.new()
	dot.custom_minimum_size = Vector2(8, 8)
	var dot_sb: StyleBoxFlat = StyleBoxFlat.new()
	dot_sb.bg_color = KIND_DOTS.get(kind, KIND_DOTS[&"misc"])
	dot_sb.corner_radius_top_left = 4
	dot_sb.corner_radius_top_right = 4
	dot_sb.corner_radius_bottom_left = 4
	dot_sb.corner_radius_bottom_right = 4
	dot.add_theme_stylebox_override("panel", dot_sb)

	var dot_wrap: VBoxContainer = VBoxContainer.new()
	dot_wrap.custom_minimum_size.x = 14.0
	var top_pad: Control = Control.new()
	top_pad.custom_minimum_size.y = 6.0
	dot_wrap.add_child(top_pad)
	dot_wrap.add_child(dot)
	hb.add_child(dot_wrap)

	# Text column.
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	hb.add_child(col)

	var date_label: Label = Label.new()
	date_label.text = GameClock.format_absolute(int(event.get("abs_day", 0)))
	date_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
	date_label.add_theme_font_size_override("font_size", 10)
	col.add_child(date_label)

	var headline: Label = Label.new()
	headline.text = String(event.get("headline", ""))
	headline.add_theme_color_override("font_color", COLOR_HEADLINE)
	headline.add_theme_font_size_override("font_size", 15)
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(headline)

	var body: RichTextLabel = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.text = String(event.get("body", ""))
	body.add_theme_color_override("default_color", COLOR_INK)
	body.add_theme_font_size_override("normal_font_size", 13)
	body.meta_clicked.connect(_on_meta_clicked)
	body.meta_hover_started.connect(func(_m: Variant) -> void:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND))
	body.meta_hover_ended.connect(func(_m: Variant) -> void:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW))
	col.add_child(body)

	return hb


func _on_meta_clicked(meta: Variant) -> void:
	var s: String = String(meta)
	if s.begins_with("actor:"):
		var id: StringName = StringName(s.substr(len("actor:")))
		actor_link_clicked.emit(id)
		close()
	elif s.begins_with("codebook:"):
		var anchor: StringName = StringName(s.substr(len("codebook:")))
		codebook_link_clicked.emit(anchor)
		close()


# --- Widget factories --------------------------------------------------------

func _make_title(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_INK)
	l.add_theme_font_size_override("font_size", 22)
	return l


func _make_subtitle(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	l.add_theme_font_size_override("font_size", 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _make_divider() -> HSeparator:
	var s: HSeparator = HSeparator.new()
	s.add_theme_color_override("color", COLOR_PARCHMENT_EDGE)
	return s


func _make_close_button(label: String, on_press: Callable) -> Button:
	var b: Button = Button.new()
	b.text = label
	b.custom_minimum_size.y = 34.0
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", COLOR_INK)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(on_press)
	return b
