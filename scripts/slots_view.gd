extends Control
## Full-screen overlay for the save/load 'Archive'.
##
## Surfaces three named slots plus the F5/F9 quicksave. Each row shows
## the slot's in-game date and system saved_at time when occupied, and
## offers Save / Load / Delete buttons. No thumbnails yet.
##
## Uses SaveManager for all filesystem work; this view is only chrome.

signal closed

const SLOT_IDS: Array[String] = ["quicksave", "slot_1", "slot_2", "slot_3"]
const SLOT_LABELS: Dictionary = {
	"quicksave": "Quicksave (F5 / F9)",
	"slot_1":    "First archive",
	"slot_2":    "Second archive",
	"slot_3":    "Third archive",
}

# --- Visual tokens -----------------------------------------------------------

const COLOR_DIMMER: Color         = Color(0, 0, 0, 0.62)
const COLOR_PARCHMENT: Color      = Color(0.96, 0.92, 0.82, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.55, 0.42, 0.28, 0.7)
const COLOR_INK: Color            = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.22, 0.14, 0.06, 0.65)
const COLOR_WAX: Color            = Color(0.55, 0.08, 0.08, 1.0)
const COLOR_ACCENT: Color         = Color(0.18, 0.34, 0.22, 1.0)

# --- Nodes -------------------------------------------------------------------

var _dimmer: ColorRect
var _sheet: PanelContainer
var _body_vbox: VBoxContainer


# --- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	_build_dimmer()
	_build_sheet()
	_render()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)


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
	_sheet.offset_left = -360.0
	_sheet.offset_right = 360.0
	_sheet.offset_top = -240.0
	_sheet.offset_bottom = 240.0
	_sheet.mouse_filter = MOUSE_FILTER_STOP
	add_child(_sheet)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_sheet.add_child(margin)

	_body_vbox = VBoxContainer.new()
	_body_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(_body_vbox)


# --- Render ------------------------------------------------------------------

func _render() -> void:
	for c in _body_vbox.get_children():
		c.queue_free()

	var title: Label = Label.new()
	title.text = "The Archive"
	title.add_theme_color_override("font_color", COLOR_INK)
	title.add_theme_font_size_override("font_size", 22)
	_body_vbox.add_child(title)

	var sub: Label = Label.new()
	sub.text = "A few copies of the table, folded and stored, so you can return to any season you like."
	sub.add_theme_color_override("font_color", COLOR_INK_MUTED)
	sub.add_theme_font_size_override("font_size", 12)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_vbox.add_child(sub)

	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("color", COLOR_PARCHMENT_EDGE)
	_body_vbox.add_child(sep)

	for slot in SLOT_IDS:
		_body_vbox.add_child(_build_slot_row(slot))

	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	_body_vbox.add_child(footer)

	var title_btn: Button = Button.new()
	title_btn.text = "Leave this table — back to the title"
	title_btn.flat = true
	title_btn.custom_minimum_size.y = 30.0
	title_btn.focus_mode = Control.FOCUS_NONE
	title_btn.add_theme_color_override("font_color", COLOR_INK_MUTED)
	title_btn.add_theme_font_size_override("font_size", 12)
	title_btn.pressed.connect(_on_return_to_title)
	footer.add_child(title_btn)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var close_btn: Button = Button.new()
	close_btn.text = "Set aside"
	close_btn.custom_minimum_size.y = 30.0
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_color_override("font_color", COLOR_INK)
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.pressed.connect(func() -> void: close())
	footer.add_child(close_btn)


func _build_slot_row(slot: String) -> Control:
	var info: Dictionary = SaveManager.slot_info(slot)
	var has_save: bool = not info.is_empty()

	var panel: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.94, 0.84, 1.0)
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
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	var text_col: VBoxContainer = VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	hbox.add_child(text_col)

	var label_l: Label = Label.new()
	label_l.text = String(SLOT_LABELS.get(slot, slot))
	label_l.add_theme_color_override("font_color", COLOR_INK)
	label_l.add_theme_font_size_override("font_size", 14)
	text_col.add_child(label_l)

	var meta: Label = Label.new()
	if has_save:
		var ingame: String = _format_ingame(info)
		var saved_at: String = String(info.get("saved_at", ""))
		meta.text = "%s   ·   saved %s" % [ingame, saved_at]
		meta.add_theme_color_override("font_color", COLOR_INK_MUTED)
	else:
		meta.text = "Empty fold. No season has been stored here."
		meta.add_theme_color_override("font_color", COLOR_INK_MUTED)
	meta.add_theme_font_size_override("font_size", 11)
	text_col.add_child(meta)

	# Action buttons
	var btn_save: Button = _small_button("Store", COLOR_INK)
	btn_save.pressed.connect(func() -> void: _on_save_pressed(slot))
	hbox.add_child(btn_save)

	var btn_load: Button = _small_button("Return to", COLOR_ACCENT)
	btn_load.disabled = not has_save
	btn_load.pressed.connect(func() -> void: _on_load_pressed(slot))
	hbox.add_child(btn_load)

	var btn_del: Button = _small_button("Discard", COLOR_WAX)
	btn_del.disabled = not has_save
	btn_del.pressed.connect(func() -> void: _on_delete_pressed(slot))
	hbox.add_child(btn_del)

	return panel


func _small_button(text: String, color: Color) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(90, 28)
	b.add_theme_color_override("font_color", color)
	b.add_theme_font_size_override("font_size", 11)
	return b


# --- Slot actions ------------------------------------------------------------

func _on_save_pressed(slot: String) -> void:
	SaveManager.save_to_slot(slot)
	_render()


func _on_load_pressed(slot: String) -> void:
	if not SaveManager.slot_exists(slot):
		return
	SaveManager.load_from_slot(slot)
	# Close the panel so the player sees the restored table.
	close()


func _on_delete_pressed(slot: String) -> void:
	SaveManager.delete_slot(slot)
	_render()


func _on_return_to_title() -> void:
	Session.pending_load_slot = ""
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func() -> void:
		get_tree().change_scene_to_file("res://scenes/title/title.tscn"))


# --- Formatting --------------------------------------------------------------

func _format_ingame(info: Dictionary) -> String:
	var abs_day: int = GameClock.absolute_day_of(
		int(info.get("year", 0)),
		int(info.get("month", 1)),
		int(info.get("day", 1))
	)
	return GameClock.format_absolute(abs_day)
