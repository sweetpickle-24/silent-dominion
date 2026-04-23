extends Control
## Full-screen overlay for the Ledger object on the table.
##
## Surfaces the qualitative state of every kingdom's treasury (§32.5).
## No raw numbers are shown — the player sees a condition band and a
## short sentence explaining what produced it, in period voice.
##
## Two modes:
##   LIST   — every kingdom as a row with its condition tag.
##   DETAIL — a single kingdom expanded to show its provinces, with
##            each province's share of the monthly income flagged as
##            "meagre / ordinary / handsome" (again — no numbers).
##
## Built entirely in code, same parchment palette as the rest of the
## table. Listens to KingdomEconomy.tick to redraw whenever the world
## moves forward.

signal closed
## Emitted when the player hits "Offer loan" on a kingdom row or in
## the detail view. `table.gd` handles the actual Purse.spend +
## Finance.open_iou call and posts a confirmation letter — the
## ledger itself stays a read-only surface for that mechanic.
signal offer_loan_requested(kingdom_id: String)
## Emitted when the player hits "Economic pressure" on a kingdom row
## or in the detail view. `table.gd` opens ComposeView pre-filtered
## to that kingdom with a regional kingdom-target action preselected.
signal economic_pressure_requested(kingdom_id: String)

enum Mode { LIST, DETAIL }

# --- Visual tokens -----------------------------------------------------------

const COLOR_DIMMER: Color         = Color(0, 0, 0, 0.62)
const COLOR_PARCHMENT: Color      = Color(0.96, 0.92, 0.82, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.55, 0.42, 0.28, 0.7)
const COLOR_INK: Color            = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.22, 0.14, 0.06, 0.65)
const COLOR_ROW_HOVER: Color      = Color(0.88, 0.82, 0.68, 1.0)

const CONDITION_TAGS: Dictionary = {
	Kingdom.TreasuryCondition.FLUSH:    "FLUSH",
	Kingdom.TreasuryCondition.STABLE:   "STABLE",
	Kingdom.TreasuryCondition.STRAINED: "STRAINED",
	Kingdom.TreasuryCondition.INDEBTED: "INDEBTED",
	Kingdom.TreasuryCondition.BROKE:    "BROKE",
}

const CONDITION_BLURBS: Dictionary = {
	Kingdom.TreasuryCondition.FLUSH:
		"The coffers are deep. Little leverage here — unless you choose to lend.",
	Kingdom.TreasuryCondition.STABLE:
		"Income and outlay balance. Shifts are possible, not immediate.",
	Kingdom.TreasuryCondition.STRAINED:
		"Outflow exceeds the crown's patience. An offer of silver now would be welcomed.",
	Kingdom.TreasuryCondition.INDEBTED:
		"The ruler leans on creditors. Whoever holds the paper holds the ruler.",
	Kingdom.TreasuryCondition.BROKE:
		"The seals will not hold. Armies grumble. Anything can be asked now.",
}

const CONDITION_COLORS: Dictionary = {
	Kingdom.TreasuryCondition.FLUSH:    Color(0.18, 0.34, 0.22, 1.0),
	Kingdom.TreasuryCondition.STABLE:   Color(0.40, 0.36, 0.14, 1.0),
	Kingdom.TreasuryCondition.STRAINED: Color(0.62, 0.45, 0.10, 1.0),
	Kingdom.TreasuryCondition.INDEBTED: Color(0.72, 0.28, 0.12, 1.0),
	Kingdom.TreasuryCondition.BROKE:    Color(0.55, 0.08, 0.08, 1.0),
}

# --- State / nodes -----------------------------------------------------------

var _mode: Mode = Mode.LIST
var _focus_kingdom_id: String = ""
var _dimmer: ColorRect
var _sheet: PanelContainer
var _body_margin: MarginContainer
var _body_vbox: VBoxContainer


# --- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	_build_dimmer()
	_build_sheet()
	_render_list()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, Prefs.anim_duration(0.18))

	KingdomEconomy.tick.connect(_on_economy_tick)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _mode == Mode.DETAIL:
				_render_list()
			else:
				close()
			get_viewport().set_input_as_handled()


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
		if _mode == Mode.DETAIL:
			_render_list()
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


func _clear_body() -> void:
	for child in _body_vbox.get_children():
		child.queue_free()


# --- List --------------------------------------------------------------------

func _render_list() -> void:
	_mode = Mode.LIST
	_focus_kingdom_id = ""
	_clear_body()

	_body_vbox.add_child(_make_title("The Ledger"))
	_body_vbox.add_child(_make_subtitle(
		"A season's measure of every crown's coffers. You will not see their figures — they do not trust them to anyone but their treasurer. But the shape of it is plain enough."
	))
	_body_vbox.add_child(_make_divider())

	_build_owned_entities_panel()

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 440.0
	_body_vbox.add_child(scroll)

	var roster: VBoxContainer = VBoxContainer.new()
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster.add_theme_constant_override("separation", 0)
	scroll.add_child(roster)

	var kingdoms: Array = WorldData.kingdoms.values()
	kingdoms.sort_custom(func(a, b):
		if int(a.treasury_condition) == int(b.treasury_condition):
			return a.kingdom_name < b.kingdom_name
		return int(a.treasury_condition) > int(b.treasury_condition))  # worse first
	for k in kingdoms:
		roster.add_child(_build_kingdom_row(k))

	_body_vbox.add_child(_make_close_button("Set aside", func() -> void: close()))


func _build_owned_entities_panel() -> void:
	var active: Array[OwnedEntity] = Entities.active_entities()
	if active.is_empty():
		return
	_body_vbox.add_child(_make_section_heading("OUR HOUSES AND WORKS"))
	for e in active:
		if e.control_disrupted:
			var warn: Label = _make_body_line("•  %s — %s in %s · control slipped · %s" % [
				e.display_name,
				e.kind_label().to_lower(),
				_kingdom_name(e.home_kingdom),
				e.memory_phrase(),
			])
			warn.add_theme_color_override("font_color", Color(0.58, 0.22, 0.12, 1.0))
			_body_vbox.add_child(warn)
			var reclaim_btn: Button = Button.new()
			reclaim_btn.text = "Seat a new proxy"
			reclaim_btn.focus_mode = Control.FOCUS_NONE
			reclaim_btn.custom_minimum_size.y = 26.0
			var eid: StringName = e.id
			reclaim_btn.pressed.connect(func() -> void:
				var new_proxy: StringName = _choose_new_proxy_for(eid)
				if new_proxy != &"":
					Entities.reestablish_control(eid, new_proxy)
				_clear_body()
				_render_list())
			_body_vbox.add_child(reclaim_btn)
			continue
		_body_vbox.add_child(_make_body_line("•  %s — %s in %s · %d silver/month · %s · %s" % [
			e.display_name,
			e.kind_label().to_lower(),
			_kingdom_name(e.home_kingdom),
			_effective_monthly_yield(e),
			e.corruption_phrase(),
			e.memory_phrase(),
		]))
		# §20 paperwork. A muted secondary line, just enough that the
		# player can see what their names look like when someone
		# does pull the charter.
		var papers_line: Label = _make_body_line("    on paper: " + e.papers_phrase(-GameClock.year))
		papers_line.add_theme_color_override("font_color", Color(0.42, 0.38, 0.32, 1.0))
		papers_line.add_theme_font_size_override("font_size", 12)
		_body_vbox.add_child(papers_line)
	_body_vbox.add_child(_make_divider())


func _choose_new_proxy_for(entity_id: StringName) -> StringName:
	# Prefer the first host currently positioned in the entity's
	# home kingdom. If none, fall back to any host, then any
	# living merchant-role actor in the home kingdom. Empty if
	# nothing plausible exists — the player then has to cultivate
	# a fresh contact before re-establishing.
	var e: OwnedEntity = Entities.get_entity(entity_id)
	if e == null:
		return &""
	var hosts_here: Array[Actor] = Actors.hosts_in(e.home_kingdom)
	if not hosts_here.is_empty():
		return hosts_here[0].id
	var any_hosts: Array[Actor] = Actors.hosts()
	if not any_hosts.is_empty():
		return any_hosts[0].id
	for a in Actors.actors_in_kingdom(e.home_kingdom):
		if a.is_alive() and a.role == Actor.Role.MERCHANT:
			return a.id
	return &""


func _effective_monthly_yield(e: OwnedEntity) -> int:
	if e.compromised or e.corruption >= OwnedEntity.CORRUPTION_LOSS_THRESHOLD:
		return 0
	if e.corruption >= OwnedEntity.CORRUPTION_LEAK_THRESHOLD:
		return int(round(e.monthly_yield_silver * 0.85))
	return e.monthly_yield_silver


func _kingdom_name(kid: String) -> String:
	var k: Kingdom = WorldData.get_kingdom(kid)
	return k.kingdom_name if k != null else kid


func _build_kingdom_row(k: Kingdom) -> Control:
	var row: Button = Button.new()
	row.text = ""
	row.flat = true
	row.custom_minimum_size.y = 56.0
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

	var left_vbox: VBoxContainer = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 2)
	left_vbox.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_child(left_vbox)

	var name_l: Label = Label.new()
	name_l.text = k.kingdom_name
	name_l.add_theme_color_override("font_color", COLOR_INK)
	name_l.add_theme_font_size_override("font_size", 15)
	left_vbox.add_child(name_l)

	var blurb: Label = Label.new()
	blurb.text = String(CONDITION_BLURBS[k.treasury_condition])
	blurb.add_theme_color_override("font_color", COLOR_INK_MUTED)
	blurb.add_theme_font_size_override("font_size", 11)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_vbox.add_child(blurb)

	# §15 — coverage-gated coffers figure. Players with a coordinator
	# on site read the number; distant crowns show "?" or a wide band.
	var coffers_line: Label = Label.new()
	coffers_line.text = "Coffers: %s" % _treasury_display(k)
	coffers_line.add_theme_color_override("font_color", COLOR_INK_MUTED)
	coffers_line.add_theme_font_size_override("font_size", 11)
	left_vbox.add_child(coffers_line)

	var strip: Control = _build_trajectory_strip(k.id, 6, 10, false)
	if strip != null:
		left_vbox.add_child(strip)

	var tag: Label = Label.new()
	tag.text = String(CONDITION_TAGS[k.treasury_condition])
	tag.add_theme_color_override("font_color", CONDITION_COLORS[k.treasury_condition])
	tag.add_theme_font_size_override("font_size", 12)
	tag.custom_minimum_size.x = 110.0
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(tag)

	# Inline direct-action chips. Mouse-filter STOP so they eat their
	# own clicks without falling through to the row-level "open detail".
	var actions_col: VBoxContainer = VBoxContainer.new()
	actions_col.add_theme_constant_override("separation", 3)
	actions_col.custom_minimum_size.x = 120.0
	actions_col.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_child(actions_col)

	var kid: String = k.id
	actions_col.add_child(_make_row_action_chip(
		"Offer loan",
		"Lend silver to this crown in return for an IOU.",
		func() -> void: offer_loan_requested.emit(kid),
	))
	actions_col.add_child(_make_row_action_chip(
		"Pressure",
		"Open Compose pre-selected to a regional kingdom-target action against this crown.",
		func() -> void: economic_pressure_requested.emit(kid),
	))

	row.pressed.connect(func() -> void: _render_detail(k.id))
	return row


func _make_row_action_chip(label: String, tooltip: String, on_press: Callable) -> Button:
	var b: Button = Button.new()
	b.text = label
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(120.0, 22.0)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", COLOR_INK)
	b.add_theme_font_size_override("font_size", 10)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.88, 0.82, 0.68, 0.80)
	sb.border_color = COLOR_PARCHMENT_EDGE
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	var hover: StyleBoxFlat = sb.duplicate()
	hover.bg_color = Color(0.75, 0.62, 0.40, 0.95)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(on_press)
	return b


# --- Detail ------------------------------------------------------------------

func _render_detail(kingdom_id: String) -> void:
	var k: Kingdom = WorldData.get_kingdom(kingdom_id)
	if k == null:
		_render_list()
		return

	_mode = Mode.DETAIL
	_focus_kingdom_id = kingdom_id
	_clear_body()

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_body_vbox.add_child(header)

	var back: Button = Button.new()
	back.text = "‹ Back to the ledger"
	back.flat = true
	back.add_theme_color_override("font_color", COLOR_INK_MUTED)
	back.add_theme_font_size_override("font_size", 12)
	back.pressed.connect(func() -> void: _render_list())
	header.add_child(back)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_body_vbox.add_child(_make_title(k.kingdom_name))

	var tag_row: HBoxContainer = HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 10)
	_body_vbox.add_child(tag_row)

	var tag_l: Label = Label.new()
	tag_l.text = String(CONDITION_TAGS[k.treasury_condition])
	tag_l.add_theme_color_override("font_color", CONDITION_COLORS[k.treasury_condition])
	tag_l.add_theme_font_size_override("font_size", 13)
	tag_row.add_child(tag_l)

	var sub_l: Label = Label.new()
	sub_l.text = String(CONDITION_BLURBS[k.treasury_condition])
	sub_l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	sub_l.add_theme_font_size_override("font_size", 12)
	sub_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_row.add_child(sub_l)

	_body_vbox.add_child(_make_divider())
	_body_vbox.add_child(_make_section_heading("THE COFFERS"))
	_body_vbox.add_child(_make_body_line(
		"Silver on hand — %s." % IntelNumbers.amount_display(k.treasury_silver, _coverage_for(k.id), "silver")
	))
	if k.treasury_gold > 0.0 or _coverage_for(k.id) >= 50:
		_body_vbox.add_child(_make_body_line(
			"Gold reserves — %s." % IntelNumbers.amount_display(k.treasury_gold, _coverage_for(k.id), "gold")
		))
	var cov_note: String = _coverage_note(k.id)
	if cov_note != "":
		var nl: Label = _make_body_line(cov_note)
		nl.add_theme_color_override("font_color", COLOR_INK_MUTED)
		nl.add_theme_font_size_override("font_size", 11)
		_body_vbox.add_child(nl)

	_body_vbox.add_child(_make_divider())
	_body_vbox.add_child(_make_section_heading("THE LAST MONTHS"))

	var strip: Control = _build_trajectory_strip(k.id, 12, 16, true)
	if strip != null:
		_body_vbox.add_child(strip)

	_body_vbox.add_child(_make_body_line(KingdomEconomy.trajectory_phrase(k.id)))

	_body_vbox.add_child(_make_divider())
	_body_vbox.add_child(_make_section_heading("WHERE THE SILVER FLOWS FROM"))

	var provinces: Array = []
	for pid in k.owned_provinces:
		var p: Province = WorldData.get_province(pid)
		if p != null:
			provinces.append(p)
	if provinces.is_empty():
		_body_vbox.add_child(_make_body_line("They hold no land of consequence to their coffers."))
	else:
		provinces.sort_custom(func(a, b):
			return _province_income(a) > _province_income(b))
		for p in provinces:
			_body_vbox.add_child(_build_province_line(p))

	_body_vbox.add_child(_make_divider())
	_body_vbox.add_child(_make_section_heading("THIS MONTH'S FLOW"))

	# We surface the *direction* of this month's net flow in prose and
	# the absolute figures gated by coverage. Cold kingdoms show "?";
	# a coordinator-on-site reads the exact coin.
	var prev: Dictionary = KingdomEconomy.preview(k)
	var income: float = float(prev.get("income", 0.0))
	var expend: float = float(prev.get("expenditure", 0.0))
	var war_cost: float = float(prev.get("war_cost", 0.0))
	var net: float = income - expend
	var cov: int = _coverage_for(k.id)
	_body_vbox.add_child(_make_body_line(_flow_phrase(net, expend)))
	_body_vbox.add_child(_make_body_line(
		"Monthly income — %s. Outlay — %s." % [
			IntelNumbers.amount_display(income, cov, "silver"),
			IntelNumbers.amount_display(expend, cov, "silver"),
		]
	))
	if war_cost > 0.0:
		_body_vbox.add_child(_make_body_line(_war_burden_phrase(war_cost, expend)))
		_body_vbox.add_child(_make_body_line(
			"The armies draw — %s each month." % IntelNumbers.amount_display(war_cost, cov, "silver")
		))

	var army: Army = Armies.get_army(k.id)
	if army != null:
		_body_vbox.add_child(_make_divider())
		_body_vbox.add_child(_make_section_heading("THE ARMY UNDER THE STANDARD"))
		_body_vbox.add_child(_make_body_line(army.size_phrase().capitalize() + "."))
		_body_vbox.add_child(_make_body_line(
			"Under the standard: %s." % IntelNumbers.thousands_display(army.size, cov, "men")
		))
		if army.size_ceiling > army.size:
			_body_vbox.add_child(_make_body_line(
				"At full strength they could raise %s." % IntelNumbers.thousands_display(army.size_ceiling, cov, "men")
			))
		_body_vbox.add_child(_make_body_line("Quality: %s." % army.quality_phrase()))
		_body_vbox.add_child(_make_body_line("Spirit: %s." % army.morale_phrase()))
		_body_vbox.add_child(_make_body_line("Supply: %s." % army.supply_phrase()))
		_body_vbox.add_child(_make_body_line("Loyalty: %s." % army.loyalty_phrase()))

	# Direct actions — mirror the row chips at a larger size so the
	# detail panel is never information-only. Treasury is the gateway
	# to money-and-leverage mechanics; these two buttons are the
	# fastest path into them.
	_body_vbox.add_child(_make_divider())
	_body_vbox.add_child(_make_section_heading("WHAT YOU CAN SEND AGAINST THIS CROWN"))
	var detail_kid: String = k.id
	var loan_btn: Button = Button.new()
	loan_btn.text = "Offer a loan to %s…" % k.kingdom_name
	loan_btn.tooltip_text = "Lend silver from your purse in exchange for an IOU the crown will owe you."
	loan_btn.custom_minimum_size.y = 30.0
	loan_btn.focus_mode = Control.FOCUS_NONE
	loan_btn.add_theme_color_override("font_color", COLOR_INK)
	loan_btn.add_theme_font_size_override("font_size", 13)
	loan_btn.pressed.connect(func() -> void: offer_loan_requested.emit(detail_kid))
	_body_vbox.add_child(loan_btn)

	var pressure_btn: Button = Button.new()
	pressure_btn.text = "Apply economic pressure on %s…" % k.kingdom_name
	pressure_btn.tooltip_text = "Open Compose pre-selected to a regional kingdom-scope action against this crown."
	pressure_btn.custom_minimum_size.y = 30.0
	pressure_btn.focus_mode = Control.FOCUS_NONE
	pressure_btn.add_theme_color_override("font_color", COLOR_INK)
	pressure_btn.add_theme_font_size_override("font_size", 13)
	pressure_btn.pressed.connect(func() -> void: economic_pressure_requested.emit(detail_kid))
	_body_vbox.add_child(pressure_btn)

	_body_vbox.add_child(_make_close_button("Set aside", func() -> void: close()))


func _build_province_line(p: Province) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = MOUSE_FILTER_IGNORE

	var name_l: Label = Label.new()
	name_l.text = "•  %s" % p.province_name
	name_l.add_theme_color_override("font_color", COLOR_INK)
	name_l.add_theme_font_size_override("font_size", 13)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)

	var contrib_l: Label = Label.new()
	contrib_l.text = _province_contribution_phrase(p)
	contrib_l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	contrib_l.add_theme_font_size_override("font_size", 12)
	contrib_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	contrib_l.custom_minimum_size.x = 200.0
	row.add_child(contrib_l)
	return row


# --- Phrases -----------------------------------------------------------------

static func _province_income(p: Province) -> float:
	return p.grain_production + p.silver_production + p.iron_production + p.timber_production


func _province_contribution_phrase(p: Province) -> String:
	var v: float = _province_income(p)
	var qualitative: String
	if v <= 0.0:      qualitative = "yields almost nothing of consequence"
	elif v < 6.0:     qualitative = "yields a meagre dribble"
	elif v < 14.0:    qualitative = "a modest tithe"
	elif v < 28.0:    qualitative = "a handsome share"
	else:             qualitative = "the backbone of the treasury"
	if v <= 0.0:
		return qualitative
	var cov: int = _coverage_for(p.owning_kingdom)
	return "%s · %s silver/mo" % [qualitative, IntelNumbers.amount_display(v, cov)]


# --- Coverage helpers --------------------------------------------------------

func _coverage_for(kingdom_id: String) -> int:
	if Picture == null or kingdom_id.is_empty():
		return 0
	return Picture.score_for(kingdom_id)


## Player-facing hint about how reliable the figures above are. Returns
## empty when coverage is exact — no need to explain a clean number.
func _coverage_note(kingdom_id: String) -> String:
	var t: int = IntelNumbers.tier_for(_coverage_for(kingdom_id))
	match t:
		IntelNumbers.Tier.UNKNOWN:
			return "No coin counted here. Lift a coordinator onto the treasury and the bench will start to show."
		IntelNumbers.Tier.WIDE:
			return "Figures inferred from market gossip — treat the range as the outer walls of what could be true."
		IntelNumbers.Tier.ROUGH:
			return "A rough count, from operatives close enough to the books."
		IntelNumbers.Tier.NARROW:
			return "A workable count, corroborated by more than one voice."
		IntelNumbers.Tier.TIGHT:
			return "Near-current figures, sourced from the treasurer's own clerks."
	return ""


func _treasury_display(k: Kingdom) -> String:
	return IntelNumbers.amount_display(k.treasury_silver, _coverage_for(k.id), "silver")


## A line explaining how much of the crown's monthly cost is war —
## qualitative only, like every other number in the ledger. `expend`
## here is the full expenditure (with war cost already included).
func _war_burden_phrase(war_cost: float, expend: float) -> String:
	var share: float = war_cost / max(1.0, expend)
	if share < 0.20:
		return "A portion of what goes out now goes to the armies in the field."
	if share < 0.40:
		return "The war is a drag on the books. Not yet ruinous, but felt at every pay-day."
	if share < 0.60:
		return "The war eats the treasury in earnest. What the crown takes in, the army takes out."
	return "The war has become the crown's main expense. Every other line is a footnote to it."


func _flow_phrase(net: float, expend: float) -> String:
	var normalized: float = net / max(1.0, expend)
	if normalized > 0.15:
		return "The coffers gather faster than they empty. A surplus month."
	if normalized > -0.05:
		return "Income and outlay are close enough to call even."
	if normalized > -0.30:
		return "The treasury is ebbing. Not dangerous yet, but noted."
	return "The crown is bleeding silver. Something will have to give."


# --- Hooks -------------------------------------------------------------------

func _on_economy_tick(_snapshot: Array) -> void:
	# Redraw whatever we're currently showing so the ledger stays live
	# as months pass.
	if _mode == Mode.DETAIL and not _focus_kingdom_id.is_empty():
		_render_detail(_focus_kingdom_id)
	else:
		_render_list()


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


func _make_close_button(label: String, on_press: Callable) -> Button:
	var b: Button = Button.new()
	b.text = label
	b.custom_minimum_size.y = 34.0
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", COLOR_INK)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(on_press)
	return b


# --- Trajectory strip --------------------------------------------------------
#
# Renders up to `slots` horizontal blocks, one per recorded month of the
# kingdom's treasury condition history. Oldest month on the left, current
# on the right. Empty tail slots are rendered in a muted parchment band
# so the widget's width stays visually consistent across kingdoms.

func _build_trajectory_strip(
	kingdom_id: String,
	slots: int,
	block_h: int,
	show_caption: bool,
) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if show_caption:
		var caption: Label = Label.new()
		caption.text = "← older   |   newer →"
		caption.add_theme_color_override("font_color", COLOR_INK_MUTED)
		caption.add_theme_font_size_override("font_size", 10)
		box.add_child(caption)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)

	var history: Array = KingdomEconomy.history_for(kingdom_id)
	# Right-align: if history has fewer entries than slots, pad empty
	# blocks on the left so the newest always sits flush on the right.
	var empty_head: int = maxi(0, slots - history.size())
	var taken: Array = history
	if history.size() > slots:
		taken = history.slice(history.size() - slots)

	for i in range(empty_head):
		row.add_child(_make_trajectory_block(-1, block_h))
	for cond in taken:
		row.add_child(_make_trajectory_block(int(cond), block_h))

	return box


func _make_trajectory_block(condition: int, block_h: int) -> Control:
	var panel: Panel = Panel.new()
	panel.custom_minimum_size = Vector2(14, block_h)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	if condition < 0:
		sb.bg_color = Color(COLOR_PARCHMENT_EDGE.r, COLOR_PARCHMENT_EDGE.g, COLOR_PARCHMENT_EDGE.b, 0.18)
	else:
		var c: Color = CONDITION_COLORS[condition]
		c.a = 0.85
		sb.bg_color = c
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	panel.add_theme_stylebox_override("panel", sb)
	if condition >= 0:
		panel.tooltip_text = String(CONDITION_TAGS[condition])
	return panel
