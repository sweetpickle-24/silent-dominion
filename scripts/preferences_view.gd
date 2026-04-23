extends Control
## Full-screen overlay for user preferences (§10.4 / §10.6 / §10.8 /
## §10.9). Deliberately terse: this isn't a Settings app, it's the
## half-dozen toggles a player actually touches.

signal closed

const COLOR_DIMMER: Color         = Color(0, 0, 0, 0.62)
const COLOR_PARCHMENT: Color      = Color(0.96, 0.92, 0.82, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.55, 0.42, 0.28, 0.7)
const COLOR_INK: Color            = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.22, 0.14, 0.06, 0.65)


var _dimmer: ColorRect
var _sheet: PanelContainer
var _body_vbox: VBoxContainer


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP
	_build_dimmer()
	_build_sheet()
	_build_rows()
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


# --- Chrome ---------------------------------------------------------------

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
	_sheet.anchor_left = 0.5
	_sheet.anchor_top = 0.5
	_sheet.anchor_right = 0.5
	_sheet.anchor_bottom = 0.5
	_sheet.custom_minimum_size = Vector2(560, 620)
	_sheet.pivot_offset = Vector2(280, 310)
	_sheet.offset_left = -280
	_sheet.offset_top = -310
	_sheet.offset_right = 280
	_sheet.offset_bottom = 310

	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = COLOR_PARCHMENT
	sb.border_color = COLOR_PARCHMENT_EDGE
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 18
	sb.corner_radius_top_right = 18
	sb.corner_radius_bottom_left = 18
	sb.corner_radius_bottom_right = 18
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	_sheet.add_theme_stylebox_override("panel", sb)
	add_child(_sheet)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sheet.add_child(scroll)

	_body_vbox = VBoxContainer.new()
	_body_vbox.add_theme_constant_override("separation", 14)
	_body_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body_vbox)


# --- Rows ------------------------------------------------------------------

func _build_rows() -> void:
	_body_vbox.add_child(_make_title("Preferences"))
	_body_vbox.add_child(_make_hr())

	_body_vbox.add_child(_make_section("Time"))
	_body_vbox.add_child(_make_checkbox(
		"Pause when urgent letters arrive",
		Prefs.auto_pause_on_priority,
		func(on: bool) -> void: Prefs.set_auto_pause(on),
	))

	_body_vbox.add_child(_make_section("Saving"))
	_body_vbox.add_child(_make_checkbox(
		"Continuous autosave (rotating A / B slots)",
		Prefs.continuous_autosave,
		func(on: bool) -> void: Prefs.set_continuous_autosave(on),
	))
	_body_vbox.add_child(_make_spin_row(
		"Autosave every N days",
		Prefs.autosave_interval_days,
		1, 360, 5,
		func(value: int) -> void: Prefs.set_autosave_interval(value),
	))
	_body_vbox.add_child(_make_checkbox(
		"Ironman (no manual saves, no reload-to-undo)",
		Prefs.ironman,
		func(on: bool) -> void: Prefs.set_ironman(on),
	))

	_body_vbox.add_child(_make_section("Accessibility"))
	_body_vbox.add_child(_make_checkbox(
		"Reduced motion",
		Prefs.reduced_motion,
		func(on: bool) -> void: Prefs.set_reduced_motion(on),
	))
	_body_vbox.add_child(_make_spin_row(
		"UI font scale (75-175%)",
		int(round(Prefs.ui_font_scale * 100.0)),
		75, 175, 5,
		func(value: int) -> void: Prefs.set_ui_font_scale(float(value) / 100.0),
	))
	# §10.9 colour-blind palette selector.
	_body_vbox.add_child(_make_dropdown_row(
		"Colour-blind palette",
		["off", "deuteranopia", "protanopia", "tritanopia"],
		String(Prefs.colorblind_mode),
		func(value: String) -> void: Prefs.set_colorblind_mode(StringName(value)),
	))
	_body_vbox.add_child(_make_checkbox(
		"Stronger focus ring (keyboard)",
		Prefs.focus_ring_strong,
		func(on: bool) -> void: Prefs.set_focus_ring_strong(on),
	))

	# §10.10 audio.
	_body_vbox.add_child(_make_section("Audio"))
	_body_vbox.add_child(_make_checkbox(
		"Event sounds",
		Prefs.sfx_enabled,
		func(on: bool) -> void: Prefs.set_sfx_enabled(on),
	))
	_body_vbox.add_child(_make_spin_row(
		"Event volume (0-100%)",
		int(round(Prefs.sfx_volume * 100.0)),
		0, 100, 5,
		func(value: int) -> void: Prefs.set_sfx_volume(float(value) / 100.0),
	))
	_body_vbox.add_child(_make_checkbox(
		"Ambient loop",
		Prefs.ambient_enabled,
		func(on: bool) -> void: Prefs.set_ambient_enabled(on),
	))
	_body_vbox.add_child(_make_spin_row(
		"Ambient volume (0-100%)",
		int(round(Prefs.ambient_volume * 100.0)),
		0, 100, 5,
		func(value: int) -> void: Prefs.set_ambient_volume(float(value) / 100.0),
	))
	_body_vbox.add_child(_make_checkbox(
		"Music",
		Prefs.music_enabled,
		func(on: bool) -> void: Prefs.set_music_enabled(on),
	))
	_body_vbox.add_child(_make_spin_row(
		"Music volume (0-100%)",
		int(round(Prefs.music_volume * 100.0)),
		0, 100, 5,
		func(value: int) -> void: Prefs.set_music_volume(float(value) / 100.0),
	))

	# §10.6 extra hardship.
	_body_vbox.add_child(_make_section("Extra hardship"))
	_body_vbox.add_child(_make_checkbox(
		"Aggressive rivals (twice the pressure)",
		Prefs.aggressive_rivals,
		func(on: bool) -> void: Prefs.set_aggressive_rivals(on),
	))
	_body_vbox.add_child(_make_checkbox(
		"Lean starting resources",
		Prefs.lean_start,
		func(on: bool) -> void: Prefs.set_lean_start(on),
	))
	_body_vbox.add_child(_make_checkbox(
		"Hostile hosts (higher resistance floor)",
		Prefs.hostile_hosts,
		func(on: bool) -> void: Prefs.set_hostile_hosts(on),
	))
	_body_vbox.add_child(_make_checkbox(
		"Fast hunters (earlier shadow tier thresholds)",
		Prefs.fast_hunters,
		func(on: bool) -> void: Prefs.set_fast_hunters(on),
	))
	_body_vbox.add_child(_make_checkbox(
		"Brittle cover (+25% decay per action)",
		Prefs.brittle_cover,
		func(on: bool) -> void: Prefs.set_brittle_cover(on),
	))

	# §10.8 cross-run persistence.
	_body_vbox.add_child(_make_section("World persistence"))
	_body_vbox.add_child(_make_checkbox(
		"Carry past lives forward (legacy entities, rumours)",
		Prefs.world_persistence_enabled,
		func(on: bool) -> void: Prefs.set_world_persistence_enabled(on),
	))

	_body_vbox.add_child(_make_hr())
	var close_btn: Button = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(close)
	_body_vbox.add_child(close_btn)


# --- Widgets ---------------------------------------------------------------

func _make_title(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_INK)
	l.add_theme_font_size_override("font_size", 22)
	return l


func _make_section(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	l.add_theme_font_size_override("font_size", 11)
	return l


func _make_hr() -> Control:
	var r: ColorRect = ColorRect.new()
	r.color = COLOR_PARCHMENT_EDGE
	r.custom_minimum_size = Vector2(0, 1)
	return r


func _make_checkbox(label: String, initial: bool, on_toggle: Callable) -> CheckBox:
	var cb: CheckBox = CheckBox.new()
	cb.text = label
	cb.button_pressed = initial
	cb.add_theme_color_override("font_color", COLOR_INK)
	cb.toggled.connect(func(pressed: bool) -> void: on_toggle.call(pressed))
	return cb


func _make_dropdown_row(label: String, options: Array, initial: String, on_change: Callable) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l: Label = Label.new()
	l.text = label
	l.add_theme_color_override("font_color", COLOR_INK)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var opt: OptionButton = OptionButton.new()
	opt.custom_minimum_size.x = 160
	for i in range(options.size()):
		opt.add_item(String(options[i]))
		opt.set_item_metadata(i, String(options[i]))
		if String(options[i]) == initial:
			opt.select(i)
	opt.item_selected.connect(func(idx: int) -> void:
		on_change.call(String(opt.get_item_metadata(idx))))
	h.add_child(opt)
	return h


func _make_spin_row(label: String, initial: int, vmin: int, vmax: int, step: int, on_change: Callable) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l: Label = Label.new()
	l.text = label
	l.add_theme_color_override("font_color", COLOR_INK)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var sb: SpinBox = SpinBox.new()
	sb.min_value = vmin
	sb.max_value = vmax
	sb.step = step
	sb.value = initial
	sb.custom_minimum_size.x = 100
	sb.value_changed.connect(func(value: float) -> void: on_change.call(int(value)))
	h.add_child(sb)
	return h
