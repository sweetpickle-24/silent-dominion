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
	var birth_bce: int = -actor.birth_year
	var age_line: Label = _make_body_line(
		"Born %d BCE — some %d winters old at this hand." % [birth_bce, max(0, age)]
	)
	_body_vbox.add_child(age_line)

	# Confidence / freshness band (§7.6 two-reality). The dossier is
	# the clearest moment to remind the player they are reading a
	# picture, not the world. Only surfaced when it actually matters —
	# current, well-covered regions stay quiet.
	if actor.kingdom_id != "":
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
	if Shadow.is_hunter(String(actor.id)):
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

	_maybe_build_org_section(actor)

	_maybe_build_mandate_section(actor)

	_body_vbox.add_child(_make_section_heading("LETTERS ON THIS NAME"))
	var linked: Array[Letter] = _letters_mentioning(actor)
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
	if actor.dead:
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
	var id_token: String = "actor:%s" % String(actor.id)
	var display: String = actor.display_name()
	var out: Array[Letter] = []
	for l in Inbox.letters:
		if l.body.find(id_token) >= 0 or l.sender == display:
			out.append(l)
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
