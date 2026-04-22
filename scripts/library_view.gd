extends Control
## Full-screen overlay for the fingerprint library per §8.12.
##
## What the player has learned about the other societies operating
## in their world. Each society is a row:
##   - the era-appropriate name for our knowledge of them
##   - a confirmation phrase (unknown / glimpsed / provisional / confirmed / catalogued)
##   - a one-line summary of their strongholds we are aware of
##   - a small band of their recent operations we have broken open
##
## Societies the player has not yet touched at all are listed as
## "An unrecognised hand, somewhere." — a reminder the library is
## partial, not exhaustive. We deliberately do not render them as
## named rows; that would leak ground truth.

signal closed

const COLOR_DIMMER: Color         = Color(0, 0, 0, 0.62)
const COLOR_PARCHMENT: Color      = Color(0.96, 0.92, 0.82, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.55, 0.42, 0.28, 0.7)
const COLOR_INK: Color            = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.22, 0.14, 0.06, 0.65)
const COLOR_ACCENT: Color         = Color(0.44, 0.36, 0.14, 1.0)
const COLOR_WAX: Color            = Color(0.55, 0.08, 0.08, 1.0)

const COLOR_TIER_UNKNOWN: Color    = Color(0.62, 0.18, 0.12, 1.0)
const COLOR_TIER_GLIMPSED: Color   = Color(0.62, 0.42, 0.14, 1.0)
const COLOR_TIER_PROVISIONAL: Color = Color(0.52, 0.40, 0.18, 1.0)
const COLOR_TIER_CONFIRMED: Color  = Color(0.32, 0.30, 0.52, 1.0)
const COLOR_TIER_CATALOGUED: Color = Color(0.24, 0.42, 0.22, 1.0)

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

	Fingerprints.society_identified.connect(_on_identified)
	Fingerprints.op_level_changed.connect(_on_level_changed)


func _exit_tree() -> void:
	if Fingerprints.society_identified.is_connected(_on_identified):
		Fingerprints.society_identified.disconnect(_on_identified)
	if Fingerprints.op_level_changed.is_connected(_on_level_changed):
		Fingerprints.op_level_changed.disconnect(_on_level_changed)


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


# --- Chrome -----------------------------------------------------------------

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
	_sheet.offset_left = -420.0
	_sheet.offset_right = 420.0
	_sheet.offset_top = -320.0
	_sheet.offset_bottom = 320.0
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


# --- Render -----------------------------------------------------------------

func _on_identified(_sid: StringName, _confirmation: int) -> void:
	call_deferred("_render")


func _on_level_changed(_op_id: String, _level: int) -> void:
	call_deferred("_render")


func _render() -> void:
	_clear_body()

	_body_vbox.add_child(_make_title("Fingerprint Library"))
	_body_vbox.add_child(_make_subtitle(_subtitle_text()))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 480.0
	_body_vbox.add_child(scroll)

	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	# Only show societies we have touched at all. Untouched ones are
	# rolled into the summary line below.
	var any_known: bool = false
	for sid in _sorted_known_ids():
		var soc: RivalSociety = Rivals.get_society(sid)
		if soc == null:
			continue
		any_known = true
		list.add_child(_build_society_row(soc))

	if not any_known:
		var empty: Label = Label.new()
		empty.text = (
			"The library is empty. No hand has yet left enough of a mark "
			+ "in a region you are watching for the archivists to build a "
			+ "file on them."
		)
		empty.add_theme_color_override("font_color", COLOR_INK_MUTED)
		empty.add_theme_font_size_override("font_size", 12)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(empty)

	var unknown_line: Label = Label.new()
	unknown_line.text = _unknown_line_text()
	unknown_line.add_theme_color_override("font_color", COLOR_INK_MUTED)
	unknown_line.add_theme_font_size_override("font_size", 11)
	unknown_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_vbox.add_child(unknown_line)

	# Known immortals (§5.5). Rendered only when at least one peer
	# has surfaced in the correspondence — otherwise silence.
	var peers: Array[OtherImmortal] = Immortals.known_immortals()
	if not peers.is_empty():
		_body_vbox.add_child(_make_peers_heading())
		for im in peers:
			_body_vbox.add_child(_build_peer_row(im))

	_body_vbox.add_child(_make_close_button())


func _sorted_known_ids() -> Array[StringName]:
	# Confirmation desc, then alpha for stability.
	var ids: Array[StringName] = []
	for s in Rivals.all_societies():
		if Fingerprints.confirmation_for(s.id) > 0 \
				or _has_any_investigated_op(s.id):
			ids.append(s.id)
	ids.sort_custom(func(a, b):
		var ca: int = Fingerprints.confirmation_for(a)
		var cb: int = Fingerprints.confirmation_for(b)
		if ca == cb:
			return String(a) < String(b)
		return ca > cb)
	return ids


func _has_any_investigated_op(sid: StringName) -> bool:
	for op in Rivals.op_log:
		if String(op.get("rival_signature", "")) != String(sid):
			continue
		if Fingerprints.level_for(String(op.get("op_id", ""))) \
				> Fingerprints.LEVEL_SIGNAL:
			return true
	return false


func _build_society_row(soc: RivalSociety) -> Control:
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
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", sb)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	row.add_child(vbox)

	var conf: int = Fingerprints.confirmation_for(soc.id)
	var tier: StringName = _tier_for_confirmation(conf)
	var tier_color: Color = _tier_color(tier)

	# Header: name + tier chip.
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	var name_label: Label = Label.new()
	name_label.text = _name_for_tier(soc, tier)
	name_label.add_theme_color_override("font_color", COLOR_INK)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	var chip: Label = Label.new()
	chip.text = _tier_label(tier)
	chip.add_theme_color_override("font_color", tier_color)
	chip.add_theme_font_size_override("font_size", 11)
	header.add_child(chip)

	# Philosophy is visible only once confirmed. Before that we give
	# a generic hint based on the ops we've seen.
	var philo_label: Label = Label.new()
	philo_label.text = _philosophy_for_tier(soc, tier)
	philo_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
	philo_label.add_theme_font_size_override("font_size", 12)
	philo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(philo_label)

	# Regions: kingdoms where we have broken open at least one op of
	# theirs to level >= Actor. Blind to their strongholds below the
	# confirmed tier.
	var regions_text: String = _regions_line(soc, tier)
	if not regions_text.is_empty():
		var reg: Label = Label.new()
		reg.text = regions_text
		reg.add_theme_color_override("font_color", COLOR_INK_MUTED)
		reg.add_theme_font_size_override("font_size", 11)
		reg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(reg)

	# Recent operations we have attribution on.
	var attributed: Array[Dictionary] = _attributed_ops(soc.id, 4)
	if not attributed.is_empty():
		var ops_heading: Label = Label.new()
		ops_heading.text = "OPERATIONS WE HAVE READ"
		ops_heading.add_theme_color_override("font_color", COLOR_INK_MUTED)
		ops_heading.add_theme_font_size_override("font_size", 10)
		vbox.add_child(ops_heading)
		for op in attributed:
			var ln: Label = Label.new()
			ln.text = "   · %s" % String(op.get("headline", ""))
			ln.add_theme_color_override("font_color", COLOR_INK)
			ln.add_theme_font_size_override("font_size", 11)
			ln.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(ln)

	return row


# --- Content helpers --------------------------------------------------------

func _subtitle_text() -> String:
	var total: int = Rivals.all_societies().size()
	var known: int = 0
	for s in Rivals.all_societies():
		if Fingerprints.confirmation_for(s.id) > 0 or _has_any_investigated_op(s.id):
			known += 1
	if known == 0:
		return "We have no named rivals on file. Every anomaly still reads as weather."
	return "%d of %d hands touched. What follows is what the archive can defend." % [known, total]


func _unknown_line_text() -> String:
	var unknown: int = 0
	for s in Rivals.all_societies():
		if Fingerprints.confirmation_for(s.id) == 0 and not _has_any_investigated_op(s.id):
			unknown += 1
	if unknown == 0:
		return ""
	if unknown == 1:
		return "One unrecognised hand, somewhere, may still be moving without a file."
	return "%d unrecognised hands, somewhere, may still be moving without a file." % unknown


func _tier_for_confirmation(c: int) -> StringName:
	if c >= 85:
		return &"catalogued"
	if c >= 65:
		return &"confirmed"
	if c >= 40:
		return &"provisional"
	if c >= 15:
		return &"glimpsed"
	return &"unknown"


func _tier_label(tier: StringName) -> String:
	match tier:
		&"unknown":     return "UNRECOGNISED"
		&"glimpsed":    return "GLIMPSED"
		&"provisional": return "PROVISIONAL"
		&"confirmed":   return "CONFIRMED"
		&"catalogued":  return "CATALOGUED"
	return ""


func _tier_color(tier: StringName) -> Color:
	match tier:
		&"unknown":     return COLOR_TIER_UNKNOWN
		&"glimpsed":    return COLOR_TIER_GLIMPSED
		&"provisional": return COLOR_TIER_PROVISIONAL
		&"confirmed":   return COLOR_TIER_CONFIRMED
		&"catalogued":  return COLOR_TIER_CATALOGUED
	return COLOR_INK_MUTED


## Before CONFIRMED the society is referenced generically; at and
## above CONFIRMED we name them. This mirrors §8.12's attribution
## gate and keeps fog honest.
func _name_for_tier(soc: RivalSociety, tier: StringName) -> String:
	match tier:
		&"confirmed", &"catalogued":
			return soc.display_name
		&"provisional":
			return "A persistent organisation (profile open)"
		&"glimpsed":
			return "An unnamed hand (a sliver of a file)"
	return "An unnamed hand"


func _philosophy_for_tier(soc: RivalSociety, tier: StringName) -> String:
	match tier:
		&"confirmed", &"catalogued":
			return soc.philosophy
		&"provisional":
			return "Operating consistently across multiple years. Intent is readable from methods; name is not yet."
		&"glimpsed":
			return "A single incident, read carefully enough to know it was deliberate."
	return "No file yet. The archivists have nothing to defend."


func _regions_line(soc: RivalSociety, tier: StringName) -> String:
	# Only regions we have broken open at least one op in, regardless
	# of tier. Strongholds are named only at CONFIRMED+.
	var kingdoms_touched: Dictionary = {}  # kid -> true
	for op in Rivals.op_log:
		if String(op.get("rival_signature", "")) != String(soc.id):
			continue
		if Fingerprints.level_for(String(op.get("op_id", ""))) \
				< Fingerprints.LEVEL_ACTOR:
			continue
		kingdoms_touched[String(op.get("kingdom_id", ""))] = true
	if kingdoms_touched.is_empty():
		return ""
	var names: Array[String] = []
	for kid in kingdoms_touched:
		var k: Kingdom = WorldData.get_kingdom(String(kid))
		names.append(k.kingdom_name if k != null else String(kid))
	names.sort()
	var where: String = ", ".join(names)
	match tier:
		&"confirmed", &"catalogued":
			var stronghold_names: Array[String] = []
			for kid in soc.stronghold_kingdoms:
				var k2: Kingdom = WorldData.get_kingdom(kid)
				stronghold_names.append(k2.kingdom_name if k2 != null else kid)
			return "Seen in: %s.  Library notes strongholds in: %s." \
				% [where, ", ".join(stronghold_names)]
	return "Seen in: %s." % where


func _attributed_ops(sid: StringName, limit: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# Walk newest-first so the list reads as "what we just broke open."
	for i in range(Rivals.op_log.size() - 1, -1, -1):
		var op: Dictionary = Rivals.op_log[i]
		if String(op.get("rival_signature", "")) != String(sid):
			continue
		if Fingerprints.level_for(String(op.get("op_id", ""))) \
				< Fingerprints.LEVEL_ACTOR:
			continue
		out.append(op)
		if out.size() >= limit:
			break
	return out


# --- Visual helpers ---------------------------------------------------------

func _make_title(text: String) -> Control:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_INK)
	l.add_theme_font_size_override("font_size", 22)
	return l


func _make_subtitle(text: String) -> Control:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	l.add_theme_font_size_override("font_size", 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _make_close_button() -> Control:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_END
	var btn: Button = Button.new()
	btn.text = "Close"
	btn.flat = true
	btn.add_theme_color_override("font_color", COLOR_ACCENT)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(close)
	hbox.add_child(btn)
	return hbox


func _clear_body() -> void:
	for c in _body_vbox.get_children():
		c.queue_free()


func _make_peers_heading() -> Control:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var hr: Label = Label.new()
	hr.text = "PEERS"
	hr.add_theme_color_override("font_color", COLOR_INK_MUTED)
	hr.add_theme_font_size_override("font_size", 11)
	v.add_child(hr)
	var blurb: Label = Label.new()
	blurb.text = "Other immortals whose hand the library has confirmed. Relationships are state, not opinion."
	blurb.add_theme_color_override("font_color", COLOR_INK_MUTED)
	blurb.add_theme_font_size_override("font_size", 11)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(blurb)
	return v


func _build_peer_row(im: OtherImmortal) -> Control:
	var row: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.94, 0.88, 0.74, 0.8)
	sb.border_color = Color(0.42, 0.28, 0.14, 0.45)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", sb)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	row.add_child(vbox)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var soc: RivalSociety = Rivals.get_society(im.society_id)
	var title: Label = Label.new()
	title.text = "%s — behind %s" % [im.epithet, soc.display_name if soc != null else "an unlisted society"]
	title.add_theme_color_override("font_color", COLOR_INK)
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var chip: Label = Label.new()
	chip.text = _relationship_label(im.relationship)
	chip.add_theme_color_override("font_color", _relationship_color(im.relationship))
	chip.add_theme_font_size_override("font_size", 11)
	header.add_child(chip)

	var disp: Label = Label.new()
	disp.text = im.disposition
	disp.add_theme_color_override("font_color", COLOR_INK_MUTED)
	disp.add_theme_font_size_override("font_size", 11)
	disp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(disp)

	if not im.is_alive() or im.relationship == &"dead":
		var note: Label = Label.new()
		note.text = "Founder posthumous. Their society runs on inheritance alone."
		note.add_theme_color_override("font_color", COLOR_INK_MUTED)
		note.add_theme_font_size_override("font_size", 11)
		vbox.add_child(note)

	return row


func _relationship_label(rel: StringName) -> String:
	match rel:
		&"unknown":    return "UNRECOGNISED"
		&"aware":      return "KNOWN TO EACH OTHER"
		&"in_contact": return "IN CONTACT"
		&"truce":      return "TRUCE"
		&"cold":       return "CHANNEL COLD"
		&"war":        return "OPEN WAR"
		&"dead":       return "DEAD BY OUR HAND"
		&"escaped":    return "ESCAPED OUR HAND"
	return ""


func _relationship_color(rel: StringName) -> Color:
	match rel:
		&"truce":      return COLOR_TIER_CATALOGUED
		&"in_contact": return COLOR_TIER_CONFIRMED
		&"aware":      return COLOR_TIER_PROVISIONAL
		&"cold":       return COLOR_INK_MUTED
		&"war":        return COLOR_TIER_UNKNOWN
		&"escaped":    return Color(0.55, 0.08, 0.08, 1.0)
		&"dead":       return Color(0.24, 0.42, 0.22, 1.0)
	return COLOR_INK_MUTED
