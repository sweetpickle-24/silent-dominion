extends Control
## Full-screen overlay for browsing and reading character dossiers.
##
## Two modes in the same scene:
##   - LIST:   every known actor as a scrollable roster, grouped nothing,
##             filterable by kingdom via a dropdown at the top.
##   - DETAIL: a single actor's dossier in period voice — role, kingdom,
##             age, and a qualitative §24 trait read-out. No numbers.
##
## Built entirely in code so the scene is self-contained and matches the
## parchment/ink table aesthetic without needing yet another .tscn file.
##
## Emits `closed` when dismissed. The table instantiates, displays, awaits.

signal closed

enum Mode { LIST, DETAIL }

# --- Visual tokens -----------------------------------------------------------

const COLOR_DIMMER: Color         = Color(0, 0, 0, 0.62)
const COLOR_PARCHMENT: Color      = Color(0.96, 0.92, 0.82, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.55, 0.42, 0.28, 0.7)
const COLOR_INK: Color            = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.22, 0.14, 0.06, 0.65)
const COLOR_ROW_HOVER: Color      = Color(0.88, 0.82, 0.68, 1.0)

const ALL_KINGDOMS_KEY: String = "__all__"

# --- Nodes -------------------------------------------------------------------

var _mode: Mode = Mode.LIST
var _dimmer: ColorRect
var _sheet: PanelContainer
var _body_margin: MarginContainer
var _body_vbox: VBoxContainer
var _kingdom_filter: OptionButton
var _current_kingdom_filter: String = ALL_KINGDOMS_KEY


# --- Lifecycle ---------------------------------------------------------------

var _pending_initial_actor: Actor = null


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	_build_dimmer()
	_build_sheet()

	if _pending_initial_actor != null:
		_show_detail(_pending_initial_actor)
		_pending_initial_actor = null
	else:
		_render_list()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)


## Public: open the view directly on a specific actor's dossier. Safe to
## call before or after the view has entered the tree.
func show_actor(actor: Actor) -> void:
	if actor == null:
		return
	if _body_vbox == null:
		_pending_initial_actor = actor
		return
	_show_detail(actor)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _mode == Mode.DETAIL:
				_show_list()
			else:
				close()
			get_viewport().set_input_as_handled()


# --- Public ------------------------------------------------------------------

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
		if _mode == Mode.DETAIL:
			_show_list()
		else:
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
	_sheet.offset_left = -360.0
	_sheet.offset_right = 360.0
	_sheet.offset_top = -280.0
	_sheet.offset_bottom = 280.0
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


# --- List mode ---------------------------------------------------------------

func _show_list() -> void:
	_mode = Mode.LIST
	_render_list()


func _render_list() -> void:
	_clear_body()

	_body_vbox.add_child(_make_title("Dossiers"))
	_body_vbox.add_child(_make_subtitle("Every name on this table, and the shape the world ascribes to them."))

	var filter_bar: HBoxContainer = HBoxContainer.new()
	filter_bar.add_theme_constant_override("separation", 8)
	filter_bar.custom_minimum_size.y = 28.0
	_body_vbox.add_child(filter_bar)

	var filter_label: Label = Label.new()
	filter_label.text = "Filter by kingdom:"
	filter_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
	filter_label.add_theme_font_size_override("font_size", 12)
	filter_bar.add_child(filter_label)

	_kingdom_filter = OptionButton.new()
	_kingdom_filter.add_theme_font_size_override("font_size", 12)
	_kingdom_filter.add_item("All kingdoms")
	_kingdom_filter.set_item_metadata(0, ALL_KINGDOMS_KEY)
	var kingdoms: Array = _unique_kingdom_ids()
	kingdoms.sort()
	for kid in kingdoms:
		var k: Kingdom = WorldData.get_kingdom(kid)
		var label: String = (k.kingdom_name if k != null else String(kid))
		var idx: int = _kingdom_filter.item_count
		_kingdom_filter.add_item(label)
		_kingdom_filter.set_item_metadata(idx, String(kid))
	_kingdom_filter.item_selected.connect(_on_kingdom_filter_changed)
	# Restore previously-selected filter across list re-renders.
	for i in range(_kingdom_filter.item_count):
		if String(_kingdom_filter.get_item_metadata(i)) == _current_kingdom_filter:
			_kingdom_filter.select(i)
			break
	filter_bar.add_child(_kingdom_filter)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 380.0
	_body_vbox.add_child(scroll)

	var roster: VBoxContainer = VBoxContainer.new()
	roster.add_theme_constant_override("separation", 0)
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(roster)

	var entries: Array[Actor] = _filtered_actors()
	if entries.is_empty():
		var empty: Label = Label.new()
		empty.text = "No names on file."
		empty.add_theme_color_override("font_color", COLOR_INK_MUTED)
		empty.add_theme_font_size_override("font_size", 13)
		roster.add_child(empty)
	else:
		for a in entries:
			roster.add_child(_build_list_row(a))

	_body_vbox.add_child(_make_close_button(func() -> void: close()))


func _on_kingdom_filter_changed(idx: int) -> void:
	_current_kingdom_filter = String(_kingdom_filter.get_item_metadata(idx))
	# Defer the re-render so the OptionButton isn't freed while still
	# in the middle of dispatching its own `item_selected` signal.
	call_deferred("_render_list")


func _filtered_actors() -> Array[Actor]:
	var all: Array[Actor] = Actors.all_actors()
	var filtered: Array[Actor] = []
	for a in all:
		if not a.is_alive():
			continue
		if _current_kingdom_filter != ALL_KINGDOMS_KEY \
				and a.kingdom_id != _current_kingdom_filter:
			continue
		filtered.append(a)
	filtered.sort_custom(func(x, y):
		if x.kingdom_id == y.kingdom_id:
			return x.given_name < y.given_name
		return x.kingdom_id < y.kingdom_id)
	return filtered


func _unique_kingdom_ids() -> Array:
	var s: Dictionary = {}
	for a in Actors.all_actors():
		if a.kingdom_id != "":
			s[a.kingdom_id] = true
	return s.keys()


func _build_list_row(actor: Actor) -> Control:
	var row: Button = Button.new()
	row.text = ""
	row.flat = true
	row.custom_minimum_size.y = 42.0
	row.focus_mode = Control.FOCUS_NONE
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hover_sb: StyleBoxFlat = StyleBoxFlat.new()
	hover_sb.bg_color = COLOR_ROW_HOVER
	hover_sb.corner_radius_top_left = 3
	hover_sb.corner_radius_top_right = 3
	hover_sb.corner_radius_bottom_left = 3
	hover_sb.corner_radius_bottom_right = 3
	row.add_theme_stylebox_override("hover", hover_sb)
	row.add_theme_stylebox_override("pressed", hover_sb)

	# Row layout: name on the left, role + kingdom on the right.
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	hbox.offset_left = 10
	hbox.offset_right = -10
	hbox.offset_top = 6
	hbox.offset_bottom = -6
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(hbox)

	var name_label: Label = Label.new()
	name_label.text = actor.display_name()
	name_label.add_theme_color_override("font_color", COLOR_INK)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)

	var meta: Label = Label.new()
	var k: Kingdom = WorldData.get_kingdom(actor.kingdom_id)
	var kingdom_name: String = k.kingdom_name if k != null else actor.kingdom_id
	meta.text = "%s — %s" % [TraitCues.role_title(actor.role), kingdom_name]
	meta.add_theme_color_override("font_color", COLOR_INK_MUTED)
	meta.add_theme_font_size_override("font_size", 12)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(meta)

	# Only surface relationship when it's left neutral territory. Prevents
	# the roster from shouting "INDIFFERENT" at every unmet face.
	if actor.relationship >= 11 or actor.relationship <= -11:
		var rel: Label = Label.new()
		rel.text = _relationship_tag(actor.relationship)
		rel.add_theme_color_override("font_color", _relationship_color(actor.relationship))
		rel.add_theme_font_size_override("font_size", 10)
		rel.custom_minimum_size.x = 90.0
		rel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(rel)

	if actor.is_host():
		var host_tag: Label = Label.new()
		host_tag.text = "HOST"
		host_tag.add_theme_color_override("font_color", Color(0.18, 0.34, 0.22, 1.0))
		host_tag.add_theme_font_size_override("font_size", 10)
		host_tag.custom_minimum_size.x = 48.0
		host_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(host_tag)

	row.pressed.connect(func() -> void: _show_detail(actor))
	return row


func _relationship_tag(v: int) -> String:
	var band: StringName = TraitCues.relationship_band(v)
	match band:
		&"hostile":  return "HOSTILE"
		&"wary":     return "WARY"
		&"polite":   return "POLITE"
		&"warming":  return "WARMING"
		&"loyal":    return "LOYAL"
		_: return ""


func _relationship_color(v: int) -> Color:
	if v <= -31: return Color(0.55, 0.08, 0.08, 1.0)    # wine
	if v <= -11: return Color(0.62, 0.30, 0.12, 1.0)    # muted rust
	if v >=  61: return Color(0.18, 0.34, 0.22, 1.0)    # forest green
	if v >=  11: return Color(0.40, 0.36, 0.14, 1.0)    # mustard
	return COLOR_INK_MUTED


# --- Detail mode -------------------------------------------------------------

func _show_detail(actor: Actor) -> void:
	_mode = Mode.DETAIL
	_clear_body()

	# Header: back + name
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_body_vbox.add_child(header)

	var back: Button = Button.new()
	back.text = "‹ Back to roster"
	back.flat = true
	back.add_theme_color_override("font_color", COLOR_INK_MUTED)
	back.add_theme_font_size_override("font_size", 12)
	back.pressed.connect(func() -> void: _show_list())
	header.add_child(back)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_body_vbox.add_child(_make_title(actor.display_name()))

	var k: Kingdom = WorldData.get_kingdom(actor.kingdom_id)
	var p: Province = WorldData.get_province(actor.province_id)
	var subtitle_parts: Array[String] = []
	subtitle_parts.append(TraitCues.role_title(actor.role))
	if k != null:
		subtitle_parts.append(k.kingdom_name)
	elif actor.kingdom_id != "":
		subtitle_parts.append(actor.kingdom_id)
	if p != null:
		subtitle_parts.append("of %s" % p.province_name)
	_body_vbox.add_child(_make_subtitle(" — ".join(subtitle_parts)))

	# Age line
	var age: int = actor.age_in(GameClock.year)
	var birth_bce: int = -actor.birth_year
	var age_line: Label = _make_body_line(
		"Born %d BCE — some %d winters old at this hand." % [birth_bce, max(0, age)]
	)
	_body_vbox.add_child(age_line)

	_body_vbox.add_child(_make_divider())

	_body_vbox.add_child(_make_section_heading("WHAT IS SAID OF THEM"))

	var phrases: Array[String] = TraitCues.notable_phrases(actor)
	if phrases.is_empty():
		var plain: Label = _make_body_line(
			"Nothing remarkable. The shape your agents describe is the shape of any ordinary person in their station."
		)
		_body_vbox.add_child(plain)
	else:
		for phrase in phrases:
			var bullet: Label = _make_body_line("•  %s." % phrase)
			_body_vbox.add_child(bullet)

	_body_vbox.add_child(_make_divider())

	_body_vbox.add_child(_make_section_heading("THEIR STANCE TOWARD YOU"))
	_body_vbox.add_child(_make_body_line(
		"They %s." % TraitCues.relationship_phrase(actor.relationship)
	))
	if actor.is_host():
		var host_line: Label = _make_body_line(
			"They will act on your behalf, if you ask it carefully. They are a host."
		)
		host_line.add_theme_color_override("font_color", Color(0.18, 0.34, 0.22, 1.0))
		_body_vbox.add_child(host_line)

	_body_vbox.add_child(_make_divider())

	_body_vbox.add_child(_make_section_heading("ON FILE"))
	_body_vbox.add_child(_make_body_line(
		"Identifier: %s    Role: %s    Kingdom: %s" % [
			String(actor.id),
			TraitCues.role_title(actor.role),
			(k.kingdom_name if k != null else actor.kingdom_id),
		]
	))

	_body_vbox.add_child(_make_close_button(func() -> void: close()))


# --- Widget factories --------------------------------------------------------

func _clear_body() -> void:
	for child in _body_vbox.get_children():
		child.queue_free()


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
	return l


func _make_section_heading(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	l.add_theme_font_size_override("font_size", 11)
	return l


func _make_body_line(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_INK)
	l.add_theme_font_size_override("font_size", 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _make_divider() -> HSeparator:
	var s: HSeparator = HSeparator.new()
	s.add_theme_color_override("color", COLOR_PARCHMENT_EDGE)
	return s


func _make_close_button(on_press: Callable) -> Button:
	var b: Button = Button.new()
	b.text = "Set aside"
	b.custom_minimum_size.y = 34.0
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", COLOR_INK)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(on_press)
	return b
