extends Control
## Full-screen overlay for the player's organisation: every Lieutenant,
## Coordinator, and named Operative they have cultivated.
##
## §14.1–§14.3: the roster shows the shape of the cell the player is
## building. Trust is the player's confidence in them. Skill is
## operational competence. Heat is their own exposure — when it climbs
## they get burned.
##
## Grouped by layer (Lieutenants → Coordinators → Operatives). Within a
## layer, grouped by kingdom for scan-ability. Empty layers collapse
## into a single muted line so the first-promotion state still reads.

signal closed

const COLOR_DIMMER: Color         = Color(0, 0, 0, 0.62)
const COLOR_PARCHMENT: Color      = Color(0.96, 0.92, 0.82, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.55, 0.42, 0.28, 0.7)
const COLOR_INK: Color            = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.22, 0.14, 0.06, 0.65)
const COLOR_ROW_HOVER: Color      = Color(0.88, 0.82, 0.68, 1.0)

const COLOR_TRUST: Color = Color(0.24, 0.42, 0.22, 1.0)
const COLOR_SKILL: Color = Color(0.32, 0.30, 0.52, 1.0)
const COLOR_HEAT:  Color = Color(0.62, 0.18, 0.12, 1.0)
const COLOR_BAR_BG: Color = Color(0.22, 0.14, 0.06, 0.18)

var _dimmer: ColorRect
var _sheet: PanelContainer
var _body_margin: MarginContainer
var _body_vbox: VBoxContainer


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	_build_dimmer()
	_build_sheet()
	_render()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)

	Org.roster_changed.connect(_on_roster_changed)
	Org.member_updated.connect(_on_member_updated)
	Org.member_burned.connect(_on_member_burned)


func _exit_tree() -> void:
	if Org.roster_changed.is_connected(_on_roster_changed):
		Org.roster_changed.disconnect(_on_roster_changed)
	if Org.member_updated.is_connected(_on_member_updated):
		Org.member_updated.disconnect(_on_member_updated)
	if Org.member_burned.is_connected(_on_member_burned):
		Org.member_burned.disconnect(_on_member_burned)


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
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
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
	_sheet.offset_left = -380.0
	_sheet.offset_right = 380.0
	_sheet.offset_top = -300.0
	_sheet.offset_bottom = 300.0
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


# --- Signals -----------------------------------------------------------------

func _on_roster_changed() -> void:
	call_deferred("_render")


func _on_member_updated(_m: OrgMember) -> void:
	call_deferred("_render")


func _on_member_burned(_m: OrgMember, _reason: StringName) -> void:
	call_deferred("_render")


# --- Render ------------------------------------------------------------------

func _render() -> void:
	_clear_body()

	_body_vbox.add_child(_make_title("Roster"))
	_body_vbox.add_child(_make_subtitle(_subtitle_text()))

	# Two-reality coverage band (§7.6 / §15.4). Lists known kingdoms
	# with their current fog state — gives the player one scannable
	# place to notice a region going cold. Hidden until we actually
	# have visibility data (first operative dropped their letter).
	if Picture.visibility.size() > 0:
		_render_coverage_band(_body_vbox)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 440.0
	_body_vbox.add_child(scroll)

	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var lieuts: Array[OrgMember] = Org.by_layer(OrgMember.Layer.LIEUTENANT)
	var coords: Array[OrgMember] = Org.by_layer(OrgMember.Layer.COORDINATOR)
	var ops:    Array[OrgMember] = Org.by_layer(OrgMember.Layer.OPERATIVE)

	if lieuts.is_empty() and coords.is_empty() and ops.is_empty():
		list.add_child(_make_empty_line("No hands yet. Every instruction is still yours to deliver."))
	else:
		_render_layer(list, "Lieutenants", lieuts,
			"Trusted with the shape of the work, if not its purpose.")
		_render_layer(list, "Coordinators", coords,
			"Each runs a cell. Their kingdom's work routes through them.")
		_render_layer(list, "Operatives", ops,
			"Hands for the coordinators. Kept in the dark, kept in the city.")

	_body_vbox.add_child(_make_close_button())


func _subtitle_text() -> String:
	var n: int = Org.size_active()
	if n == 0:
		return "Nothing on file yet. A single promotion begins the machine."
	var lieuts: int = Org.by_layer(OrgMember.Layer.LIEUTENANT).size()
	var coords: int = Org.by_layer(OrgMember.Layer.COORDINATOR).size()
	var ops:    int = Org.by_layer(OrgMember.Layer.OPERATIVE).size()
	return "Active: %d lieutenant%s · %d coordinator%s · %d operative%s" % [
		lieuts, ("" if lieuts == 1 else "s"),
		coords, ("" if coords == 1 else "s"),
		ops,    ("" if ops == 1 else "s"),
	]


func _render_coverage_band(parent: VBoxContainer) -> void:
	var heading: Label = Label.new()
	heading.text = "COVERAGE"
	heading.add_theme_color_override("font_color", COLOR_INK_MUTED)
	heading.add_theme_font_size_override("font_size", 11)
	parent.add_child(heading)

	var blurb: Label = Label.new()
	blurb.text = "What our network reports, and how old it is. Ground truth may differ."
	blurb.add_theme_color_override("font_color", COLOR_INK_MUTED)
	blurb.add_theme_font_size_override("font_size", 11)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(blurb)

	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	parent.add_child(list)

	# Sort by visibility desc so hottest coverage sits at the top.
	var kids: Array = []
	for kid in Picture.visibility.keys():
		kids.append(String(kid))
	kids.sort_custom(func(a, b):
		return Picture.score_for(a) > Picture.score_for(b))

	var shown: int = 0
	for kid in kids:
		if shown >= 8:
			break
		var score: int = Picture.score_for(kid)
		if score <= 0:
			continue
		shown += 1
		list.add_child(_build_coverage_row(kid, score))


func _build_coverage_row(kingdom_id: String, score: int) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var k: Kingdom = WorldData.get_kingdom(kingdom_id)
	var name: Label = Label.new()
	name.text = k.kingdom_name if k != null else kingdom_id
	name.add_theme_color_override("font_color", COLOR_INK)
	name.add_theme_font_size_override("font_size", 12)
	name.custom_minimum_size.x = 200.0
	row.add_child(name)

	var state: StringName = Picture.state_for(kingdom_id)
	var phrase: String = Picture.freshness_phrase(kingdom_id)
	var state_color: Color
	match state:
		&"current": state_color = Color(0.24, 0.42, 0.22, 1.0)
		&"aging":   state_color = Color(0.52, 0.40, 0.18, 1.0)
		&"stale":   state_color = Color(0.62, 0.42, 0.14, 1.0)
		_:          state_color = Color(0.62, 0.18, 0.12, 1.0)

	var bar: Control = _build_bar("Fog", score, state_color)
	bar.custom_minimum_size.x = 140.0
	row.add_child(bar)

	var phrase_label: Label = Label.new()
	phrase_label.text = phrase
	phrase_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
	phrase_label.add_theme_font_size_override("font_size", 11)
	row.add_child(phrase_label)

	# Shadow awareness suffix: only surfaces at institutional+. Reads
	# as a muted red tag so it doesn't compete with the fog-state
	# phrase but still flags "this region is getting loud".
	var aw_tier: int = Shadow.awareness_tier_in(kingdom_id)
	if aw_tier >= Shadow.TIER_INSTITUTIONAL:
		var aw_label: Label = Label.new()
		aw_label.text = "— drawing eyes" if aw_tier == Shadow.TIER_INSTITUTIONAL \
			else "— they speak of you here"
		aw_label.add_theme_color_override("font_color", Color(0.62, 0.18, 0.12, 1.0))
		aw_label.add_theme_font_size_override("font_size", 11)
		row.add_child(aw_label)

	return row


func _render_layer(parent: VBoxContainer, title: String,
		entries: Array[OrgMember], blurb: String) -> void:
	parent.add_child(_make_layer_heading(title, blurb))
	if entries.is_empty():
		var empty: Label = Label.new()
		empty.text = "   — none —"
		empty.add_theme_color_override("font_color", COLOR_INK_MUTED)
		empty.add_theme_font_size_override("font_size", 12)
		parent.add_child(empty)
		return

	entries.sort_custom(func(a: OrgMember, b: OrgMember) -> bool:
		if a.region_id == b.region_id:
			return a.display_name < b.display_name
		return a.region_id < b.region_id)

	var last_kingdom: String = "__none__"
	for m in entries:
		if m.region_id != last_kingdom:
			last_kingdom = m.region_id
			parent.add_child(_make_kingdom_heading(m.region_id))
		parent.add_child(_build_row(m))


func _build_row(m: OrgMember) -> Control:
	var row: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.95, 0.90, 0.76, 0.75)
	sb.border_color = Color(0.42, 0.28, 0.14, 0.4)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel", sb)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hbox)

	# Name + cover stack
	var id_box: VBoxContainer = VBoxContainer.new()
	id_box.add_theme_constant_override("separation", 1)
	id_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_box.custom_minimum_size.x = 220.0
	id_box.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_child(id_box)

	var name_label: Label = Label.new()
	name_label.text = m.display_name
	name_label.add_theme_color_override("font_color", COLOR_INK)
	name_label.add_theme_font_size_override("font_size", 14)
	id_box.add_child(name_label)

	var cover_label: Label = Label.new()
	cover_label.text = m.cover
	cover_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
	cover_label.add_theme_font_size_override("font_size", 11)
	cover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	id_box.add_child(cover_label)

	# Tenure
	var tenure: Label = Label.new()
	tenure.text = _tenure_phrase(m.tenure_days)
	tenure.add_theme_color_override("font_color", COLOR_INK_MUTED)
	tenure.add_theme_font_size_override("font_size", 11)
	tenure.custom_minimum_size.x = 90.0
	tenure.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(tenure)

	# Bars
	hbox.add_child(_build_bar("Trust", m.trust, COLOR_TRUST))
	hbox.add_child(_build_bar("Skill", m.skill, COLOR_SKILL))
	hbox.add_child(_build_bar("Heat",  m.heat,  COLOR_HEAT))

	# Strain badge (§14.1 span-of-control). Only surfaces above caps;
	# stays quiet for comfortable members so the row doesn't shout.
	var strain: StringName = Org.strain_label(m.id)
	if strain != &"comfortable":
		hbox.add_child(_build_strain_badge(strain))

	# §18-19 intelligence/corruption flags. Double agent is the loudest;
	# suspected is a yellow warning; drift fires after a long tenure
	# without audit. At most one of these shows — we pick the most
	# severe so the row stays readable.
	if m.double_agent:
		hbox.add_child(_build_status_badge(
			"DOUBLE",
			Color(0.35, 0.18, 0.48, 1.0),
			"Running as a controlled feeder back to the rival network. "
			+ "Monthly handler upkeep; all their reporting is our fiction."
		))
	elif m.suspected_compromised:
		hbox.add_child(_build_status_badge(
			"SUSPECT",
			Color(0.68, 0.46, 0.10, 1.0),
			"A cross-reference or audit has flagged them. Decide soon: "
			+ "cut, leverage, or run them as a double."
		))
	elif m.layer != OrgMember.Layer.OPERATIVE and m.months_since_audit >= 18:
		hbox.add_child(_build_status_badge(
			"DRIFT",
			Color(0.52, 0.40, 0.18, 1.0),
			"%d months since this cell was last audited. Long tenure "
			% m.months_since_audit
			+ "without oversight is the tenure that rots."
		))

	# Sever-cell action on coordinators (§14.2 rollback). Operatives
	# are dissolved automatically with their coordinator; lieutenants
	# are too deep to burn casually — their removal is future work.
	if m.layer == OrgMember.Layer.COORDINATOR:
		hbox.add_child(_build_sever_button(m))

	return row


func _build_status_badge(text: String, bg: Color, tooltip: String) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = MOUSE_FILTER_STOP
	panel.tooltip_text = tooltip

	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82, 1.0))
	l.add_theme_font_size_override("font_size", 9)
	panel.add_child(l)
	return panel


func _build_strain_badge(label: StringName) -> Control:
	var is_over: bool = label == &"over"
	var text: String = "OVER" if is_over else "STRAINED"
	var bg: Color = Color(0.62, 0.18, 0.12, 1.0) if is_over \
			else Color(0.62, 0.42, 0.14, 1.0)

	var panel: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.tooltip_text = (
		"Too many hands for one set of eyes. Their effective skill "
		+ "is docked and their heat creeps up each month until the "
		+ "load comes down."
	)

	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82, 1.0))
	l.add_theme_font_size_override("font_size", 9)
	panel.add_child(l)
	return panel


func _build_sever_button(m: OrgMember) -> Control:
	var b: Button = Button.new()
	b.text = "Sever"
	b.flat = false
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 10)
	b.custom_minimum_size = Vector2(58.0, 24.0)
	b.tooltip_text = (
		"Dissolve this cell. Operatives vanish, silver is absorbed, "
		+ "the player's heat ticks up a little. Used when the coordinator "
		+ "has drawn too much notice to keep running."
	)
	b.pressed.connect(func() -> void: Actions.sever_cell(m.id))
	return b


func _build_bar(label: String, value: int, color: Color) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.custom_minimum_size.x = 72.0
	box.mouse_filter = MOUSE_FILTER_IGNORE

	var cap: Label = Label.new()
	cap.text = "%s %d" % [label, value]
	cap.add_theme_color_override("font_color", COLOR_INK_MUTED)
	cap.add_theme_font_size_override("font_size", 10)
	box.add_child(cap)

	var track: PanelContainer = PanelContainer.new()
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = COLOR_BAR_BG
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	track.add_theme_stylebox_override("panel", bg)
	track.custom_minimum_size = Vector2(72.0, 6.0)
	box.add_child(track)

	var fill: ColorRect = ColorRect.new()
	fill.color = color
	fill.anchor_right = 0.0
	fill.custom_minimum_size = Vector2(0.01, 6.0)
	fill.mouse_filter = MOUSE_FILTER_IGNORE
	# Width in pixels proportional to value.
	var pct: float = clampf(float(value) / 100.0, 0.0, 1.0)
	fill.custom_minimum_size.x = maxf(1.0, 72.0 * pct)
	track.add_child(fill)

	return box


# --- Helpers -----------------------------------------------------------------

func _clear_body() -> void:
	for c in _body_vbox.get_children():
		c.queue_free()


func _make_title(txt: String) -> Label:
	var l: Label = Label.new()
	l.text = txt
	l.add_theme_color_override("font_color", COLOR_INK)
	l.add_theme_font_size_override("font_size", 22)
	return l


func _make_subtitle(txt: String) -> Label:
	var l: Label = Label.new()
	l.text = txt
	l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	l.add_theme_font_size_override("font_size", 12)
	return l


func _make_empty_line(txt: String) -> Label:
	var l: Label = Label.new()
	l.text = txt
	l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	l.add_theme_font_size_override("font_size", 13)
	return l


func _make_layer_heading(title: String, blurb: String) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 2)
	margin.add_child(box)

	var h: Label = Label.new()
	h.text = title.to_upper()
	h.add_theme_color_override("font_color", Color(0.44, 0.36, 0.14, 1.0))
	h.add_theme_font_size_override("font_size", 12)
	box.add_child(h)

	var sub: Label = Label.new()
	sub.text = blurb
	sub.add_theme_color_override("font_color", COLOR_INK_MUTED)
	sub.add_theme_font_size_override("font_size", 10)
	box.add_child(sub)

	return margin


func _make_kingdom_heading(kingdom_id: String) -> Control:
	var k: Kingdom = WorldData.get_kingdom(kingdom_id)
	var k_name: String = k.kingdom_name if k != null else kingdom_id
	var box: MarginContainer = MarginContainer.new()
	box.add_theme_constant_override("margin_top", 4)
	box.add_theme_constant_override("margin_bottom", 2)
	box.add_theme_constant_override("margin_left", 4)
	var h: Label = Label.new()
	h.text = "— " + k_name.to_upper()
	h.add_theme_color_override("font_color", Color(0.36, 0.28, 0.12, 0.9))
	h.add_theme_font_size_override("font_size", 10)
	box.add_child(h)
	return box


func _make_close_button() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	var b: Button = Button.new()
	b.text = "Close"
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(func() -> void: close())
	row.add_child(b)
	return row


func _tenure_phrase(days: int) -> String:
	if days < 30:
		return "new"
	if days < 90:
		return "weeks in"
	if days < 365:
		var months: int = int(days / 30.0)
		return "%d mo" % months
	var years: int = int(days / 365.0)
	return "%d yr" % maxi(1, years)
