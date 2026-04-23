extends Control
## §C5 Branched-dialogue overlay for a live immortal encounter.
##
## Opens when `Immortals.dialogue_requested` fires — typically from a
## successful `request_contact` action. The player reads the peer's
## opening text and picks one of 3–5 branches; the choice is resolved
## through `Immortals.resolve_dialogue_choice`, which applies the
## consequence (relationship change, mandate offer, exposure bump,
## etc.) and returns the prose result for the view to render.
##
## Visual tone: parchment sheet on a dimmed table, the same family
## as LibraryView — we deliberately reuse its palette so the player
## does not need to context-switch into a new UI grammar.

signal closed

const COLOR_DIMMER: Color         = Color(0, 0, 0, 0.62)
const COLOR_PARCHMENT: Color      = Color(0.96, 0.92, 0.82, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.55, 0.42, 0.28, 0.7)
const COLOR_INK: Color            = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.22, 0.14, 0.06, 0.65)
const COLOR_ACCENT: Color         = Color(0.44, 0.36, 0.14, 1.0)

var _immortal_id: StringName = &""
var _tree: Dictionary = {}

var _dimmer: ColorRect
var _sheet: PanelContainer
var _body_margin: MarginContainer
var _body_vbox: VBoxContainer


func configure(immortal_id: StringName, tree: Dictionary) -> void:
	_immortal_id = immortal_id
	_tree = tree


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	_build_dimmer()
	_build_sheet()
	_render_prompt()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, Prefs.anim_duration(0.18))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()


func close() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, Prefs.anim_duration(0.15))
	tw.tween_callback(func() -> void:
		closed.emit()
		queue_free())


# --- Chrome ----------------------------------------------------------------

func _build_dimmer() -> void:
	_dimmer = ColorRect.new()
	_dimmer.color = COLOR_DIMMER
	_dimmer.anchor_right = 1.0
	_dimmer.anchor_bottom = 1.0
	_dimmer.mouse_filter = MOUSE_FILTER_STOP
	add_child(_dimmer)


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
	_sheet.offset_left = -340.0
	_sheet.offset_right = 340.0
	_sheet.offset_top = -260.0
	_sheet.offset_bottom = 260.0
	_sheet.mouse_filter = MOUSE_FILTER_STOP
	add_child(_sheet)

	_body_margin = MarginContainer.new()
	_body_margin.add_theme_constant_override("margin_left", 32)
	_body_margin.add_theme_constant_override("margin_right", 32)
	_body_margin.add_theme_constant_override("margin_top", 24)
	_body_margin.add_theme_constant_override("margin_bottom", 24)
	_sheet.add_child(_body_margin)

	_body_vbox = VBoxContainer.new()
	_body_vbox.add_theme_constant_override("separation", 12)
	_body_margin.add_child(_body_vbox)


# --- Render ----------------------------------------------------------------

func _clear_body() -> void:
	for c in _body_vbox.get_children():
		c.queue_free()


func _render_prompt() -> void:
	_clear_body()

	var im: OtherImmortal = Immortals.get_by_id(_immortal_id)
	var title_text: String = "A private letter"
	if im != null:
		title_text = "A letter from %s" % im.epithet
	_body_vbox.add_child(_make_title(title_text))

	var prompt: String = String(_tree.get("prompt", ""))
	var body: Label = Label.new()
	body.text = prompt
	body.add_theme_color_override("font_color", COLOR_INK)
	body.add_theme_font_size_override("font_size", 13)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_vbox.add_child(body)

	var choices_heading: Label = Label.new()
	choices_heading.text = "YOUR REPLY"
	choices_heading.add_theme_color_override("font_color", COLOR_INK_MUTED)
	choices_heading.add_theme_font_size_override("font_size", 11)
	_body_vbox.add_child(choices_heading)

	var branches: Variant = _tree.get("branches", [])
	if not branches is Array:
		return
	for b in branches:
		if not b is Dictionary:
			continue
		_body_vbox.add_child(_make_branch_button(b))


func _render_result(result_text: String, branch_label: String) -> void:
	_clear_body()

	var im: OtherImmortal = Immortals.get_by_id(_immortal_id)
	var title_text: String = "What came of it"
	if im != null:
		title_text = "With %s — what came of it" % im.epithet
	_body_vbox.add_child(_make_title(title_text))

	var chose: Label = Label.new()
	chose.text = "You chose: %s" % branch_label
	chose.add_theme_color_override("font_color", COLOR_INK_MUTED)
	chose.add_theme_font_size_override("font_size", 12)
	chose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_vbox.add_child(chose)

	var body: Label = Label.new()
	body.text = result_text
	body.add_theme_color_override("font_color", COLOR_INK)
	body.add_theme_font_size_override("font_size", 13)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_vbox.add_child(body)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_END
	var btn: Button = Button.new()
	btn.text = "Close"
	btn.flat = true
	btn.add_theme_color_override("font_color", COLOR_ACCENT)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(close)
	hbox.add_child(btn)
	_body_vbox.add_child(hbox)


# --- Branch selection ------------------------------------------------------

func _make_branch_button(b: Dictionary) -> Control:
	var btn: Button = Button.new()
	btn.text = String(b.get("label", "..."))
	btn.flat = false
	btn.add_theme_color_override("font_color", COLOR_INK)
	btn.add_theme_font_size_override("font_size", 13)
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func() -> void: _on_branch_chosen(b))
	return btn


func _on_branch_chosen(b: Dictionary) -> void:
	var branch_id: String = String(b.get("id", ""))
	var branch_label: String = String(b.get("label", ""))
	var result: String = Immortals.resolve_dialogue_choice(_immortal_id, branch_id)
	if result == "":
		result = String(b.get("result", ""))
	_render_result(result, branch_label)


# --- Visual helpers --------------------------------------------------------

func _make_title(text: String) -> Control:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_INK)
	l.add_theme_font_size_override("font_size", 20)
	return l
