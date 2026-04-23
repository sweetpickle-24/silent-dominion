extends Control
## Row of sealed-envelope tokens showing every action awaiting resolution.
##
## One token per pending `action_resolution` task in the `Scheduler`.
## Each token carries:
##   - A cream parchment envelope with a small red wax dot.
##   - Countdown text beneath ("8d") pulled from the scheduler's fire_day.
##   - A tooltip with the action display name + target name.
##
## Listens to EventBus.action_issued / action_resolved and GameClock.day_passed
## so the tray stays in sync without any manual refresh calls from the table.
##
## Visuals match the rest of the table (StyleBoxFlat parchment + wax).

# --- Visual constants --------------------------------------------------------

const ENVELOPE_SIZE: Vector2       = Vector2(72.0, 46.0)
const ENVELOPE_GAP: float          = 10.0
const TOKEN_ROTATION_RANGE: float  = 0.06        # +/- radians
const HEADER_HEIGHT: float         = 18.0

const COLOR_PARCHMENT: Color       = Color(0.94, 0.87, 0.72, 1.0)
const COLOR_PARCHMENT_BORDER: Color = Color(0.55, 0.42, 0.28, 0.6)
const COLOR_WAX: Color             = Color(0.55, 0.08, 0.08, 1.0)
const COLOR_WAX_HIGHLIGHT: Color   = Color(0.78, 0.18, 0.18, 1.0)
const COLOR_INK: Color             = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color       = Color(0.22, 0.14, 0.06, 0.55)

# --- Nodes -------------------------------------------------------------------

var _header_label: Label
var _row: HBoxContainer
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


# --- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	_rng.seed = 0xB1A7E5                    # stable rotations across refreshes
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_chrome()
	_subscribe()
	_refresh()


func _build_chrome() -> void:
	_header_label = Label.new()
	_header_label.text = "AWAITING  REPLY"
	_header_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
	_header_label.add_theme_font_size_override("font_size", 10)
	_header_label.add_theme_constant_override("outline_size", 0)
	_header_label.mouse_filter = MOUSE_FILTER_IGNORE
	_header_label.anchor_left = 0.0
	_header_label.anchor_right = 1.0
	_header_label.offset_top = 0.0
	_header_label.offset_bottom = HEADER_HEIGHT
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_header_label)

	_row = HBoxContainer.new()
	_row.mouse_filter = MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_END
	_row.add_theme_constant_override("separation", int(ENVELOPE_GAP))
	_row.anchor_left = 0.0
	_row.anchor_right = 1.0
	_row.anchor_top = 0.0
	_row.anchor_bottom = 1.0
	_row.offset_top = HEADER_HEIGHT + 4.0
	add_child(_row)


func _subscribe() -> void:
	EventBus.action_issued.connect(_on_action_issued)
	EventBus.action_resolved.connect(_on_action_resolved)
	GameClock.day_passed.connect(_on_day_passed)


# --- Event hooks -------------------------------------------------------------

func _on_action_issued(_action_id: StringName, _payload: Dictionary) -> void:
	_refresh()


func _on_action_resolved(_action_id: StringName, _result: Dictionary) -> void:
	_refresh()


func _on_day_passed(_y: int, _m: int, _d: int) -> void:
	# Countdown on each existing token drifts every game-day.
	_refresh()


# --- Refresh -----------------------------------------------------------------

func _refresh() -> void:
	for child in _row.get_children():
		child.queue_free()

	var pending: Array = _gather_pending()
	if pending.is_empty():
		_header_label.text = "NO  MATTERS  AWAITING  REPLY"
		return

	_header_label.text = "AWAITING  REPLY  (%d)" % pending.size()

	# Sort so the soonest-resolving token is rightmost (closest to the
	# time dial above it, reading order left->right = furthest->soonest).
	pending.sort_custom(func(a, b): return int(a["fire_day"]) > int(b["fire_day"]))

	var today: int = GameClock.absolute_day()
	for entry in pending:
		var token: Control = _build_token(entry, today)
		_row.add_child(token)


func _gather_pending() -> Array:
	var out: Array = []
	for task in Scheduler.snapshot():
		var desc: Dictionary = task.get("descriptor", {})
		if String(desc.get("kind", "")) != String(Actions.TASK_KIND):
			continue
		out.append({
			"fire_day":  int(task.get("fire_day", 0)),
			"action_id": StringName(String(desc.get("action_id", ""))),
			"target_id": String(desc.get("target_id", "")),
		})
	return out


# --- Token construction ------------------------------------------------------

func _build_token(entry: Dictionary, today: int) -> Control:
	var action_id: StringName = entry["action_id"]
	var target_id: String     = entry["target_id"]
	var fire_day: int         = int(entry["fire_day"])
	var days_left: int        = max(0, fire_day - today)

	var def: ActionDefinition = Actions.get_definition(action_id)
	var action_name: String = def.display_name if def != null else String(action_id)
	var target_name: String = _pretty_target(def, target_id)

	var holder: Control = Control.new()
	holder.custom_minimum_size = Vector2(ENVELOPE_SIZE.x, ENVELOPE_SIZE.y + 18.0)
	holder.mouse_filter = MOUSE_FILTER_STOP
	holder.tooltip_text = "%s — %s\nresolves in %d %s" % [
		action_name,
		target_name,
		days_left,
		("day" if days_left == 1 else "days"),
	]

	var envelope: Panel = _make_envelope()
	envelope.position = Vector2.ZERO
	envelope.size = ENVELOPE_SIZE
	envelope.pivot_offset = ENVELOPE_SIZE * 0.5
	envelope.rotation = _rng.randf_range(-TOKEN_ROTATION_RANGE, TOKEN_ROTATION_RANGE)
	holder.add_child(envelope)

	var seal: Panel = _make_seal()
	seal.size = Vector2(16, 16)
	seal.position = ENVELOPE_SIZE * 0.5 - seal.size * 0.5
	seal.rotation = envelope.rotation
	seal.pivot_offset = seal.size * 0.5
	holder.add_child(seal)

	var count: Label = Label.new()
	count.text = "%dd" % days_left
	count.add_theme_color_override("font_color", COLOR_INK)
	count.add_theme_font_size_override("font_size", 11)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.anchor_left = 0.0
	count.anchor_right = 1.0
	count.offset_top = ENVELOPE_SIZE.y + 2.0
	count.offset_bottom = ENVELOPE_SIZE.y + 18.0
	count.mouse_filter = MOUSE_FILTER_IGNORE
	holder.add_child(count)

	# Subtle hover lift, so the tray feels like a physical pile of papers.
	holder.mouse_entered.connect(func() -> void: _lift(envelope, seal, true))
	holder.mouse_exited.connect(func() -> void: _lift(envelope, seal, false))

	return holder


func _make_envelope() -> Panel:
	var p: Panel = Panel.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = COLOR_PARCHMENT
	sb.border_color = COLOR_PARCHMENT_BORDER
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 2)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = MOUSE_FILTER_IGNORE
	return p


func _make_seal() -> Panel:
	var p: Panel = Panel.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = COLOR_WAX
	sb.border_color = COLOR_WAX_HIGHLIGHT
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 2
	sb.shadow_offset = Vector2(0, 1)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = MOUSE_FILTER_IGNORE
	return p


func _lift(envelope: Panel, seal: Panel, up: bool) -> void:
	var target_offset: float = -3.0 if up else 0.0
	if Prefs.reduced_motion:
		envelope.position.y = target_offset
		seal.position.y = ENVELOPE_SIZE.y * 0.5 - 8.0 + target_offset
		return
	var t: Tween = create_tween().set_parallel(true)
	t.tween_property(envelope, "position:y", target_offset, 0.12) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(seal, "position:y",
			ENVELOPE_SIZE.y * 0.5 - 8.0 + target_offset, 0.12) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# --- Helpers -----------------------------------------------------------------

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
