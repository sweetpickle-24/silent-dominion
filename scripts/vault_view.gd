extends Control
## Full-screen overlay surfacing the player's financial network (§16).
##
## The Vault shows every banking house the player has an arrangement
## with: their capacity band, discretion band, reach, curiosity (a.k.a.
## how much they've started to wonder who they're actually serving),
## and any open IOUs the player holds against crowns.
##
## No raw silver numbers are shown. The whole financial system is
## qualitative from the player's side — they get bands and period
## phrases, never an integer balance.

signal closed

# --- Visual tokens -----------------------------------------------------

const COLOR_DIMMER: Color         = Color(0, 0, 0, 0.62)
const COLOR_PARCHMENT: Color      = Color(0.96, 0.92, 0.82, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.55, 0.42, 0.28, 0.7)
const COLOR_INK: Color            = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.22, 0.14, 0.06, 0.65)
const COLOR_ROW_HOVER: Color      = Color(0.88, 0.82, 0.68, 1.0)

const COLOR_CAP_AMPLE: Color      = Color(0.18, 0.34, 0.22, 1.0)
const COLOR_CAP_CAUTIOUS: Color   = Color(0.40, 0.36, 0.14, 1.0)
const COLOR_CAP_STRAINED: Color   = Color(0.62, 0.42, 0.14, 1.0)
const COLOR_CAP_TAPPED: Color     = Color(0.72, 0.28, 0.12, 1.0)

const COLOR_DISC_INVISIBLE: Color = Color(0.18, 0.34, 0.22, 1.0)
const COLOR_DISC_ORDINARY: Color  = Color(0.40, 0.36, 0.14, 1.0)
const COLOR_DISC_LOOSE: Color     = Color(0.62, 0.42, 0.14, 1.0)
const COLOR_DISC_SUSP: Color      = Color(0.72, 0.28, 0.12, 1.0)
const COLOR_DISC_COMP: Color      = Color(0.55, 0.08, 0.08, 1.0)


# --- Nodes -------------------------------------------------------------

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

	if not Finance.house_updated.is_connected(_on_finance_changed):
		Finance.house_updated.connect(_on_finance_changed)
	if not Finance.house_added.is_connected(_on_finance_changed):
		Finance.house_added.connect(_on_finance_changed)
	if not Finance.ledger_changed.is_connected(_on_ledger_changed):
		Finance.ledger_changed.connect(_on_ledger_changed)


func _exit_tree() -> void:
	if Finance.house_updated.is_connected(_on_finance_changed):
		Finance.house_updated.disconnect(_on_finance_changed)
	if Finance.house_added.is_connected(_on_finance_changed):
		Finance.house_added.disconnect(_on_finance_changed)
	if Finance.ledger_changed.is_connected(_on_ledger_changed):
		Finance.ledger_changed.disconnect(_on_ledger_changed)


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


# --- Chrome ------------------------------------------------------------

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
	_sheet.anchor_left = 0.5
	_sheet.anchor_top = 0.5
	_sheet.anchor_right = 0.5
	_sheet.anchor_bottom = 0.5
	_sheet.pivot_offset = Vector2(0, 0)
	_sheet.custom_minimum_size = Vector2(720, 560)
	_sheet.offset_left  = -360
	_sheet.offset_top   = -280
	_sheet.offset_right =  360
	_sheet.offset_bottom = 280
	_sheet.mouse_filter = MOUSE_FILTER_STOP

	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = COLOR_PARCHMENT
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.border_color = COLOR_PARCHMENT_EDGE
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 24
	_sheet.add_theme_stylebox_override("panel", sb)
	add_child(_sheet)

	_body_margin = MarginContainer.new()
	_body_margin.add_theme_constant_override("margin_left", 28)
	_body_margin.add_theme_constant_override("margin_right", 28)
	_body_margin.add_theme_constant_override("margin_top", 24)
	_body_margin.add_theme_constant_override("margin_bottom", 24)
	_sheet.add_child(_body_margin)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_margin.add_child(scroll)

	_body_vbox = VBoxContainer.new()
	_body_vbox.add_theme_constant_override("separation", 10)
	_body_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body_vbox)


# --- Render ------------------------------------------------------------

func _on_finance_changed(_house: Object = null) -> void:
	_render()


func _on_ledger_changed() -> void:
	_render()


func _render() -> void:
	for c in _body_vbox.get_children():
		c.queue_free()

	_body_vbox.add_child(_title("The Vault"))
	_body_vbox.add_child(_subtitle(
		"No silver sits here. What sits here are the hands that can produce it — and the price of asking them."
	))

	_body_vbox.add_child(_divider())
	_body_vbox.add_child(_heading("BANKING HOUSES"))

	var actives: Array[BankingHouse] = Finance.active_houses()
	if actives.is_empty():
		_body_vbox.add_child(_body_line(
			"No arrangements yet. Any large expense must come from the purse."
		))
	else:
		for h in actives:
			_body_vbox.add_child(_build_house_row(h))

	_body_vbox.add_child(_divider())
	_body_vbox.add_child(_heading("OPEN IOUs"))

	var ious: Array[Dictionary] = Finance.open_ious()
	if ious.is_empty():
		_body_vbox.add_child(_body_line(
			"No crown currently owes the network silver. Every debt on the table is someone else's."
		))
	else:
		for iou in ious:
			_body_vbox.add_child(_build_iou_row(iou))

	_body_vbox.add_child(_divider())
	_body_vbox.add_child(_build_close())


func _build_house_row(h: BankingHouse) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.tooltip_text = (
		"%s — a %s based in %s.\n"
		+ "Their patience with us is %s; their discretion, %s.\n"
		+ "They can reach: %s."
	) % [
		h.display_name,
		h.house_kind,
		_kingdom_name(h.home_kingdom),
		_capacity_phrase(h),
		_discretion_phrase(h),
		_reach_phrase(h),
	]

	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.94, 0.84, 1.0)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.border_color = COLOR_PARCHMENT_EDGE
	sb.border_width_bottom = 1
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Line 1: name + home
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	vbox.add_child(top)

	var name_label: Label = Label.new()
	name_label.text = h.display_name
	name_label.add_theme_color_override("font_color", COLOR_INK)
	name_label.add_theme_font_size_override("font_size", 16)
	top.add_child(name_label)

	var kind_label: Label = Label.new()
	kind_label.text = "— %s of %s" % [h.house_kind, _kingdom_name(h.home_kingdom)]
	kind_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
	kind_label.add_theme_font_size_override("font_size", 12)
	top.add_child(kind_label)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	top.add_child(_build_pill(h.capacity_band_label(), _capacity_color(h)))
	top.add_child(_build_pill(h.discretion_band_label(), _discretion_color(h)))

	# Line 2: reach
	var reach_label: Label = Label.new()
	reach_label.text = "Reaches: %s." % _reach_phrase(h)
	reach_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
	reach_label.add_theme_font_size_override("font_size", 12)
	reach_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(reach_label)

	# Line 3: curiosity warning, if any
	if h.is_suspicious():
		var warn: Label = Label.new()
		warn.text = (
			"They are starting to ask who their patron really is. Rest this "
			+ "house for a season or rotate the work elsewhere."
		)
		warn.add_theme_color_override("font_color", COLOR_DISC_SUSP)
		warn.add_theme_font_size_override("font_size", 12)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(warn)

	return panel


func _build_iou_row(iou: Dictionary) -> Control:
	var row: Label = Label.new()
	var kname: String = _kingdom_name(String(iou.get("debtor_kingdom", "")))
	var due_y: int = int(iou.get("due_year", 0))
	var due_m: int = int(iou.get("due_month", 0))
	var amt:   int = int(iou.get("amount", 0))
	var amt_band: String = "a handful of silver"
	if amt > 200:   amt_band = "a respectable sum"
	if amt > 800:   amt_band = "a considerable loan"
	if amt > 2000:  amt_band = "a crown-weight of silver"
	row.text = "%s owes us %s, to be returned by the %s of %d BCE." % [
		kname, amt_band, _month_name(due_m), -due_y,
	]
	row.add_theme_color_override("font_color", COLOR_INK)
	row.add_theme_font_size_override("font_size", 13)
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return row


# --- Pills and widgets -------------------------------------------------

func _build_pill(text: String, bg: Color) -> Control:
	var p: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 9999
	sb.corner_radius_top_right = 9999
	sb.corner_radius_bottom_left = 9999
	sb.corner_radius_bottom_right = 9999
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = MOUSE_FILTER_IGNORE

	var l: Label = Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", COLOR_PARCHMENT)
	l.add_theme_font_size_override("font_size", 10)
	p.add_child(l)
	return p


func _capacity_color(h: BankingHouse) -> Color:
	match h.capacity_band():
		&"ample":      return COLOR_CAP_AMPLE
		&"cautious":   return COLOR_CAP_CAUTIOUS
		&"strained":   return COLOR_CAP_STRAINED
		&"tapped_out": return COLOR_CAP_TAPPED
	return COLOR_INK_MUTED


func _discretion_color(h: BankingHouse) -> Color:
	match h.discretion_band():
		&"invisible":   return COLOR_DISC_INVISIBLE
		&"discreet":    return COLOR_DISC_ORDINARY
		&"ordinary":    return COLOR_DISC_ORDINARY
		&"loose":       return COLOR_DISC_LOOSE
		&"suspicious":  return COLOR_DISC_SUSP
		&"compromised": return COLOR_DISC_COMP
	return COLOR_INK_MUTED


func _capacity_phrase(h: BankingHouse) -> String:
	match h.capacity_band():
		&"ample":      return "deep"
		&"cautious":   return "measured"
		&"strained":   return "thin"
		&"tapped_out": return "exhausted"
	return "unclear"


func _discretion_phrase(h: BankingHouse) -> String:
	match h.discretion_band():
		&"invisible":   return "near-perfect"
		&"discreet":    return "careful"
		&"ordinary":    return "adequate"
		&"loose":       return "careless"
		&"suspicious":  return "curious about us"
		&"compromised": return "in another's pocket"
	return "unclear"


func _reach_phrase(h: BankingHouse) -> String:
	var names: Array[String] = []
	for kid in h.reach:
		names.append(_kingdom_name(kid))
	if names.is_empty():
		return "nowhere useful"
	return ", ".join(names)


func _kingdom_name(kid: String) -> String:
	var k: Kingdom = WorldData.get_kingdom(kid)
	return k.kingdom_name if k != null else kid


func _month_name(m: int) -> String:
	match m:
		1:  return "month of the year's first frost"
		2:  return "second month"
		3:  return "month of the quickening"
		4:  return "month of the sowing"
		5:  return "month of long days"
		6:  return "midsummer"
		7:  return "month of the hot wind"
		8:  return "month of the first harvest"
		9:  return "month of the late harvest"
		10: return "month of the short sun"
		11: return "month of the sealing"
		12: return "dead of the year"
	return "season"


func _title(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_INK)
	l.add_theme_font_size_override("font_size", 22)
	return l


func _subtitle(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	l.add_theme_font_size_override("font_size", 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _heading(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	l.add_theme_font_size_override("font_size", 11)
	return l


func _body_line(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_INK)
	l.add_theme_font_size_override("font_size", 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _divider() -> HSeparator:
	var s: HSeparator = HSeparator.new()
	s.add_theme_color_override("color", COLOR_PARCHMENT_EDGE)
	return s


func _build_close() -> Button:
	var b: Button = Button.new()
	b.text = "Set aside"
	b.custom_minimum_size.y = 34.0
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", COLOR_INK)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(func() -> void: close())
	return b
