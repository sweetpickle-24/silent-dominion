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
signal actor_link_clicked(actor_id: StringName)
signal codebook_link_clicked(anchor: StringName)
## Emitted when the player clicks a direct action button on a dossier.
## `table.gd` opens Compose with the action preset and target locked
## to the dossier's actor, so issuing is one more click.
signal compose_action_requested(action_id: StringName, actor_id: StringName)

const LetterViewScene: PackedScene = preload("res://scenes/inbox/letter_view.tscn")

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
# §D1 live text search combined with the kingdom filter as AND.
var _search_input: LineEdit
var _current_search: String = ""

## A child LetterView spawned when the player clicks a linked letter
## from the detail page. While it's set we suppress dossier close on
## dimmer clicks and escape so the dossier stays underneath.
var _child_letter_view: Control


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
	create_tween().tween_property(self, "modulate:a", 1.0, Prefs.anim_duration(0.18))

	if EraTheme != null:
		EraTheme.register_view(self)


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
			if _child_letter_view != null:
				return   # the letter view handles its own ESC
			if _mode == Mode.DETAIL:
				_show_list()
			else:
				close()
			get_viewport().set_input_as_handled()


# --- Public ------------------------------------------------------------------

func close() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, Prefs.anim_duration(0.15))
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
		if _child_letter_view != null:
			return   # don't fall through the open letter
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

	# §F4 — "This side of the table": the player's own cover identities.
	_render_identities_section()

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

	# §D1 live text search, AND-combined with the kingdom filter.
	var search_label: Label = Label.new()
	search_label.text = "Search:"
	search_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
	search_label.add_theme_font_size_override("font_size", 12)
	filter_bar.add_child(search_label)

	_search_input = LineEdit.new()
	_search_input.placeholder_text = "by name"
	_search_input.add_theme_font_size_override("font_size", 12)
	_search_input.custom_minimum_size.x = 160.0
	_search_input.text = _current_search
	_search_input.text_changed.connect(_on_search_text_changed)
	filter_bar.add_child(_search_input)

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
		var current_kingdom: String = "__none__"
		for a in entries:
			if a.kingdom_id != current_kingdom:
				current_kingdom = a.kingdom_id
				roster.add_child(_build_kingdom_heading(current_kingdom))
			roster.add_child(_build_list_row(a))

	_body_vbox.add_child(_make_close_button(func() -> void: close()))


func _on_kingdom_filter_changed(idx: int) -> void:
	_current_kingdom_filter = String(_kingdom_filter.get_item_metadata(idx))
	# Defer the re-render so the OptionButton isn't freed while still
	# in the middle of dispatching its own `item_selected` signal.
	call_deferred("_render_list")


func _on_search_text_changed(new_text: String) -> void:
	_current_search = new_text
	call_deferred("_render_list")


func _filtered_actors() -> Array[Actor]:
	# §E1 — roster is gated by Picture. If the player has no picture of
	# a kingdom, its people don't exist in the dossier.
	var all: Array[Actor] = Picture.known_actors() if Picture != null else Actors.all_actors()
	var filtered: Array[Actor] = []
	var needle: String = _current_search.strip_edges().to_lower()
	for a in all:
		if not a.is_alive():
			continue
		if _current_kingdom_filter != ALL_KINGDOMS_KEY \
				and a.kingdom_id != _current_kingdom_filter:
			continue
		if needle != "" and not a.display_name().to_lower().contains(needle):
			continue
		filtered.append(a)
	filtered.sort_custom(func(x, y):
		if x.kingdom_id == y.kingdom_id:
			return x.given_name < y.given_name
		return x.kingdom_id < y.kingdom_id)
	return filtered


func _unique_kingdom_ids() -> Array:
	var s: Dictionary = {}
	var pool: Array[Actor] = Picture.known_actors() if Picture != null else Actors.all_actors()
	for a in pool:
		if a.kingdom_id != "":
			s[a.kingdom_id] = true
	return s.keys()


func _build_kingdom_heading(kingdom_id: String) -> Control:
	var k: Kingdom = WorldData.get_kingdom(kingdom_id)
	var k_name: String = k.kingdom_name if k != null else kingdom_id
	var box: MarginContainer = MarginContainer.new()
	box.add_theme_constant_override("margin_top", 10)
	box.add_theme_constant_override("margin_bottom", 2)
	box.add_theme_constant_override("margin_left", 4)
	var h: Label = Label.new()
	h.text = k_name.to_upper()
	h.add_theme_color_override("font_color", Color(0.44, 0.36, 0.14, 1.0))
	h.add_theme_font_size_override("font_size", 11)
	box.add_child(h)
	return box


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
	meta.text = TraitCues.role_title(actor.role)
	meta.add_theme_color_override("font_color", COLOR_INK_MUTED)
	meta.add_theme_font_size_override("font_size", 12)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta.custom_minimum_size.x = 110.0
	hbox.add_child(meta)

	var trait_strip: Control = _build_trait_strip(actor)
	if trait_strip != null:
		hbox.add_child(trait_strip)

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


func _build_trait_strip(actor: Actor) -> Control:
	var keys: Array[StringName] = TraitCues.notable_trait_keys(actor, 3)
	if keys.is_empty():
		return null
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)
	hb.custom_minimum_size.x = 66.0
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in keys:
		var value: int = actor.get_trait(k)
		hb.add_child(_build_trait_chip(k, value))
	return hb


func _build_trait_chip(key: StringName, value: int) -> Control:
	var chip: PanelContainer = PanelContainer.new()
	var is_high: bool = value > 70
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	if is_high:
		sb.bg_color = Color(0.44, 0.36, 0.14, 1.0)   # ink-mustard
	else:
		sb.bg_color = Color(0.55, 0.42, 0.28, 0.55)  # dust
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", sb)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.tooltip_text = "%s: %s" % [
		String(key).capitalize(),
		("notably high" if is_high else "notably low"),
	]

	var l: Label = Label.new()
	l.text = TraitCues.trait_glyph(key)
	l.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82, 1.0))
	l.add_theme_font_size_override("font_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(l)
	return chip


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
	# Actor.birth_year uses GameClock's negative-BCE / positive-CE
	# convention. Label flips once we're past year 1.
	var by: int = actor.birth_year
	var born_phrase: String = ""
	if by < 0:
		born_phrase = "%d BCE" % -by
	elif by == 0:
		born_phrase = "1 BCE"
	else:
		born_phrase = "%d CE" % by
	var age_line: Label = _make_body_line(
		"Born %s — some %d winters old at this hand." % [born_phrase, max(0, age)]
	)
	_body_vbox.add_child(age_line)

	# Confidence / freshness band (§7.6 two-reality). The dossier is
	# the clearest moment to remind the player they are reading a
	# picture, not the world. Only surfaced when it actually matters —
	# current, well-covered regions stay quiet.
	if actor.kingdom_id != "" and Picture != null:
		var state: StringName = Picture.state_for(actor.kingdom_id)
		if state != &"current":
			var phrase: String = Picture.freshness_phrase(actor.kingdom_id)
			var color: Color = COLOR_INK_MUTED
			var prefix: String = "Our picture of this name is "
			match state:
				&"aging":
					color = Color(0.52, 0.40, 0.18, 1.0)
					prefix = "Our picture of this name is aging — "
				&"stale":
					color = Color(0.62, 0.42, 0.14, 1.0)
					prefix = "This picture is stale — "
				&"cold":
					color = Color(0.62, 0.18, 0.12, 1.0)
					prefix = "No current intelligence here — "
			var freshness_line: Label = _make_body_line(prefix + phrase + ".")
			freshness_line.add_theme_color_override("font_color", color)
			_body_vbox.add_child(freshness_line)

	# Hunter warning (§10.5). If this actor is actively hunting the
	# shadow figure, we flag it prominently. This reads above the
	# normal "what is said of them" list because the dossier itself
	# is now a dangerous object — if they ever got this file, they
	# would have us.
	if Shadow != null and Shadow.is_hunter(String(actor.id)):
		var hunter_line: Label = _make_body_line(
			"This name is on our own hunter list. They are building a file on "
			+ "the shadow figure and have stopped asking the ordinary questions."
		)
		hunter_line.add_theme_color_override("font_color", Color(0.62, 0.18, 0.12, 1.0))
		_body_vbox.add_child(hunter_line)

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

	_build_contextual_actions_section(actor)

	_maybe_build_languages_section(actor)

	_maybe_build_dynasty_section(actor)

	_maybe_build_org_section(actor)

	_maybe_build_mandate_section(actor)

	_body_vbox.add_child(_make_section_heading("WHAT THE LETTERS SAY"))
	var linked: Array[Letter] = _letters_mentioning(actor)
	_build_cross_reference_panel(linked)

	_body_vbox.add_child(_make_section_heading("LETTERS ON THIS NAME"))
	if linked.is_empty():
		_body_vbox.add_child(_make_body_line(
			"No letter on the table yet names them. The world has not written them down."
		))
	else:
		var letters_box: VBoxContainer = VBoxContainer.new()
		letters_box.add_theme_constant_override("separation", 2)
		_body_vbox.add_child(letters_box)
		var shown: int = 0
		for l in linked:
			letters_box.add_child(_build_letter_row(l))
			shown += 1
			if shown >= 12:
				break
		if linked.size() > shown:
			var more: Label = _make_body_line(
				"  …and %d earlier letter%s in the Memoirs." % [
					linked.size() - shown,
					"" if linked.size() - shown == 1 else "s",
				]
			)
			more.add_theme_color_override("font_color", COLOR_INK_MUTED)
			letters_box.add_child(more)

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


# --- Organisation section ---------------------------------------------------
#
# Surfaces the player's two org-facing verbs against this dossier:
#   - "Raise as coordinator" if the actor is a loyal host and not yet
#     in the cell. Issues `promote_coordinator`.
#   - "Elevate to lieutenant" if the actor is already a seasoned,
#     trusted coordinator. Issues `promote_lieutenant`.
# If the actor is already in the org, shows their current posting
# instead. If they're a ruler, shows nothing — rulers are not tools.

func _maybe_build_dynasty_section(actor: Actor) -> void:
	var f: Family = Dynasties.family_of(actor)

	# If no family is tracked yet, offer to found one on host-tier
	# non-ruler actors so the player can explicitly adopt a dynasty.
	if f == null:
		if not actor.is_alive():
			return
		if actor.role == Actor.Role.RULER:
			return
		if actor.relationship < 40:
			return
		_body_vbox.add_child(_make_section_heading("THEIR HOUSE"))
		_body_vbox.add_child(_make_body_line(
			"They are the first of their line to deal with you. You could begin tracking the family itself — if you mean to serve with them across generations."
		))
		var found_btn: Button = Button.new()
		found_btn.text = "Begin tracking this house"
		found_btn.flat = false
		found_btn.focus_mode = Control.FOCUS_NONE
		found_btn.custom_minimum_size.y = 30.0
		var actor_ref: Actor = actor
		found_btn.pressed.connect(func() -> void:
			var domain: int = _domain_guess(actor_ref)
			Dynasties.found_family(actor_ref.id, domain)
			_show_detail(actor_ref))
		_body_vbox.add_child(found_btn)
		_body_vbox.add_child(_make_divider())
		return

	_body_vbox.add_child(_make_section_heading("THEIR HOUSE"))

	var head_label: String = ""
	if f.head_id == actor.id:
		head_label = "They are the head of %s — %s, %s." % [
			f.family_name, f.generation_phrase(), f.culture_phrase()
		]
	else:
		var head: Actor = Actors.get_actor(f.head_id)
		var head_name: String = head.display_name() if head != null else "the current head"
		head_label = "They belong to %s. The head is %s — %s, %s." % [
			f.family_name, head_name, f.generation_phrase(), f.culture_phrase()
		]
	_body_vbox.add_child(_make_body_line(head_label))

	if f.decline_score >= 55:
		var warn: Label = _make_body_line(
			"The line is tired. Quiet scandals and thin heirs. They will not carry another generation without care."
		)
		warn.add_theme_color_override("font_color", Color(0.58, 0.22, 0.12, 1.0))
		_body_vbox.add_child(warn)

	if f.has_open_need():
		var need_line: Label = _make_body_line(
			"They have written: %s. They are waiting to see whether you answer." % f.need_label()
		)
		need_line.add_theme_color_override("font_color", Color(0.58, 0.22, 0.12, 1.0))
		_body_vbox.add_child(need_line)

		var need_row: HBoxContainer = HBoxContainer.new()
		need_row.add_theme_constant_override("separation", 8)
		_body_vbox.add_child(need_row)

		var protect_btn: Button = Button.new()
		protect_btn.text = "Stand with them"
		protect_btn.focus_mode = Control.FOCUS_NONE
		protect_btn.custom_minimum_size.y = 28.0
		var fid_p: StringName = f.id
		protect_btn.pressed.connect(func() -> void:
			Dynasties.note_crisis_response(fid_p, true)
			_show_detail(actor))
		need_row.add_child(protect_btn)

		var ignore_btn: Button = Button.new()
		ignore_btn.text = "Let them manage"
		ignore_btn.focus_mode = Control.FOCUS_NONE
		ignore_btn.custom_minimum_size.y = 28.0
		var fid_i: StringName = f.id
		ignore_btn.pressed.connect(func() -> void:
			Dynasties.note_crisis_response(fid_i, false)
			_show_detail(actor))
		need_row.add_child(ignore_btn)

	var invest_btn: Button = Button.new()
	invest_btn.text = "Invest in the next generation"
	invest_btn.flat = false
	invest_btn.focus_mode = Control.FOCUS_NONE
	invest_btn.custom_minimum_size.y = 28.0
	var fid: StringName = f.id
	invest_btn.pressed.connect(func() -> void:
		Dynasties.invest_in_children(fid)
		_show_detail(actor))
	_body_vbox.add_child(invest_btn)

	_body_vbox.add_child(_make_divider())


func _domain_guess(actor: Actor) -> int:
	match actor.role:
		Actor.Role.MERCHANT:    return int(Family.Domain.MERCHANT)
		Actor.Role.GENERAL:     return int(Family.Domain.MILITARY)
		Actor.Role.PRIEST:      return int(Family.Domain.RELIGIOUS)
		Actor.Role.PHILOSOPHER: return int(Family.Domain.SCHOLARLY)
		Actor.Role.ADVISOR:     return int(Family.Domain.COURT)
		_:                      return int(Family.Domain.GENERIC)


## Direct contextual actions: one button per ACTOR-targeting action
## the player can currently issue against this dossier's subject.
## Disabled buttons carry a tooltip explaining the block (exposure,
## purse, no host). A final "More…" button opens the full Compose UI
## pre-filtered to the dossier's kingdom/province, for rarer targets.
func _build_contextual_actions_section(actor: Actor) -> void:
	if actor == null or Actions == null:
		return
	var defs: Array[ActionDefinition] = Actions.all_definitions()
	# Order: tier ascending (shadow-first), then display name.
	defs.sort_custom(func(a: ActionDefinition, b: ActionDefinition) -> bool:
		if int(a.tier) == int(b.tier):
			return a.display_name < b.display_name
		return int(a.tier) < int(b.tier))
	var relevant: Array[ActionDefinition] = []
	for def in defs:
		if def == null:
			continue
		if def.target_kind != ActionDefinition.TargetKind.ACTOR:
			continue
		relevant.append(def)
	if relevant.is_empty():
		return
	_body_vbox.add_child(_make_section_heading("WHAT YOU CAN SEND AGAINST THEM"))
	var grid: VBoxContainer = VBoxContainer.new()
	grid.add_theme_constant_override("separation", 4)
	_body_vbox.add_child(grid)
	var shown: int = 0
	for def in relevant:
		var btn: Button = _build_action_button_against(actor, def)
		if btn == null:
			continue
		grid.add_child(btn)
		shown += 1
		# Keep the list from eating the dossier — roll the tail into a
		# single "see all" button that opens Compose.
		if shown >= 6:
			break
	var more_btn: Button = Button.new()
	more_btn.text = "More instruments…"
	more_btn.custom_minimum_size.y = 28.0
	more_btn.focus_mode = Control.FOCUS_NONE
	more_btn.add_theme_color_override("font_color", COLOR_INK_MUTED)
	more_btn.add_theme_font_size_override("font_size", 12)
	more_btn.pressed.connect(func() -> void:
		compose_action_requested.emit(StringName(""), actor.id))
	grid.add_child(more_btn)
	_body_vbox.add_child(_make_divider())


## Build a single action button targeting `actor` with `def`. Returns
## null for actions the player should not even see (e.g. hidden by
## discovery). Disabled with tooltip for actions that are visible but
## blocked.
func _build_action_button_against(actor: Actor, def: ActionDefinition) -> Button:
	var btn: Button = Button.new()
	var costs: String = ""
	if def.silver_cost > 0:
		costs = "  (%d silver)" % def.silver_cost
	btn.text = "%s%s" % [def.display_name, costs]
	btn.tooltip_text = def.blurb
	btn.custom_minimum_size.y = 28.0
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_color_override("font_color", COLOR_INK)
	btn.add_theme_font_size_override("font_size", 12)

	var reason: String = _action_block_reason(actor, def)
	if reason != "":
		btn.disabled = true
		btn.tooltip_text = reason
	else:
		btn.disabled = false

	btn.pressed.connect(func() -> void:
		compose_action_requested.emit(def.id, actor.id))
	return btn


## Return the player-facing reason the action is blocked, or "" if it
## can fire. Mirrors the gating logic in ComposeView's card builder so
## the two stay in sync.
func _action_block_reason(actor: Actor, def: ActionDefinition) -> String:
	if def == null or actor == null:
		return "This action cannot be composed right now."
	if Exposure != null and not Exposure.allows_tier(def.tier):
		return CrashGuard.safe_str(Exposure.block_reason(def.tier), "Exposure too high for this tier.")
	if def.silver_cost > 0 and Purse != null and not Purse.can_afford(def.silver_cost):
		return "The purse will not cover this."
	if def.requires_host_target and not actor.is_host():
		return "They are not loyal enough to act on your behalf yet."
	if not actor.is_alive():
		return "They are beyond reach of any letter."
	return ""


func _maybe_build_languages_section(actor: Actor) -> void:
	if actor.languages.is_empty():
		return

	_body_vbox.add_child(_make_section_heading("TONGUES THEY SPEAK"))

	var lines: Array[String] = []
	var native_line: String = ""
	var other_lines: Array[String] = []
	for lang_id_v in actor.known_languages():
		var lang_id: StringName = lang_id_v
		var level: int = actor.language_level(lang_id)
		if level <= Actor.LANG_NONE:
			continue
		var label: String = Languages.display_name(lang_id)
		var phrase: String = ""
		match level:
			Actor.LANG_BASIC:
				phrase = "a few words of %s" % label
			Actor.LANG_FUNCTIONAL:
				phrase = "workable %s" % label
			Actor.LANG_FLUENT:
				phrase = "fluent %s" % label
			_:
				phrase = label
		if String(lang_id) == String(Languages.native_of(actor.kingdom_id)):
			native_line = "Their mother tongue is %s." % label
		else:
			other_lines.append(phrase)

	if native_line != "":
		lines.append(native_line)
	if not other_lines.is_empty():
		lines.append("Beyond that, they have %s." % _join_and(other_lines))

	if lines.is_empty():
		_body_vbox.add_child(_make_body_line(
			"They speak only their own people's tongue."
		))
	else:
		for l in lines:
			_body_vbox.add_child(_make_body_line(l))

	_body_vbox.add_child(_make_divider())


func _join_and(items: Array) -> String:
	if items.is_empty():
		return ""
	if items.size() == 1:
		return String(items[0])
	if items.size() == 2:
		return "%s and %s" % [items[0], items[1]]
	var head: Array = items.slice(0, items.size() - 1)
	return "%s, and %s" % [", ".join(head), items[items.size() - 1]]


func _maybe_build_org_section(actor: Actor) -> void:
	if actor.role == Actor.Role.RULER:
		return

	_body_vbox.add_child(_make_section_heading("ORGANISATION"))

	var existing: OrgMember = Org.member_for_actor(actor.id)
	if existing != null:
		var role_phrase: String = "%s in %s" % [
			existing.layer_name(),
			_kingdom_name_of(existing.region_id),
		]
		var status_line: Label
		if existing.burned:
			status_line = _make_body_line(
				"Formerly your %s. Burned — no longer reachable through our work." % role_phrase
			)
			status_line.add_theme_color_override("font_color", Color(0.62, 0.18, 0.12, 1.0))
		else:
			status_line = _make_body_line(
				"They are your %s. Their cover: %s." % [role_phrase, existing.cover]
			)
			status_line.add_theme_color_override("font_color", Color(0.18, 0.34, 0.22, 1.0))
		_body_vbox.add_child(status_line)

		# Lieutenant elevation — shown only if the member meets the
		# thresholds. Don't taunt the player with a disabled button;
		# say plainly why it isn't offered.
		if not existing.burned \
				and existing.layer == OrgMember.Layer.COORDINATOR:
			if existing.trust >= 70 and existing.tenure_days >= 365:
				_body_vbox.add_child(_make_promote_lieutenant_button(actor))
			else:
				_body_vbox.add_child(_make_body_line(
					"They are not yet seasoned or trusted enough to raise further."
				))
		_body_vbox.add_child(_make_divider())
		return

	# Not in the org yet. Only loyal hosts can be promoted to coordinator.
	if actor.is_host():
		_body_vbox.add_child(_make_body_line(
			"A trusted host. They could be raised into the work as your coordinator in "
			+ _kingdom_name_of(actor.kingdom_id)
			+ " — a conversation that cannot be taken back."
		))
		_body_vbox.add_child(_make_promote_coordinator_button(actor))
	else:
		_body_vbox.add_child(_make_body_line(
			"Not yet loyal enough to be asked for more. Keep cultivating."
		))
	_body_vbox.add_child(_make_divider())


func _make_promote_coordinator_button(actor: Actor) -> Button:
	var def: ActionDefinition = Actions.get_definition(&"promote_coordinator")
	var cost_hint: String = ""
	if def != null:
		cost_hint = "  (%d silver · HIGH exposure)" % def.silver_cost
	var b: Button = Button.new()
	b.text = "Raise %s as coordinator%s" % [actor.display_name(), cost_hint]
	b.custom_minimum_size.y = 34.0
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", COLOR_INK)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(func() -> void:
		var handle: int = Actions.issue(&"promote_coordinator", String(actor.id))
		if handle == Scheduler.INVALID_HANDLE:
			return
		close())
	return b


func _make_promote_lieutenant_button(actor: Actor) -> Button:
	var def: ActionDefinition = Actions.get_definition(&"promote_lieutenant")
	var cost_hint: String = ""
	if def != null:
		cost_hint = "  (%d silver · HIGH exposure)" % def.silver_cost
	var b: Button = Button.new()
	b.text = "Elevate %s to lieutenant%s" % [actor.display_name(), cost_hint]
	b.custom_minimum_size.y = 34.0
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", COLOR_INK)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(func() -> void:
		var handle: int = Actions.issue(&"promote_lieutenant", String(actor.id))
		if handle == Scheduler.INVALID_HANDLE:
			return
		close())
	return b


func _kingdom_name_of(kid: String) -> String:
	var k: Kingdom = WorldData.get_kingdom(kid)
	return k.kingdom_name if k != null else kid


# --- Mandates section -------------------------------------------------------
#
# Shows active removal-mandate progress against this actor, if any.
# For rulers with no active mandate, offers a "Mark for removal"
# button. For non-rulers this section stays silent — removal mandates
# are only offered against figures holding a crown.

func _maybe_build_mandate_section(actor: Actor) -> void:
	if not actor.is_alive():
		return
	var active: Mandate = _active_removal_for(actor.id)
	if active == null and actor.role != Actor.Role.RULER:
		return

	_body_vbox.add_child(_make_section_heading("MANDATES"))

	if active != null:
		var phase: Dictionary = active.active_phase()
		_body_vbox.add_child(_make_body_line(
			"Under mandate: %s." % active.headline.to_lower()
		))
		if not phase.is_empty():
			_body_vbox.add_child(_make_body_line(
				"Current phase — %s (%d of %d). %s" % [
					String(phase.get("name", "")),
					int(phase.get("progress", 0)),
					int(phase.get("target", 1)),
					String(phase.get("description", "")),
				]
			))
		return

	var btn: Button = Button.new()
	btn.text = "Declare a removal mandate"
	btn.flat = false
	btn.add_theme_font_size_override("font_size", 12)
	btn.custom_minimum_size.y = 28.0
	btn.pressed.connect(func() -> void: _on_declare_removal(actor))
	_body_vbox.add_child(btn)


func _on_declare_removal(actor: Actor) -> void:
	var mid: StringName = Mandates.offer_removal_mandate(actor.id, false)
	if mid != &"":
		_show_detail(actor)   # refresh so the section now shows progress


func _active_removal_for(actor_id: StringName) -> Mandate:
	for m in Mandates.all_mandates():
		if (
			m.category == Mandate.Category.REMOVAL
			and m.target_actor_id == actor_id
			and m.status == Mandate.Status.ACTIVE
		):
			return m
	return null


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


# --- Linked letters ----------------------------------------------------------
#
# Scans the inbox for every letter that mentions this actor and returns
# them sorted newest-first. A letter "mentions" the actor if its BBCode
# body carries a `[url=actor:<id>]` anchor, or if the sender display
# name matches the actor's (covers host-authored letters where the
# actor is the voice, not a reference).

func _letters_mentioning(actor: Actor) -> Array[Letter]:
	var out: Array[Letter] = []
	# Fast path: the actor-index maintained by Inbox.
	if Inbox.has_method("letters_about"):
		var indexed: Array[Letter] = Inbox.call("letters_about", actor.id) as Array[Letter]
		for l in indexed:
			out.append(l)
	# Fall-back scan: also catch letters where the actor is the *sender*
	# (host-authored correspondence) or where the body links them with
	# plain text rather than BBCode (legacy). De-dup by identity.
	var seen: Dictionary = {}
	for l in out:
		seen[l] = true
	var display: String = actor.display_name()
	var id_token: String = "actor:%s" % String(actor.id)
	for l in Inbox.letters:
		if seen.has(l):
			continue
		if l.sender == display or l.body.find(id_token) >= 0:
			out.append(l)
			seen[l] = true
	out.sort_custom(_sort_letters_newest_first)
	return out


func _sort_letters_newest_first(a: Letter, b: Letter) -> bool:
	# GameDate.year is stored positive for BCE; smaller year = later in time.
	var ay: int = a.date.year if a.date != null else 0
	var by: int = b.date.year if b.date != null else 0
	if ay != by:
		return ay < by
	var am: int = a.date.month if a.date != null else 0
	var bm: int = b.date.month if b.date != null else 0
	if am != bm:
		return am > bm
	var ad: int = a.date.day if a.date != null else 0
	var bd: int = b.date.day if b.date != null else 0
	return ad > bd


## Three most recent letters about this actor as stacked "report cards".
## Each card shows the reporter, the subject line, and a confidence pill.
## When at least two cards carry confidence bands and their gap is wide
## (≥ 30 points) OR they come from different reporters, a small
## "Sources disagree" chip is surfaced on the panel — the player's cue to
## reach for cross_reference_pattern / intel_reinvestigate.
func _build_cross_reference_panel(all_linked: Array[Letter]) -> void:
	if all_linked.is_empty():
		return

	var band_letters: Array[Letter] = []
	for l in all_linked:
		if l != null and l.has_confidence_band():
			band_letters.append(l)

	if band_letters.is_empty():
		_body_vbox.add_child(_make_body_line(
			"No banded reports yet. Nothing on the table carries a source we have measured against itself."
		))
		return

	# Header row with optional contradiction chip.
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_body_vbox.add_child(header)

	var caption: Label = Label.new()
	caption.text = "Latest %d report%s on this name" % [
		min(3, band_letters.size()),
		"" if band_letters.size() == 1 else "s",
	]
	caption.add_theme_color_override("font_color", COLOR_INK_MUTED)
	caption.add_theme_font_size_override("font_size", 11)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(caption)

	var top3: Array[Letter] = []
	for i in range(min(3, band_letters.size())):
		top3.append(band_letters[i])

	if _crossref_has_contradiction(top3):
		header.add_child(_build_contradiction_chip())

	for l in top3:
		_body_vbox.add_child(_build_cross_ref_card(l))


func _crossref_has_contradiction(top3: Array[Letter]) -> bool:
	if top3.size() < 2:
		return false
	var min_c: int = 1000
	var max_c: int = -1
	var reporters: Dictionary = {}
	for l in top3:
		min_c = mini(min_c, l.confidence)
		max_c = maxi(max_c, l.confidence)
		if l.reporter_id != &"":
			reporters[l.reporter_id] = true
	if max_c - min_c >= 30:
		return true
	if reporters.size() >= 2 and max_c - min_c >= 15:
		return true
	return false


func _build_contradiction_chip() -> Control:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.62, 0.18, 0.12, 0.28)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.62, 0.18, 0.12, 0.85)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	var lbl: Label = Label.new()
	lbl.text = "SOURCES DISAGREE"
	lbl.add_theme_color_override("font_color", Color(0.32, 0.08, 0.04, 1.0))
	lbl.add_theme_font_size_override("font_size", 10)
	p.add_child(lbl)
	return p


func _build_cross_ref_card(letter: Letter) -> Control:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.92, 0.87, 0.72, 0.60)
	sb.border_width_left = 2
	sb.border_color = _confidence_accent(letter)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)

	var row1: HBoxContainer = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	vb.add_child(row1)

	var date_l: Label = Label.new()
	date_l.text = _format_letter_short_date(letter.date)
	date_l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	date_l.add_theme_font_size_override("font_size", 11)
	date_l.custom_minimum_size.x = 90.0
	row1.add_child(date_l)

	var sender_l: Label = Label.new()
	var reporter_name: String = letter.sender
	if letter.reporter_id != &"":
		var m: OrgMember = Org.get_member(letter.reporter_id)
		if m != null:
			reporter_name = m.display_name
	sender_l.text = reporter_name
	sender_l.add_theme_color_override("font_color", COLOR_INK)
	sender_l.add_theme_font_size_override("font_size", 12)
	sender_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sender_l.clip_text = true
	row1.add_child(sender_l)

	row1.add_child(_build_confidence_pill(letter))

	var subject_l: Label = Label.new()
	subject_l.text = letter.subject
	subject_l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	subject_l.add_theme_font_size_override("font_size", 11)
	subject_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(subject_l)

	# Clicking a card opens the letter — same contract as the
	# existing letters-list rows.
	panel.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_open_linked_letter(letter))

	return panel


func _confidence_accent(letter: Letter) -> Color:
	match letter.confidence_tier():
		&"high":   return Color(0.24, 0.44, 0.20, 0.85)
		&"medium": return Color(0.58, 0.44, 0.18, 0.85)
		&"low":    return Color(0.62, 0.18, 0.12, 0.85)
	return Color(0.30, 0.22, 0.12, 0.6)


func _build_confidence_pill(letter: Letter) -> Control:
	var accent: Color = _confidence_accent(letter)
	var bg: Color = accent
	bg.a = 0.28
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = accent
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	var lbl: Label = Label.new()
	lbl.text = "%s %d" % [String(letter.confidence_tier()).to_upper(), letter.confidence]
	lbl.add_theme_color_override("font_color", accent)
	lbl.add_theme_font_size_override("font_size", 10)
	p.add_child(lbl)
	return p


func _build_letter_row(letter: Letter) -> Control:
	var btn: Button = Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size.y = 32.0
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hover_sb: StyleBoxFlat = StyleBoxFlat.new()
	hover_sb.bg_color = COLOR_ROW_HOVER
	hover_sb.corner_radius_top_left = 3
	hover_sb.corner_radius_top_right = 3
	hover_sb.corner_radius_bottom_left = 3
	hover_sb.corner_radius_bottom_right = 3
	hover_sb.content_margin_left = 10
	hover_sb.content_margin_right = 10
	hover_sb.content_margin_top = 4
	hover_sb.content_margin_bottom = 4
	var normal_sb: StyleBoxFlat = hover_sb.duplicate()
	normal_sb.bg_color = Color(0, 0, 0, 0)
	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)

	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hb)

	# Kind-colored pip
	var pip: Panel = Panel.new()
	pip.custom_minimum_size = Vector2(6, 6)
	var pip_sb: StyleBoxFlat = StyleBoxFlat.new()
	var pip_color: Color = LetterKind.color_for(letter.kind)
	if letter.is_read:
		pip_color.a = 0.4
	pip_sb.bg_color = pip_color
	pip_sb.corner_radius_top_left = 4
	pip_sb.corner_radius_top_right = 4
	pip_sb.corner_radius_bottom_left = 4
	pip_sb.corner_radius_bottom_right = 4
	pip.add_theme_stylebox_override("panel", pip_sb)
	var pip_wrap: CenterContainer = CenterContainer.new()
	pip_wrap.custom_minimum_size.x = 8.0
	pip_wrap.add_child(pip)
	hb.add_child(pip_wrap)

	var date_l: Label = Label.new()
	date_l.text = _format_letter_short_date(letter.date)
	date_l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	date_l.add_theme_font_size_override("font_size", 11)
	date_l.custom_minimum_size.x = 100.0
	hb.add_child(date_l)

	var subject_l: Label = Label.new()
	subject_l.text = letter.subject
	subject_l.add_theme_color_override(
		"font_color", COLOR_INK if not letter.is_read else COLOR_INK_MUTED
	)
	subject_l.add_theme_font_size_override("font_size", 12)
	subject_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subject_l.clip_text = true
	hb.add_child(subject_l)

	btn.pressed.connect(func() -> void: _open_linked_letter(letter))
	return btn


func _format_letter_short_date(d: GameDate) -> String:
	if d == null:
		return ""
	const NAMES: Array[String] = [
		"Ian", "Feb", "Mar", "Apr", "Mai", "Iun",
		"Qui", "Sex", "Sep", "Oct", "Nov", "Dec",
	]
	var idx: int = clampi(d.month, 1, 12) - 1
	return "%d %s %d" % [d.day, NAMES[idx], d.year]


func _open_linked_letter(letter: Letter) -> void:
	if _child_letter_view != null:
		return
	var view: Control = LetterViewScene.instantiate()
	view.anchor_right = 1.0
	view.anchor_bottom = 1.0
	add_child(view)
	view.closed.connect(_on_child_letter_closed)
	view.actor_link_clicked.connect(_on_child_actor_link)
	view.codebook_link_clicked.connect(_on_child_codebook_link)
	view.call("display", letter)
	_child_letter_view = view


func _on_child_letter_closed() -> void:
	_child_letter_view = null


func _on_child_actor_link(actor_id: StringName) -> void:
	# Another actor is named in this letter — close down and bubble up
	# so the table can swap the dossier cleanly onto the new name.
	actor_link_clicked.emit(actor_id)
	_child_letter_view = null
	close()


func _on_child_codebook_link(anchor: StringName) -> void:
	codebook_link_clicked.emit(anchor)
	_child_letter_view = null
	close()


# --- §F4 Cover identities: "THIS SIDE OF THE TABLE" --------------------------

func _render_identities_section() -> void:
	if Identities == null:
		return
	var active: Array[CoverIdentity] = Identities.active_identities()
	if active.is_empty():
		return

	var section: VBoxContainer = VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_vbox.add_child(section)

	var header: Label = Label.new()
	header.text = "THIS SIDE OF THE TABLE"
	header.add_theme_color_override("font_color", COLOR_INK)
	header.add_theme_font_size_override("font_size", 12)
	section.add_child(header)

	var blurb: Label = Label.new()
	blurb.text = "The faces you wear. Every action you route through one of these names writes a little more legend under it — and a little more risk."
	blurb.add_theme_color_override("font_color", COLOR_INK_MUTED)
	blurb.add_theme_font_size_override("font_size", 11)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(blurb)

	for ident in active:
		section.add_child(_build_identity_card(ident))

	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("color", COLOR_PARCHMENT_EDGE)
	section.add_child(sep)


func _build_identity_card(ident: CoverIdentity) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.94, 0.90, 0.78, 1.0)
	sb.border_color = COLOR_PARCHMENT_EDGE
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	var title: Label = Label.new()
	title.text = ident.display_title()
	title.add_theme_color_override("font_color", COLOR_INK)
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	var meta_parts: Array[String] = []
	meta_parts.append("apparently %d years old" % ident.apparent_age)
	if not ident.home_region_id.is_empty():
		var k: Kingdom = WorldData.get_kingdom(ident.home_region_id) if WorldData != null else null
		meta_parts.append("of %s" % (k.kingdom_name if k != null else ident.home_region_id.capitalize()))
	meta_parts.append(ident.legend_band_phrase())
	var meta: Label = Label.new()
	meta.text = " · ".join(meta_parts)
	meta.add_theme_color_override("font_color", COLOR_INK_MUTED)
	meta.add_theme_font_size_override("font_size", 11)
	vbox.add_child(meta)

	if not ident.note.is_empty():
		var note: Label = Label.new()
		note.text = ident.note
		note.add_theme_color_override("font_color", COLOR_INK_MUTED)
		note.add_theme_font_size_override("font_size", 11)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(note)

	var anchors: Array[String] = []
	for aid in ident.anchor_actor_ids:
		var aname: String = ""
		if Actors != null:
			var a: Actor = Actors.get_actor(aid)
			if a != null:
				aname = a.display_name()
		if aname.is_empty() and Org != null:
			var m: OrgMember = Org.get_member(aid)
			if m != null:
				aname = m.display_name
		if not aname.is_empty():
			anchors.append(aname)
	if not anchors.is_empty():
		var anchor_l: Label = Label.new()
		anchor_l.text = "Carried into rooms by: %s." % ", ".join(anchors)
		anchor_l.add_theme_color_override("font_color", COLOR_INK_MUTED)
		anchor_l.add_theme_font_size_override("font_size", 11)
		anchor_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(anchor_l)

	return card
