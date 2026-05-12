extends Control
## The Desk — the persistent game surface per interface-philosophy.md §7.1.
## All objects are simultaneously visible. No tab navigation.
## Details open as overlays; clicking background or Close dismisses.

var _time_keeper: Node
var _immortal_registry: Node
var _world_registry: Node
var _event_bus: Node
var _action_node: Node
var _inbox_node: Node
var _chain_node: Node
var _memoirs_node: Node

# Status strip elements
var _date_label: Label
var _era_label: Label
var _speed_label: Label

# Detail overlay
var _detail_overlay: Control
var _detail_bg: ColorRect
var _detail_container: CenterContainer
var _current_detail: Control = null

# Object sub-labels for live updates
var _inbox_count_label: Label
var _inflight_label: Label
var _roster_count_label: Label
var _memoirs_count_label: Label

# Fonts
var _serif_font: Font
var _sans_font: Font

# Colors
const _DESK_DARK := Color("#2a1f17")
const _DESK_MEDIUM := Color("#3d2e22")
const _DESK_LIGHT := Color("#5a4530")
const _PARCHMENT := Color("#e8dcc4")
const _INK_PRIMARY := Color("#1a1108")
const _INK_SECONDARY := Color("#5a4530")
const _INK_TERTIARY := Color("#7a6850")
const _DESK_TEXT := Color("#d4c5a8")
const _DESK_TEXT_SEC := Color("#9a8a70")
const _SEAL_RED := Color("#8b3a2a")


func _ready() -> void:
	_time_keeper = (Engine.get_main_loop() as SceneTree).root.get_node("TimeKeeper")
	_immortal_registry = (Engine.get_main_loop() as SceneTree).root.get_node("ImmortalRegistry")
	_world_registry = (Engine.get_main_loop() as SceneTree).root.get_node("WorldRegistry")
	_event_bus = (Engine.get_main_loop() as SceneTree).root.get_node("EventBus")
	_action_node = get_node_or_null("/root/Main/Mechanics/Action")
	_inbox_node = get_node_or_null("/root/Main/Mechanics/Inbox")
	_chain_node = get_node_or_null("/root/Main/Mechanics/Chain")
	_memoirs_node = get_node_or_null("/root/Main/Mechanics/Memoirs")

	_serif_font = load("res://data/fonts/EBGaramond-Regular.ttf")
	_sans_font = load("res://data/fonts/Inter-Regular.ttf")

	var table_theme: Theme = load("res://data/themes/table_theme.tres")
	if table_theme:
		theme = table_theme

	_build_desk()

	_time_keeper.speed_changed.connect(func(_s): _update_speed())
	_time_keeper.pause_changed.connect(func(_p): _update_speed())
	_time_keeper.era_about_to_transition.connect(func(_o, n): _era_label.text = EraValues.DISPLAY_NAMES.get(n, str(n)))

	# Subscribe to letter arrivals for inbox refresh
	_event_bus.subscribe(
		preload("res://scripts/data/events/letter_arrived_in_inbox_event.gd"),
		Callable(self, "_on_letter_arrived"), 200, &"", EndOfTickPhases.UI,
	)


func _process(_delta: float) -> void:
	_date_label.text = _time_keeper.get_display_date()
	# Update live counts
	if _inbox_node:
		var active: Array = _inbox_node.get_active_letters()
		var unread: int = 0
		for l: Letter in active:
			if not l.is_read:
				unread += 1
		_inbox_count_label.text = "%d letters%s" % [active.size(), " (%d unread)" % unread if unread > 0 else ""]
	if _action_node:
		var schemes: Array = _action_node.get_active_schemes()
		_inflight_label.text = "In-flight: %d" % schemes.size()


func _on_letter_arrived(_event) -> void:
	pass  # Live update happens in _process


func _build_desk() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = _DESK_DARK
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	# === Status Strip (top) ===
	var strip := HBoxContainer.new()
	strip.set_anchors_preset(PRESET_TOP_WIDE)
	strip.offset_bottom = 50
	strip.offset_left = 20
	strip.offset_right = -20
	strip.add_theme_constant_override("separation", 16)
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(strip)

	var lamp := Label.new()
	lamp.text = "🪔"
	lamp.add_theme_font_size_override("font_size", 20)
	strip.add_child(lamp)

	var spacer1 := Control.new()
	spacer1.size_flags_horizontal = SIZE_EXPAND_FILL
	strip.add_child(spacer1)

	_era_label = _make_label(EraValues.DISPLAY_NAMES.get(_time_keeper.current_era, ""), 14, _DESK_TEXT_SEC)
	strip.add_child(_era_label)

	_date_label = _make_label(_time_keeper.get_display_date(), 16, _DESK_TEXT, true)
	strip.add_child(_date_label)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = SIZE_EXPAND_FILL
	strip.add_child(spacer2)

	_speed_label = _make_label("", 14, _DESK_TEXT)
	strip.add_child(_speed_label)
	_update_speed()

	# === Desk Objects ===
	# Compose (left, upper)
	var compose := _make_desk_object("Compose a Dispatch", "Click to begin writing.", 50, 70, 480, 440)
	compose.gui_input.connect(func(e): _handle_click(e, "_open_compose"))
	add_child(compose)

	# Map (center-right, large)
	var map_obj := _make_desk_object("Map", "", 560, 70, 720, 540)
	map_obj.gui_input.connect(func(e): _handle_click(e, "_open_map"))
	_build_map_markers(map_obj)
	add_child(map_obj)

	# Inbox (right column)
	var inbox_obj := _make_desk_object("Inbox", "", 1300, 70, 280, 620)
	inbox_obj.gui_input.connect(func(e): _handle_click(e, "_open_inbox"))
	_inbox_count_label = _make_label("0 letters", 12, _INK_TERTIARY)
	inbox_obj.get_child(0).get_child(0).add_child(_inbox_count_label)
	_build_inbox_stack(inbox_obj)
	add_child(inbox_obj)

	# Accessory row (bottom-left)
	var ledger := _make_desk_object("Ledger", "Financial threads", 50, 560, 160, 140)
	ledger.gui_input.connect(func(e): _handle_click(e, "_open_ledger"))
	add_child(ledger)

	var roster := _make_desk_object("Roster", "", 230, 560, 160, 140)
	roster.gui_input.connect(func(e): _handle_click(e, "_open_roster"))
	_roster_count_label = _make_label("", 12, _INK_TERTIARY)
	roster.get_child(0).get_child(0).add_child(_roster_count_label)
	var chain_count: int = 0
	for cid: StringName in _immortal_registry.all_character_ids():
		var c: CharacterRecord = _immortal_registry.get_character(cid)
		if c.chain_status != ChainStatusValues.NONE:
			chain_count += 1
	_roster_count_label.text = "%d members" % chain_count
	add_child(roster)

	var memoirs_obj := _make_desk_object("Memoirs", "", 410, 560, 160, 140)
	memoirs_obj.gui_input.connect(func(e): _handle_click(e, "_open_memoirs"))
	_memoirs_count_label = _make_label("", 12, _INK_TERTIARY)
	memoirs_obj.get_child(0).get_child(0).add_child(_memoirs_count_label)
	if _memoirs_node:
		var lib = _memoirs_node.get_library(&"player")
		_memoirs_count_label.text = "%d patterns" % (lib.patterns.size() if lib else 0)
	add_child(memoirs_obj)

	var codebook := _make_desk_object("Codebook", "No ciphers", 590, 560, 140, 140)
	codebook.gui_input.connect(func(e): _handle_click(e, "_open_codebook"))
	add_child(codebook)

	# In-flight tray (bottom-right)
	var tray := _make_desk_object("", "", 1300, 710, 280, 50)
	tray.gui_input.connect(func(e): _handle_click(e, "_open_inflight"))
	_inflight_label = _make_label("In-flight: 0", 12, _DESK_TEXT_SEC)
	tray.get_child(0).get_child(0).add_child(_inflight_label)
	add_child(tray)

	# === Detail Overlay (invisible until opened) ===
	_detail_overlay = Control.new()
	_detail_overlay.set_anchors_preset(PRESET_FULL_RECT)
	_detail_overlay.visible = false
	_detail_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_detail_overlay)

	_detail_bg = ColorRect.new()
	_detail_bg.color = Color(0, 0, 0, 0.4)
	_detail_bg.set_anchors_preset(PRESET_FULL_RECT)
	_detail_bg.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_close_detail())
	_detail_overlay.add_child(_detail_bg)

	_detail_container = CenterContainer.new()
	_detail_container.set_anchors_preset(PRESET_FULL_RECT)
	_detail_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_overlay.add_child(_detail_container)


# === Object builders ===

func _make_desk_object(title: String, subtitle: String, x: int, y: int, w: int, h: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = Vector2(x, y)
	panel.size = Vector2(w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = _PARCHMENT
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	sb.border_color = _DESK_LIGHT
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 4)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	if title != "":
		var t := Label.new()
		t.text = title
		if _serif_font:
			t.add_theme_font_override("font", _serif_font)
		t.add_theme_font_size_override("font_size", 16)
		t.add_theme_color_override("font_color", _INK_PRIMARY)
		vbox.add_child(t)
	if subtitle != "":
		var s := Label.new()
		s.text = subtitle
		s.add_theme_font_size_override("font_size", 11)
		s.add_theme_color_override("font_color", _INK_TERTIARY)
		vbox.add_child(s)

	return panel


func _make_label(text: String, size: int, color: Color, serif: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if serif and _serif_font:
		l.add_theme_font_override("font", _serif_font)
	elif _sans_font:
		l.add_theme_font_override("font", _sans_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _handle_click(event: InputEvent, method: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		call(method)


# === Map markers ===

func _build_map_markers(map_panel: PanelContainer) -> void:
	# Render provinces as circles, routes as lines, places as dots.
	# Uses province center lat/lon; places offset from their province center.
	var map_w: float = map_panel.size.x - 24
	var map_h: float = map_panel.size.y - 24
	var min_lat: float = 25.0
	var max_lat: float = 45.0
	var min_lon: float = 5.0
	var max_lon: float = 55.0

	# Province circles (translucent, colored by kingdom)
	for pid: StringName in _world_registry.all_province_ids():
		var prov: ProvinceRecord = _world_registry.get_province(pid)
		var cx: float = ((prov.center_lon - min_lon) / (max_lon - min_lon)) * map_w + 12
		var cy: float = ((max_lat - prov.center_lat) / (max_lat - min_lat)) * map_h + 12
		var radius_px: float = (prov.render_radius_km / 111.0) / (max_lon - min_lon) * map_w
		radius_px = clampf(radius_px, 15, 60)
		var circle := ColorRect.new()
		circle.position = Vector2(cx - radius_px, cy - radius_px)
		circle.size = Vector2(radius_px * 2, radius_px * 2)
		circle.color = Color(0.7, 0.65, 0.55, 0.3)
		circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_panel.add_child(circle)
		# Province name
		var plbl := Label.new()
		plbl.text = prov.name
		plbl.position = Vector2(cx - 20, cy - 6)
		plbl.add_theme_font_size_override("font_size", 8)
		plbl.add_theme_color_override("font_color", Color("#7a6850"))
		plbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_panel.add_child(plbl)

	# Routes as lines (using Line2D for each)
	for rid: StringName in _world_registry.all_route_ids():
		var route: RouteRecord = _world_registry.get_route(rid)
		var line := Line2D.new()
		line.default_color = Color("#5a7898") if route.kind == &"sea" else Color("#8a6848")
		line.width = route.line_thickness
		for wp: StringName in route.waypoints:
			var place: PlaceRecord = _world_registry.get_place(wp)
			if place == null:
				continue
			var prov: ProvinceRecord = _world_registry.get_province(place.province)
			if prov == null:
				continue
			var h: int = hash(wp)
			var dx: float = (float(h % 100) - 50) / 50.0 * 0.5
			var dy: float = (float((h / 100) % 100) - 50) / 50.0 * 0.3
			var px: float = ((prov.center_lon + dx - min_lon) / (max_lon - min_lon)) * map_w + 12
			var py: float = ((max_lat - prov.center_lat - dy) / (max_lat - min_lat)) * map_h + 12
			line.add_point(Vector2(px, py))
		map_panel.add_child(line)

	# Place markers
	for place_id: StringName in _world_registry.all_place_ids():
		var place: PlaceRecord = _world_registry.get_place(place_id)
		var prov: ProvinceRecord = _world_registry.get_province(place.province)
		if prov == null:
			continue
		var h: int = hash(place_id)
		var dx: float = (float(h % 100) - 50) / 50.0 * 0.5
		var dy: float = (float((h / 100) % 100) - 50) / 50.0 * 0.3
		var px: float = ((prov.center_lon + dx - min_lon) / (max_lon - min_lon)) * map_w + 12
		var py: float = ((max_lat - prov.center_lat - dy) / (max_lat - min_lat)) * map_h + 12
		var marker := ColorRect.new()
		marker.size = Vector2(6, 6)
		marker.position = Vector2(px - 3, py - 3)
		marker.color = _SEAL_RED
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_panel.add_child(marker)
		var name_lbl := Label.new()
		name_lbl.text = place.name
		name_lbl.position = Vector2(px + 5, py - 7)
		name_lbl.add_theme_font_size_override("font_size", 9)
		name_lbl.add_theme_color_override("font_color", _INK_PRIMARY)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_panel.add_child(name_lbl)


# === Inbox stack ===

func _build_inbox_stack(inbox_panel: PanelContainer) -> void:
	if _inbox_node == null:
		return
	var active: Array = _inbox_node.get_active_letters()
	if active.is_empty():
		return
	active.sort_custom(func(a: Letter, b: Letter) -> bool: return a.day_received > b.day_received)
	var vbox: VBoxContainer = inbox_panel.get_child(0).get_child(0)
	var shown: int = mini(active.size(), 5)
	for i in range(shown):
		var letter: Letter = active[i]
		var card := PanelContainer.new()
		var card_sb := StyleBoxFlat.new()
		card_sb.bg_color = Color("#f5eed8") if letter.is_read else _PARCHMENT
		card_sb.set_corner_radius_all(2)
		card_sb.set_content_margin_all(6)
		card_sb.border_color = _DESK_LIGHT
		card_sb.set_border_width_all(1)
		card.add_theme_stylebox_override("panel", card_sb)
		var card_vbox := VBoxContainer.new()
		card.add_child(card_vbox)
		var subj := Label.new()
		var prefix: String = "● " if not letter.is_read else ""
		subj.text = prefix + letter.subject
		if _serif_font:
			subj.add_theme_font_override("font", _serif_font)
		subj.add_theme_font_size_override("font_size", 13)
		subj.add_theme_color_override("font_color", _SEAL_RED if not letter.is_read else _INK_PRIMARY)
		subj.clip_text = true
		card_vbox.add_child(subj)
		var meta := Label.new()
		meta.text = "Day %d" % letter.day_received
		meta.add_theme_font_size_override("font_size", 10)
		meta.add_theme_color_override("font_color", _INK_TERTIARY)
		card_vbox.add_child(meta)
		vbox.add_child(card)


# === Detail openers ===

func _open_detail(content: Control) -> void:
	if _current_detail != null:
		_current_detail.queue_free()
	_current_detail = content
	_current_detail.mouse_filter = Control.MOUSE_FILTER_STOP
	_detail_container.add_child(content)
	_detail_overlay.visible = true


func _close_detail() -> void:
	if _current_detail != null:
		_current_detail.queue_free()
		_current_detail = null
	_detail_overlay.visible = false


func _make_detail_panel(w: int, h: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = _PARCHMENT
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(32)
	sb.border_color = _DESK_LIGHT
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	return panel


func _make_close_button() -> Button:
	var btn := Button.new()
	btn.text = "Close"
	btn.pressed.connect(_close_detail)
	return btn


# --- Compose detail ---

func _open_compose() -> void:
	var panel := _make_detail_panel(700, 500)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	vbox.add_child(_make_label("Compose a Dispatch", 22, _INK_PRIMARY, true))

	# Escape actions per §35.12
	var escape_row := HBoxContainer.new()
	escape_row.add_theme_constant_override("separation", 8)
	vbox.add_child(escape_row)
	for action_name in ["Wait", "Go Dark", "Move Base"]:
		var btn := Button.new()
		btn.text = action_name
		btn.add_theme_font_size_override("font_size", 11)
		if action_name == "Wait":
			btn.pressed.connect(func(): _close_detail())
		else:
			btn.pressed.connect(func(): push_warning("%s not yet implemented" % action_name))
		escape_row.add_child(btn)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Action dropdown
	var action_row := HBoxContainer.new()
	vbox.add_child(action_row)
	action_row.add_child(_make_label("Action: ", 14, _INK_PRIMARY))
	var action_dd := OptionButton.new()
	action_dd.size_flags_horizontal = SIZE_EXPAND_FILL
	action_row.add_child(action_dd)

	# Target dropdown
	var target_row := HBoxContainer.new()
	vbox.add_child(target_row)
	target_row.add_child(_make_label("Target: ", 14, _INK_PRIMARY))
	var target_dd := OptionButton.new()
	target_dd.size_flags_horizontal = SIZE_EXPAND_FILL
	target_row.add_child(target_dd)

	# Cost label
	var cost_lbl := Label.new()
	cost_lbl.text = "..."
	cost_lbl.add_theme_font_size_override("font_size", 12)
	cost_lbl.add_theme_color_override("font_color", _INK_SECONDARY)
	vbox.add_child(cost_lbl)

	# Populate
	var action_defs: Array = []
	if _chain_node:
		var all_defs: Dictionary = _chain_node.get_all_action_definitions()
		for key: StringName in all_defs:
			action_defs.append(all_defs[key])
		action_defs.sort_custom(func(a: ActionDefinition, b: ActionDefinition) -> bool:
			return a.tier < b.tier or (a.tier == b.tier and a.display_name < b.display_name))
		for ad: ActionDefinition in action_defs:
			action_dd.add_item("[T%d] %s" % [ad.tier, ad.display_name])

	var targets: Array = []
	for pid: StringName in _world_registry.all_place_ids():
		var p: PlaceRecord = _world_registry.get_place(pid)
		target_dd.add_item("%s (%s)" % [p.name, p.province])
		targets.append({kind=&"place", ref=pid})
	for cid: StringName in _immortal_registry.all_character_ids():
		var c: CharacterRecord = _immortal_registry.get_character(cid)
		if c.chain_status != ChainStatusValues.NONE:
			continue
		target_dd.add_item("%s - %s" % [c.name, c.profession])
		targets.append({kind=&"character", ref=cid})

	# Prefill
	if ComposePrefill.target_ref != &"":
		for i in range(targets.size()):
			if targets[i].ref == ComposePrefill.target_ref:
				target_dd.selected = i
				break
		ComposePrefill.target_ref = &""

	# Cost update
	var update_cost := func(_idx: int = 0):
		if action_defs.is_empty() or targets.is_empty():
			return
		var ad: ActionDefinition = action_defs[action_dd.selected]
		var player: ImmortalRecord = _immortal_registry.get_player()
		var mult: float = PublicPositionValues.EXPOSURE_MULTIPLIER.get(player.character.public_position_tier, 1.0)
		cost_lbl.text = "Exposure ~%.1f  |  Bandwidth %d  |  Financial %d silver  |  ~%d days (estimate)" % [
			ad.baseline_exposure_cost * mult, ad.baseline_bandwidth_cost, ad.baseline_financial_cost, ad.baseline_time_days]
	action_dd.item_selected.connect(update_cost)
	target_dd.item_selected.connect(update_cost)
	update_cost.call(0)

	# Spacer + Seal button
	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	btn_row.add_child(_make_close_button())
	var btn_spacer := Control.new()
	btn_spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_row.add_child(btn_spacer)
	var seal_btn := Button.new()
	seal_btn.text = "Seal & Send"
	var seal_sb := StyleBoxFlat.new()
	seal_sb.bg_color = _SEAL_RED
	seal_sb.set_corner_radius_all(6)
	seal_sb.set_content_margin_all(14)
	seal_btn.add_theme_stylebox_override("normal", seal_sb)
	seal_btn.add_theme_color_override("font_color", _PARCHMENT)
	seal_btn.add_theme_font_size_override("font_size", 16)
	seal_btn.pressed.connect(func():
		if action_defs.is_empty() or targets.is_empty():
			return
		var ad: ActionDefinition = action_defs[action_dd.selected]
		var target: Dictionary = targets[target_dd.selected]
		var target_place: StringName = target.ref if target.kind == &"place" else _immortal_registry.get_character(target.ref).current_place if _immortal_registry.get_character(target.ref) else &""
		_action_node.dispatch(ad.id, target.ref, target_place)
		_close_detail())
	btn_row.add_child(seal_btn)

	_open_detail(panel)


# --- Inbox / Letter detail ---

func _open_inbox() -> void:
	var panel := _make_detail_panel(900, 600)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	vbox.add_child(_make_label("Inbox", 22, _INK_PRIMARY, true))
	if _inbox_node == null:
		vbox.add_child(_make_label("No inbox available.", 14, _INK_TERTIARY))
		vbox.add_child(_make_close_button())
		_open_detail(panel)
		return
	var active: Array = _inbox_node.get_active_letters()
	if active.is_empty():
		vbox.add_child(_make_label("No letters yet — your hosts and contacts will write when there's news.", 14, _INK_TERTIARY))
		vbox.add_child(_make_close_button())
		_open_detail(panel)
		return
	active.sort_custom(func(a: Letter, b: Letter) -> bool: return a.day_received > b.day_received)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list)
	for letter: Letter in active:
		var btn := Button.new()
		var prefix: String = "● " if not letter.is_read else "  "
		btn.text = "%s%s  —  Day %d" % [prefix, letter.subject, letter.day_received]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_color_override("font_color", _SEAL_RED if not letter.is_read else _INK_PRIMARY)
		btn.pressed.connect(_open_letter.bind(letter))
		list.add_child(btn)
	vbox.add_child(_make_close_button())
	_open_detail(panel)


func _open_letter(letter: Letter) -> void:
	if not letter.is_read and _inbox_node:
		_inbox_node.mark_read(letter.id)
	_close_detail()
	var panel := _make_detail_panel(800, 550)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	vbox.add_child(_make_label(letter.subject, 22, _INK_PRIMARY, true))
	var sender_name: String = "System"
	if letter.sender_kind == &"character":
		var c: CharacterRecord = _immortal_registry.get_character_record_any(letter.sender_ref)
		if c:
			sender_name = c.name
	vbox.add_child(_make_label("From: %s  ·  Day %d  ·  %s" % [sender_name, letter.day_received, letter.content_category], 12, _INK_TERTIARY))
	vbox.add_child(HSeparator.new())
	var body := RichTextLabel.new()
	body.text = letter.body
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.bbcode_enabled = false
	body.selection_enabled = true
	if _serif_font:
		body.add_theme_font_override("normal_font", _serif_font)
	body.add_theme_font_size_override("normal_font_size", 16)
	body.add_theme_color_override("default_color", _INK_PRIMARY)
	vbox.add_child(body)
	vbox.add_child(HSeparator.new())
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)
	if letter.action_ref != &"":
		var compose_btn := Button.new()
		compose_btn.text = "Compose action toward this subject"
		compose_btn.pressed.connect(func():
			ComposePrefill.target_ref = letter.action_ref
			_close_detail()
			_open_compose())
		btn_row.add_child(compose_btn)
	btn_row.add_child(_make_close_button())
	_open_detail(panel)


# --- Map detail ---

func _open_map() -> void:
	# Show a province/place selection list as the map detail
	var panel := _make_detail_panel(800, 550)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	vbox.add_child(_make_label("Map — Provinces & Places", 22, _INK_PRIMARY, true))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list)
	for pid: StringName in _world_registry.all_province_ids():
		var prov: ProvinceRecord = _world_registry.get_province(pid)
		var header := Label.new()
		header.text = "%s  (%s · %s · %s)" % [prov.name, prov.cultural_sphere, prov.terrain, prov.owning_kingdom if prov.owning_kingdom != &"" else "unaligned"]
		header.add_theme_font_size_override("font_size", 14)
		header.add_theme_color_override("font_color", _INK_PRIMARY)
		list.add_child(header)
		var places: Array = _world_registry.places_in_province(pid)
		for place: PlaceRecord in places:
			var btn := Button.new()
			btn.text = "    %s  |  %s  |  pop: %d" % [place.name, place.place_type, place.population]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.add_theme_font_size_override("font_size", 12)
			btn.add_theme_color_override("font_color", _INK_SECONDARY)
			btn.pressed.connect(func():
				_close_detail()
				_open_place_detail(place))
			list.add_child(btn)
	vbox.add_child(_make_close_button())
	_open_detail(panel)


func _open_place_detail(place: PlaceRecord) -> void:
	var panel := _make_detail_panel(600, 400)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	vbox.add_child(_make_label(place.name, 22, _INK_PRIMARY, true))
	var prov: ProvinceRecord = _world_registry.get_province(place.province)
	vbox.add_child(_make_label("Province: %s  |  Type: %s" % [prov.name if prov else str(place.province), place.place_type], 13, _INK_SECONDARY))
	vbox.add_child(_make_label("Population: %d  |  Infrastructure: %d" % [place.population, place.infrastructure_level], 13, _INK_SECONDARY))
	if not place.factional_balance.is_empty():
		var factions_text: String = ""
		for key: StringName in place.factional_balance:
			factions_text += "%s: %.0f%%  " % [key, place.factional_balance[key] * 100]
		vbox.add_child(_make_label("Factions: %s" % factions_text, 12, _INK_TERTIARY))
	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)
	var compose_btn := Button.new()
	compose_btn.text = "Compose action targeting %s" % place.name
	compose_btn.pressed.connect(func():
		ComposePrefill.target_ref = place.id
		_close_detail()
		_open_compose())
	btn_row.add_child(compose_btn)
	btn_row.add_child(_make_close_button())
	_open_detail(panel)


# --- Placeholder details ---

func _open_ledger() -> void:
	var panel := _make_detail_panel(600, 400)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	vbox.add_child(_make_label("Ledger", 22, _INK_PRIMARY, true))
	vbox.add_child(_make_label("Financial threads will appear here when the trade and economic systems are built (substep 11.16).", 14, _INK_TERTIARY))
	vbox.add_child(_make_label("No active financial threads.", 14, _INK_SECONDARY))
	vbox.add_child(_make_close_button())
	_open_detail(panel)


func _open_roster() -> void:
	var panel := _make_detail_panel(700, 500)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	vbox.add_child(_make_label("Roster", 22, _INK_PRIMARY, true))
	vbox.add_child(_make_label("Full roster interaction (audit, reassign, promote, sever) lands at substep 11.21.", 12, _INK_TERTIARY))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list)
	for cid: StringName in _immortal_registry.all_character_ids():
		var c: CharacterRecord = _immortal_registry.get_character(cid)
		if c.chain_status == ChainStatusValues.NONE:
			continue
		var entry := Label.new()
		entry.text = "%s  |  %s  |  %s  |  trust: %d  |  heat: %d" % [c.name, c.chain_status, c.current_place, c.trust_score, c.heat]
		entry.add_theme_font_size_override("font_size", 13)
		entry.add_theme_color_override("font_color", _INK_PRIMARY)
		list.add_child(entry)
	vbox.add_child(_make_close_button())
	_open_detail(panel)


func _open_memoirs() -> void:
	var panel := _make_detail_panel(700, 500)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	vbox.add_child(_make_label("Memoirs", 22, _INK_PRIMARY, true))
	vbox.add_child(_make_label("Full pattern library navigation (§35.11) lands at substep 11.21.", 12, _INK_TERTIARY))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list)
	if _memoirs_node:
		var lib = _memoirs_node.get_library(&"player")
		if lib:
			for p: Pattern in lib.patterns:
				var entry := Label.new()
				entry.text = "%s  |  %s  |  day %d  |  %d/%d  |  %s" % [p.id, p.category, p.learned_at_day, p.success_count, p.failure_count, p.staleness_state]
				entry.add_theme_font_size_override("font_size", 12)
				entry.add_theme_color_override("font_color", _INK_PRIMARY)
				list.add_child(entry)
		if lib == null or lib.patterns.is_empty():
			list.add_child(_make_label("No patterns learned yet.", 14, _INK_TERTIARY))
	vbox.add_child(_make_close_button())
	_open_detail(panel)


func _open_codebook() -> void:
	var panel := _make_detail_panel(600, 400)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	vbox.add_child(_make_label("Codebook", 22, _INK_PRIMARY, true))
	vbox.add_child(_make_label("Encrypted correspondence with high-value contacts. Cipher acquisition lands when the Codebook mechanic ships at substep 11.18.", 14, _INK_TERTIARY))
	vbox.add_child(_make_label("No ciphers yet.", 14, _INK_SECONDARY))
	vbox.add_child(_make_close_button())
	_open_detail(panel)


func _open_inflight() -> void:
	var panel := _make_detail_panel(700, 450)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	vbox.add_child(_make_label("In-flight Dispatches", 22, _INK_PRIMARY, true))
	if _action_node == null:
		vbox.add_child(_make_label("No action mechanic.", 14, _INK_TERTIARY))
		vbox.add_child(_make_close_button())
		_open_detail(panel)
		return
	var schemes: Array = _action_node.get_active_schemes()
	if schemes.is_empty():
		vbox.add_child(_make_label("No schemes in flight.", 14, _INK_TERTIARY))
	else:
		for s: SchemeRecord in schemes:
			var entry := Label.new()
			entry.text = "%s  |  %s → %s  |  phase: %s  |  Lt: %s  |  Coord: %s  |  Op: %s" % [
				s.action_type, s.target_ref, s.target_place_ref, s.current_phase,
				s.assigned_lieutenant_id if s.assigned_lieutenant_id != &"" else "-",
				s.assigned_coordinator_id if s.assigned_coordinator_id != &"" else "-",
				s.assigned_operative_id if s.assigned_operative_id != &"" else "-"]
			entry.add_theme_font_size_override("font_size", 12)
			entry.add_theme_color_override("font_color", _INK_PRIMARY)
			vbox.add_child(entry)
	vbox.add_child(_make_close_button())
	_open_detail(panel)


func _update_speed() -> void:
	if _time_keeper.is_paused:
		_speed_label.text = "|| Paused"
	else:
		_speed_label.text = "> %s" % _time_keeper.current_speed


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_pause"):
		_time_keeper.set_paused(not _time_keeper.is_paused, &"player")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_x1"):
		_time_keeper.set_speed(SpeedValues.X1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_x2"):
		_time_keeper.set_speed(SpeedValues.X2)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_x4"):
		_time_keeper.set_speed(SpeedValues.X4)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_x16"):
		_time_keeper.set_speed(SpeedValues.X16)
		get_viewport().set_input_as_handled()
