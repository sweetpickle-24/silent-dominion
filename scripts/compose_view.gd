extends Control
## Overlay that lets the player compose a real action.
##
## Two-step flow, rendered into the same sheet:
##   1. PICK_ACTION   — all ActionDefinitions from `Actions`, grouped by
##                      tier, each shown as a card with display name,
##                      blurb, costs, and typical resolve window.
##   2. PICK_TARGET   — once an action is chosen, list valid targets.
##                      ACTOR  -> every living actor (optional kingdom filter).
##                      KINGDOM -> every kingdom.
##                      PROVINCE -> every province.
##                      NONE   -> no target page; issues immediately.
##
## Issuing routes through `Actions.issue()`, which schedules the action,
## emits EventBus.action_issued, and eventually drops a report into the
## inbox. This view then closes.
##
## Emits `closed` when dismissed.

signal closed

enum Step { PICK_ACTION, PICK_TARGET, CONFIRMATION }

# --- Visual tokens (reused from the rest of the table) ----------------------

const COLOR_DIMMER: Color         = Color(0, 0, 0, 0.62)
const COLOR_PARCHMENT: Color      = Color(0.96, 0.92, 0.82, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.55, 0.42, 0.28, 0.7)
const COLOR_CARD: Color           = Color(0.98, 0.94, 0.84, 1.0)
const COLOR_CARD_HOVER: Color     = Color(0.93, 0.87, 0.72, 1.0)
const COLOR_INK: Color            = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.22, 0.14, 0.06, 0.65)
const COLOR_WAX: Color            = Color(0.55, 0.08, 0.08, 1.0)
const COLOR_TIER_DEEP: Color      = Color(0.18, 0.34, 0.22, 1.0)
const COLOR_TIER_ACTIVE: Color    = Color(0.54, 0.36, 0.10, 1.0)
const COLOR_TIER_HIGH: Color      = Color(0.55, 0.08, 0.08, 1.0)

const ALL_KINGDOMS_KEY: String = "__all__"

# --- State -------------------------------------------------------------------

var _step: Step = Step.PICK_ACTION
var _selected_action: ActionDefinition = null
var _kingdom_filter: String = ALL_KINGDOMS_KEY

# --- Nodes -------------------------------------------------------------------

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
	_render_action_picker()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			match _step:
				Step.PICK_TARGET:
					_selected_action = null
					_render_action_picker()
				_:
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
	_dimmer.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
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


# --- Step 1 — action picker --------------------------------------------------

func _render_action_picker() -> void:
	_step = Step.PICK_ACTION
	_selected_action = null
	_clear_body()

	_body_vbox.add_child(_make_title("Compose a Letter"))
	_body_vbox.add_child(_make_subtitle(
		"Every action you take is a letter sealed and sent. Choose your instrument first."
	))
	_body_vbox.add_child(_make_divider())

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 420.0
	_body_vbox.add_child(scroll)

	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var defs: Array[ActionDefinition] = Actions.all_definitions()
	defs.sort_custom(func(a, b):
		if a.tier == b.tier:
			return a.display_name < b.display_name
		return int(a.tier) < int(b.tier))

	for def in defs:
		list.add_child(_build_action_card(def))

	_body_vbox.add_child(_make_close_button("Set aside", func() -> void: close()))


func _build_action_card(def: ActionDefinition) -> Control:
	var allowed: bool = Exposure.allows_tier(def.tier)
	var has_host: bool = not def.requires_host_target or Actors.hosts().size() > 0
	var enabled: bool = allowed and has_host

	var card: Button = Button.new()
	card.text = ""
	card.flat = true
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size.y = 84.0
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.disabled = not enabled
	if not allowed:
		card.tooltip_text = Exposure.block_reason(def.tier)
	elif not has_host:
		card.tooltip_text = "You have no hosts loyal enough to act for you yet."

	var normal_sb: StyleBoxFlat = _card_stylebox(COLOR_CARD)
	var hover_sb:  StyleBoxFlat = _card_stylebox(COLOR_CARD_HOVER)
	if not enabled:
		normal_sb = _card_stylebox(Color(0.90, 0.86, 0.78, 1.0))
	card.add_theme_stylebox_override("normal", normal_sb)
	card.add_theme_stylebox_override("hover", hover_sb)
	card.add_theme_stylebox_override("pressed", hover_sb)
	card.add_theme_stylebox_override("disabled", normal_sb)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	# Title row: name + tier tag
	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	title_row.mouse_filter = MOUSE_FILTER_IGNORE
	vbox.add_child(title_row)

	var name_label: Label = Label.new()
	name_label.text = def.display_name
	name_label.add_theme_color_override("font_color", COLOR_INK)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(name_label)

	var tier_tag: Label = Label.new()
	tier_tag.text = _tier_label(def.tier)
	tier_tag.add_theme_color_override("font_color", _tier_color(def.tier))
	tier_tag.add_theme_font_size_override("font_size", 10)
	title_row.add_child(tier_tag)

	if def.requires_host_target:
		var host_tag: Label = Label.new()
		host_tag.text = "VIA HOST"
		host_tag.add_theme_color_override("font_color", Color(0.18, 0.34, 0.22, 1.0))
		host_tag.add_theme_font_size_override("font_size", 10)
		title_row.add_child(host_tag)

	# Blurb
	var blurb: Label = Label.new()
	blurb.text = def.blurb
	blurb.add_theme_color_override("font_color", COLOR_INK_MUTED)
	blurb.add_theme_font_size_override("font_size", 12)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(blurb)

	# Meta line: resolution window + costs
	var meta: Label = Label.new()
	meta.text = "resolves in %d–%d days    ·    silver %d    ·    exposure +%d" % [
		def.min_days_to_resolve,
		def.max_days_to_resolve,
		def.silver_cost,
		def.exposure_cost,
	]
	meta.add_theme_color_override("font_color", COLOR_INK_MUTED)
	meta.add_theme_font_size_override("font_size", 10)
	vbox.add_child(meta)

	# If exposure currently bars this tier, surface the reason inline
	# instead of silently making the card unclickable.
	if not allowed:
		name_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
		tier_tag.text = "BARRED  —  " + tier_tag.text
		var gate: Label = Label.new()
		gate.text = Exposure.block_reason(def.tier)
		gate.add_theme_color_override("font_color", COLOR_WAX)
		gate.add_theme_font_size_override("font_size", 11)
		gate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(gate)
	elif not has_host:
		name_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
		var gate: Label = Label.new()
		gate.text = "You have no hosts loyal enough to act for you yet. Cultivate one past the threshold first."
		gate.add_theme_color_override("font_color", COLOR_INK_MUTED)
		gate.add_theme_font_size_override("font_size", 11)
		gate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(gate)

	card.pressed.connect(func() -> void: _on_action_chosen(def))
	return card


func _on_action_chosen(def: ActionDefinition) -> void:
	_selected_action = def
	if def.target_kind == ActionDefinition.TargetKind.NONE:
		_issue_action("")
		return
	_render_target_picker()


# --- Step 2 — target picker --------------------------------------------------

func _render_target_picker() -> void:
	_step = Step.PICK_TARGET
	_clear_body()

	# Header: back + title
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_body_vbox.add_child(header)

	var back: Button = Button.new()
	back.text = "‹ Choose another instrument"
	back.flat = true
	back.add_theme_color_override("font_color", COLOR_INK_MUTED)
	back.add_theme_font_size_override("font_size", 12)
	back.pressed.connect(func() -> void: _render_action_picker())
	header.add_child(back)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_body_vbox.add_child(_make_title(_selected_action.display_name))
	_body_vbox.add_child(_make_subtitle(
		"Whom shall the letter name? " + _target_kind_hint(_selected_action.target_kind)
	))

	if _selected_action.target_kind == ActionDefinition.TargetKind.ACTOR:
		_render_actor_target_list()
	elif _selected_action.target_kind == ActionDefinition.TargetKind.KINGDOM:
		_render_kingdom_target_list()
	elif _selected_action.target_kind == ActionDefinition.TargetKind.PROVINCE:
		_render_province_target_list()

	_body_vbox.add_child(_make_close_button("Set aside", func() -> void: close()))


func _render_actor_target_list() -> void:
	# Kingdom filter
	var filter_bar: HBoxContainer = HBoxContainer.new()
	filter_bar.add_theme_constant_override("separation", 8)
	_body_vbox.add_child(filter_bar)

	var filter_label: Label = Label.new()
	filter_label.text = "From:"
	filter_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
	filter_label.add_theme_font_size_override("font_size", 12)
	filter_bar.add_child(filter_label)

	var dropdown: OptionButton = OptionButton.new()
	dropdown.add_theme_font_size_override("font_size", 12)
	dropdown.add_item("Any kingdom")
	dropdown.set_item_metadata(0, ALL_KINGDOMS_KEY)
	var seen: Dictionary = {}
	var uniq: Array = []
	for a in Actors.all_actors():
		if a.kingdom_id != "" and not seen.has(a.kingdom_id):
			seen[a.kingdom_id] = true
			uniq.append(a.kingdom_id)
	uniq.sort()
	for kid in uniq:
		var k_obj: Kingdom = WorldData.get_kingdom(kid)
		var label: String = k_obj.kingdom_name if k_obj != null else String(kid)
		var idx: int = dropdown.item_count
		dropdown.add_item(label)
		dropdown.set_item_metadata(idx, String(kid))
	for i in range(dropdown.item_count):
		if String(dropdown.get_item_metadata(i)) == _kingdom_filter:
			dropdown.select(i)
			break
	dropdown.item_selected.connect(func(idx: int) -> void:
		_kingdom_filter = String(dropdown.get_item_metadata(idx))
		call_deferred("_render_target_picker"))
	filter_bar.add_child(dropdown)

	# Scrollable list
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 360.0
	_body_vbox.add_child(scroll)

	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 0)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var candidates: Array[Actor] = []
	var host_only: bool = _selected_action != null and _selected_action.requires_host_target
	for a in Actors.all_actors():
		if not a.is_alive():
			continue
		if host_only and not a.is_host():
			continue
		if _kingdom_filter != ALL_KINGDOMS_KEY and a.kingdom_id != _kingdom_filter:
			continue
		candidates.append(a)
	candidates.sort_custom(func(x, y):
		if x.kingdom_id == y.kingdom_id:
			return x.given_name < y.given_name
		return x.kingdom_id < y.kingdom_id)

	if candidates.is_empty():
		if host_only:
			list.add_child(_make_body_line(
				"No host is yet loyal enough to act for you. Cultivate one past the threshold, and return."
			))
		else:
			list.add_child(_make_body_line("No names fit that description on the table just now."))
		return

	for a in candidates:
		list.add_child(_build_actor_target_row(a))


func _build_actor_target_row(actor: Actor) -> Control:
	var row: Button = Button.new()
	row.text = ""
	row.flat = true
	row.custom_minimum_size.y = 40.0
	row.focus_mode = Control.FOCUS_NONE
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hover_sb: StyleBoxFlat = _card_stylebox(COLOR_CARD_HOVER)
	row.add_theme_stylebox_override("hover", hover_sb)
	row.add_theme_stylebox_override("pressed", hover_sb)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	hbox.offset_left = 10
	hbox.offset_right = -10
	hbox.offset_top = 4
	hbox.offset_bottom = -4
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(hbox)

	var name_label: Label = Label.new()
	name_label.text = actor.display_name()
	name_label.add_theme_color_override("font_color", COLOR_INK)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)

	var k: Kingdom = WorldData.get_kingdom(actor.kingdom_id)
	var kingdom_name: String = k.kingdom_name if k != null else actor.kingdom_id
	var meta: Label = Label.new()
	meta.text = "%s — %s" % [TraitCues.role_title(actor.role), kingdom_name]
	meta.add_theme_color_override("font_color", COLOR_INK_MUTED)
	meta.add_theme_font_size_override("font_size", 11)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(meta)

	if actor.is_host():
		var host_tag: Label = Label.new()
		host_tag.text = "HOST"
		host_tag.add_theme_color_override("font_color", Color(0.18, 0.34, 0.22, 1.0))
		host_tag.add_theme_font_size_override("font_size", 10)
		host_tag.custom_minimum_size.x = 40.0
		host_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(host_tag)

	row.pressed.connect(func() -> void: _issue_action(String(actor.id)))
	return row


func _render_kingdom_target_list() -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 360.0
	_body_vbox.add_child(scroll)

	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var kingdoms: Array = WorldData.kingdoms.values()
	kingdoms.sort_custom(func(a, b): return a.kingdom_name < b.kingdom_name)
	for k in kingdoms:
		var row: Button = Button.new()
		row.text = k.kingdom_name
		row.flat = true
		row.custom_minimum_size.y = 34.0
		row.focus_mode = Control.FOCUS_NONE
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_color_override("font_color", COLOR_INK)
		row.add_theme_font_size_override("font_size", 13)
		row.add_theme_stylebox_override("hover", _card_stylebox(COLOR_CARD_HOVER))
		row.pressed.connect(func() -> void: _issue_action(String(k.id)))
		list.add_child(row)


func _render_province_target_list() -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 360.0
	_body_vbox.add_child(scroll)

	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var provinces: Array = WorldData.provinces.values()
	provinces.sort_custom(func(a, b): return a.province_name < b.province_name)
	for p in provinces:
		var row: Button = Button.new()
		row.text = p.province_name
		row.flat = true
		row.custom_minimum_size.y = 34.0
		row.focus_mode = Control.FOCUS_NONE
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_color_override("font_color", COLOR_INK)
		row.add_theme_font_size_override("font_size", 13)
		row.add_theme_stylebox_override("hover", _card_stylebox(COLOR_CARD_HOVER))
		row.pressed.connect(func() -> void: _issue_action(String(p.id)))
		list.add_child(row)


# --- Step 3 — confirmation ---------------------------------------------------

func _issue_action(target_id: String) -> void:
	var handle: int = Actions.issue(_selected_action.id, target_id)
	if handle == Scheduler.INVALID_HANDLE:
		_render_error("The letter would not seal. No action was sent.")
		return
	_render_confirmation(target_id)


func _render_confirmation(target_id: String) -> void:
	_step = Step.CONFIRMATION
	_clear_body()

	var target_name: String = _pretty_target(_selected_action, target_id)

	_body_vbox.add_child(_make_title("Sealed and sent"))
	_body_vbox.add_child(_make_divider())

	var msg: Label = _make_body_line(
		"You draft a short letter — %s, regarding %s — set your seal in the hot wax, and hand it to a waiting runner.\n\nAdvance your dial. A reply will come in due time."
			% [_selected_action.display_name.to_lower(), target_name]
	)
	_body_vbox.add_child(msg)

	_body_vbox.add_child(_make_divider())

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_body_vbox.add_child(row)

	var another: Button = _make_secondary_button("Compose another", func() -> void:
		_render_action_picker())
	row.add_child(another)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	row.add_child(_make_primary_button("Back to the table", func() -> void: close()))


func _render_error(text: String) -> void:
	_clear_body()
	_body_vbox.add_child(_make_title("A problem with the letter"))
	_body_vbox.add_child(_make_body_line(text))
	_body_vbox.add_child(_make_close_button("Back", func() -> void: _render_action_picker()))


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


func _make_secondary_button(label: String, on_press: Callable) -> Button:
	return _make_close_button(label, on_press)


func _make_primary_button(label: String, on_press: Callable) -> Button:
	var b: Button = Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(160, 34)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_font_size_override("font_size", 13)

	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = COLOR_WAX
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	b.add_theme_stylebox_override("normal", sb)

	var hover_sb: StyleBoxFlat = sb.duplicate()
	hover_sb.bg_color = Color(0.7, 0.12, 0.12)
	b.add_theme_stylebox_override("hover", hover_sb)
	b.add_theme_stylebox_override("pressed", hover_sb)

	b.pressed.connect(on_press)
	return b


func _card_stylebox(bg: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = COLOR_PARCHMENT_EDGE
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.shadow_color = Color(0, 0, 0, 0.2)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	return sb


# --- Helpers -----------------------------------------------------------------

func _tier_label(tier: ActionDefinition.Tier) -> String:
	match tier:
		ActionDefinition.Tier.DEEP_SHADOW: return "DEEP  SHADOW"
		ActionDefinition.Tier.ACTIVE:      return "ACTIVE"
		ActionDefinition.Tier.HIGH:        return "HIGH  INTERVENTION"
		_: return ""


func _tier_color(tier: ActionDefinition.Tier) -> Color:
	match tier:
		ActionDefinition.Tier.DEEP_SHADOW: return COLOR_TIER_DEEP
		ActionDefinition.Tier.ACTIVE:      return COLOR_TIER_ACTIVE
		ActionDefinition.Tier.HIGH:        return COLOR_TIER_HIGH
		_: return COLOR_INK_MUTED


func _target_kind_hint(kind: ActionDefinition.TargetKind) -> String:
	match kind:
		ActionDefinition.TargetKind.ACTOR:    return "Pick a person."
		ActionDefinition.TargetKind.KINGDOM:  return "Pick a kingdom."
		ActionDefinition.TargetKind.PROVINCE: return "Pick a province."
		_: return ""


func _pretty_target(def: ActionDefinition, id: String) -> String:
	if def == null or id.is_empty():
		return id
	match def.target_kind:
		ActionDefinition.TargetKind.ACTOR:
			var a: Actor = Actors.get_actor(StringName(id))
			if a != null:
				return a.display_name()
		ActionDefinition.TargetKind.KINGDOM:
			var k: Kingdom = WorldData.get_kingdom(id)
			if k != null:
				return k.kingdom_name
		ActionDefinition.TargetKind.PROVINCE:
			var p: Province = WorldData.get_province(id)
			if p != null:
				return p.province_name
		_:
			pass
	return id
