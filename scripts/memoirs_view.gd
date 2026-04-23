extends Control
## Full-screen overlay for the Memoirs object on the table.
##
## The long tail of the inbox. Every letter the player has ever
## received is grouped by year (newest year first), and each row in a
## year is a compact entry (date, sender, subject) the player can
## click to reopen the full parchment via LetterView. The inbox itself
## only shows unread letters on top; Memoirs is the archive.
##
## No numbers, no metrics — just dates and names. This is the "I want
## to re-read what X told me two winters ago" panel.

signal closed
signal actor_link_clicked(actor_id: StringName)
signal codebook_link_clicked(anchor: StringName)

const LetterViewScene: PackedScene = preload("res://scenes/inbox/letter_view.tscn")

# --- Visual tokens -----------------------------------------------------------

const COLOR_DIMMER: Color         = Color(0, 0, 0, 0.62)
const COLOR_PARCHMENT: Color      = Color(0.96, 0.92, 0.82, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.55, 0.42, 0.28, 0.7)
const COLOR_INK: Color            = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.22, 0.14, 0.06, 0.65)
const COLOR_ACCENT: Color         = Color(0.44, 0.36, 0.14, 1.0)
const COLOR_WAX: Color            = Color(0.55, 0.08, 0.08, 1.0)

# --- Nodes -------------------------------------------------------------------

var _dimmer: ColorRect
var _sheet: PanelContainer
var _content: VBoxContainer

# While a letter view is open we don't close memoirs on its close.
var _child_letter_view: Control


# --- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	_build_dimmer()
	_build_sheet()
	_render()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, Prefs.anim_duration(0.18))

	if EraTheme != null:
		EraTheme.register_view(self)

	Inbox.letters_changed.connect(_render)
	Memoirs.pattern_added.connect(_on_memoirs_changed)
	Memoirs.pattern_refreshed.connect(_on_memoirs_refreshed)
	Memoirs.pattern_flagged_unverified.connect(_on_memoirs_changed)
	Automations.rule_added.connect(_on_memoirs_changed)
	Automations.rule_changed.connect(_on_memoirs_changed)
	Automations.rule_removed.connect(_on_memoirs_changed)


func _on_memoirs_changed(_id: StringName) -> void:
	_render()


func _on_memoirs_refreshed(_id: StringName, _success: bool) -> void:
	_render()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _child_letter_view == null:
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
	_dimmer.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT \
		   and _child_letter_view == null:
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

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_sheet.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title: Label = Label.new()
	title.text = "The Memoirs"
	title.add_theme_color_override("font_color", COLOR_INK)
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var sub: Label = Label.new()
	sub.text = "Every letter that has arrived on the table, from the most recent season backward. Unread letters carry a wax dot."
	sub.add_theme_color_override("font_color", COLOR_INK_MUTED)
	sub.add_theme_font_size_override("font_size", 12)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(sub)

	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("color", COLOR_PARCHMENT_EDGE)
	root.add_child(sep)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 4)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)

	var close_btn: Button = Button.new()
	close_btn.text = "Set aside"
	close_btn.custom_minimum_size.y = 30.0
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_color_override("font_color", COLOR_INK)
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.pressed.connect(func() -> void: close())
	root.add_child(close_btn)


# --- Render ------------------------------------------------------------------

func _render() -> void:
	for c in _content.get_children():
		c.queue_free()

	# §D4 Memoirs-as-living-help. Show a one-shot welcome card the
	# first time the player opens Memoirs after the first pattern is
	# recorded. Subsequent openings skip the card.
	if Unlocks != null and Unlocks.should_show_welcome(Unlocks.ID_MEMOIRS):
		_content.add_child(_build_welcome_card())
		Unlocks.mark_welcome_shown(Unlocks.ID_MEMOIRS)

	_render_standing_orders()
	_render_known_profiles()
	_render_system_reference()

	if Inbox.letters.is_empty():
		_content.add_child(_empty_state())
		return

	# Sort letters by (year desc, month desc, day desc). Letter.date is a
	# GameDate whose year is stored as a positive BCE number, so a smaller
	# year value is actually later in game time.
	var sorted: Array = Inbox.letters.duplicate()
	sorted.sort_custom(_sort_newest_first)

	var current_year: int = -9999
	for l in sorted:
		var year: int = l.date.year if l.date != null else 0
		if year != current_year:
			current_year = year
			_content.add_child(_year_heading(year))
		_content.add_child(_letter_row(l))


# --- Standing orders (§13.2) ------------------------------------------------

func _render_standing_orders() -> void:
	var rs: Array[AutomationRule] = Automations.all_rules()
	if rs.is_empty():
		return
	var section: VBoxContainer = VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	_content.add_child(section)

	var heading: Label = Label.new()
	heading.text = "STANDING ORDERS"
	heading.add_theme_color_override("font_color", COLOR_ACCENT)
	heading.add_theme_font_size_override("font_size", 11)
	section.add_child(heading)

	for r in rs:
		section.add_child(_rule_row(r))

	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("color", COLOR_PARCHMENT_EDGE)
	section.add_child(sep)


func _rule_row(r: AutomationRule) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 2)
	row.add_child(left)

	var head_text: String = _rule_headline(r)
	var head: Label = Label.new()
	head.text = head_text
	head.add_theme_color_override("font_color", COLOR_INK)
	head.add_theme_font_size_override("font_size", 13)
	left.add_child(head)

	var meta: Label = Label.new()
	var bits: Array[String] = []
	bits.append("every %d months" % r.cadence_months)
	bits.append("%d fired, %d landed" % [r.fire_count, r.success_count])
	if r.paused:
		bits.append("stood down — %s" % _reason_phrase(r.paused_reason))
	meta.text = " · ".join(bits)
	meta.add_theme_color_override(
		"font_color",
		Color(0.58, 0.22, 0.12, 1.0) if r.paused else COLOR_INK_MUTED
	)
	meta.add_theme_font_size_override("font_size", 11)
	left.add_child(meta)

	var controls: HBoxContainer = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	if r.paused:
		var resume_btn: Button = Button.new()
		resume_btn.text = "Resume"
		resume_btn.focus_mode = Control.FOCUS_NONE
		resume_btn.custom_minimum_size.y = 24.0
		var rid_r: StringName = r.id
		resume_btn.pressed.connect(func() -> void: Automations.resume(rid_r))
		controls.add_child(resume_btn)
	else:
		var pause_btn: Button = Button.new()
		pause_btn.text = "Stand down"
		pause_btn.focus_mode = Control.FOCUS_NONE
		pause_btn.custom_minimum_size.y = 24.0
		var rid_p: StringName = r.id
		pause_btn.pressed.connect(func() -> void: Automations.pause(rid_p, &"by_hand"))
		controls.add_child(pause_btn)

	var cancel_btn: Button = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.custom_minimum_size.y = 24.0
	var rid_c: StringName = r.id
	cancel_btn.pressed.connect(func() -> void: Automations.cancel(rid_c))
	controls.add_child(cancel_btn)
	row.add_child(controls)

	return row


func _rule_headline(r: AutomationRule) -> String:
	var action_name: String = _pretty_action(r.action_id)
	match r.scope:
		AutomationRule.Scope.ACTOR:
			var a: Actor = Actors.get_actor(r.target_actor_id)
			var name: String = a.display_name() if a != null else String(r.target_actor_id)
			return "%s → %s" % [action_name, name]
		AutomationRule.Scope.KINGDOM:
			return "%s → anyone matching in %s" % [action_name, _kingdom_name(r.kingdom_id)]
		AutomationRule.Scope.REGION:
			return "%s → across the region" % action_name
	return action_name


func _reason_phrase(reason: StringName) -> String:
	match String(reason):
		"by_hand":          return "by your hand"
		"pattern_gone":     return "profile lost"
		"pattern_stale":    return "profile grown stale"
		"religion_opaque":  return "faith not yet studied"
		"losses_mounting":  return "three failures running"
	return String(reason)


func _pretty_action(action_id: StringName) -> String:
	var def: ActionDefinition = Actions.get_definition(action_id)
	if def != null and def.display_name != "":
		return def.display_name
	return String(action_id).replace("_", " ")


func _kingdom_name(kid: String) -> String:
	var k: Kingdom = WorldData.get_kingdom(kid)
	return k.kingdom_name if k != null else kid


# --- Known profiles (§13 / §30) ---------------------------------------------

func _render_known_profiles() -> void:
	var ps: Array[MemoirPattern] = Memoirs.all_patterns()
	var section: VBoxContainer = VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	_content.add_child(section)

	var heading: Label = Label.new()
	heading.text = "KNOWN PROFILES"
	heading.add_theme_color_override("font_color", COLOR_ACCENT)
	heading.add_theme_font_size_override("font_size", 11)
	section.add_child(heading)

	if ps.is_empty():
		var empty: Label = Label.new()
		empty.text = "Nothing committed to pattern yet. First encounters still come on their own terms."
		empty.add_theme_color_override("font_color", COLOR_INK_MUTED)
		empty.add_theme_font_size_override("font_size", 12)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		section.add_child(empty)
	else:
		for p in ps:
			section.add_child(_profile_row(p))

	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("color", COLOR_PARCHMENT_EDGE)
	section.add_child(sep)


func _profile_row(p: MemoirPattern) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 2)
	row.add_child(left)

	var head: Label = Label.new()
	head.text = p.headline
	head.add_theme_color_override("font_color", COLOR_INK)
	head.add_theme_font_size_override("font_size", 13)
	left.add_child(head)

	var meta: Label = Label.new()
	var bits: Array[String] = []
	bits.append("%d samples" % p.samples)
	bits.append(p.confidence_phrase())
	if p.culture_tag != &"":
		bits.append(Languages.display_name(p.culture_tag))
	if p.unverified:
		bits.append("unverified")
	else:
		bits.append("fresh")
	meta.text = " · ".join(bits)
	meta.add_theme_color_override(
		"font_color",
		Color(0.58, 0.38, 0.16, 1.0) if p.unverified else COLOR_INK_MUTED
	)
	meta.add_theme_font_size_override("font_size", 11)
	left.add_child(meta)

	var right: VBoxContainer = VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.custom_minimum_size.x = 180.0
	row.add_child(right)

	var cat: Label = Label.new()
	cat.text = String(p.category).replace("_", " ")
	cat.add_theme_color_override("font_color", COLOR_INK_MUTED)
	cat.add_theme_font_size_override("font_size", 11)
	cat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(cat)

	# §13.3 regional dispatch. Confident, fresh, culture-tagged
	# patterns can be stood up as a kingdom-wide standing order in
	# their own culture region. The list of available kingdoms is
	# whichever kingdoms speak the pattern's culture.
	if not p.unverified and p.samples >= 3:
		var kingdoms_for_culture: Array[String] = _kingdoms_matching_culture(p.culture_tag)
		if not kingdoms_for_culture.is_empty():
			var opt: OptionButton = OptionButton.new()
			opt.focus_mode = Control.FOCUS_NONE
			opt.custom_minimum_size.y = 22.0
			opt.add_theme_font_size_override("font_size", 11)
			opt.add_item("Delegate across…", 0)
			for i in range(kingdoms_for_culture.size()):
				var kid: String = kingdoms_for_culture[i]
				opt.add_item(_kingdom_name(kid), i + 1)
			var pid: StringName = p.id
			var aid: StringName = p.action_id
			opt.item_selected.connect(func(idx: int) -> void:
				if idx <= 0:
					return
				var chosen_kid: String = kingdoms_for_culture[idx - 1]
				# Don't stack duplicates silently.
				for r in Automations.all_rules():
					if r.scope == AutomationRule.Scope.KINGDOM \
							and r.action_id == aid \
							and r.kingdom_id == chosen_kid:
						return
				Automations.create_kingdom_rule(aid, chosen_kid, pid, 6))
			right.add_child(opt)

	return row


func _kingdoms_matching_culture(culture_tag: StringName) -> Array[String]:
	if culture_tag == &"":
		return []
	var out: Array[String] = []
	for k in WorldData.kingdoms.values():
		if Languages.native_of(String(k.id)) == culture_tag:
			out.append(String(k.id))
	return out


# --- System reference (§30.1) -------------------------------------------------
#
# What used to live in the Codebook. Bands, levels, and tiers the UI speaks
# in. Each entry is sourced from the responsible system's live constants
# (Purse.band_entries(), Exposure.level_entries(), etc.) so renaming a band
# in code renames it here too.

func _render_system_reference() -> void:
	var section: VBoxContainer = VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	_content.add_child(section)

	var heading: Label = Label.new()
	heading.text = "SYSTEM REFERENCE — §30.1"
	heading.add_theme_color_override("font_color", COLOR_ACCENT)
	heading.add_theme_font_size_override("font_size", 11)
	section.add_child(heading)

	var intro: Label = Label.new()
	intro.text = "What every band on the table means. Drawn from the instruments themselves — if a word here looks wrong, the word on the table has changed and this page has been re-read."
	intro.add_theme_color_override("font_color", COLOR_INK)
	intro.add_theme_font_size_override("font_size", 12)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(intro)

	_ref_group(section, "THE PURSE", "Silver on hand. Shown as a band, never as a figure.", Purse.band_entries())
	_ref_group(section, "EXPOSURE", "How visible your hand has become. Each level bars louder instruments.", Exposure.level_entries())
	_ref_group(section, "TREASURIES OF CROWNS",
		"The fiscal state of each kingdom. Rulers shift tax posture in response.",
		_treasury_entries())
	_ref_group(section, "TAX BENCHES",
		"How hard the crown squeezes. Strained treasuries push the dial up; ruinous settings cannot last a year.",
		_tax_entries())
	_ref_group(section, "RELATIONSHIP WITH A NAME",
		"Where a specific person stands with you. The threshold into 'host' sits at about loyal.",
		_relationship_entries())
	_ref_group(section, "KINGDOMS, TO EACH OTHER",
		"How crowns regard their neighbours. Shown on the Map detail panel.",
		_relations_entries())
	_ref_group(section, "PROVINCE MOOD",
		"Every populated province carries a mood, shown only on the Map.",
		_unrest_entries())
	_ref_group(section, "THE TIME DIAL",
		"Clock speeds, top-right. Pause, day, and month.",
		[
			{"id": &"pause", "label": "Pause",     "blurb": "Time freezes. Useful for reading or composing without pressure."},
			{"id": &"day",   "label": "Day (I)",   "blurb": "One day per real second."},
			{"id": &"month", "label": "Month (II)", "blurb": "One month per real second. Most of your life passes here."},
		])
	_ref_group(section, "WHISPERS",
		"A rumour, once planted, lives on the tongues of others for a while, then fades.",
		[
			{"id": &"loud",    "label": "Loud",    "blurb": "Newly seeded. The market is talking. Expect follow-ups."},
			{"id": &"carried", "label": "Carried", "blurb": "Past the first fire, but still passed around in the same rooms."},
			{"id": &"fading",  "label": "Fading",  "blurb": "Half-remembered. A final dispatch may name its decline."},
			{"id": &"dead",    "label": "Dead",    "blurb": "Dropped. The Public News will not return to it."},
		])
	_ref_group(section, "WHAT LANDS IN THE INBOX",
		"Every letter that arrives is one of a few kinds.",
		[
			{"id": &"action", "label": "Report",         "blurb": "One of your instruments has resolved — success or failure."},
			{"id": &"intel",  "label": "Intel",          "blurb": "An eyes-and-ears observation. Treat as the reporter's claim until corroborated."},
			{"id": &"host",   "label": "From a host",    "blurb": "A loyal actor writes to you unprompted, about their city."},
			{"id": &"digest", "label": "Monthly brief",  "blurb": "A coordinator's short summary of the month that just ended."},
			{"id": &"news",   "label": "A forwarded public dispatch", "blurb": "Public news important enough to put in front of you."},
			{"id": &"intro",  "label": "Onboarding",     "blurb": "Scripted beats while you learn the table."},
		])
	_ref_group(section, "COVER IDENTITIES",
		"The faces you wear. Each identity has its own legend — how well-known and trusted the cover is in the rooms it moves through. See the Dossiers panel, 'This side of the table', for the live list.",
		[
			{"id": &"new",     "label": "A name no one knows yet", "blurb": "Just opened. The cover exists on paper; no one has seen it twice."},
			{"id": &"seen",    "label": "A face seen once or twice", "blurb": "Recognised by a handful of locals, not remembered."},
			{"id": &"circuit", "label": "A face on the circuit", "blurb": "Regular at the usual tables. Trusted enough to be admitted, not enough to be confided in."},
			{"id": &"trusted", "label": "A trusted regular", "blurb": "Familiar to gatekeepers. Doors open without challenge."},
			{"id": &"fixture", "label": "Part of the landscape", "blurb": "Everyone assumes this person has always been here."},
			{"id": &"burned",  "label": "Burned", "blurb": "The cover is dead. No operation may route through it again."},
		])

	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("color", COLOR_PARCHMENT_EDGE)
	section.add_child(sep)


func _ref_group(parent: VBoxContainer, title: String, blurb: String, entries: Array) -> void:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size.y = 6.0
	parent.add_child(spacer)

	var h: Label = Label.new()
	h.text = title
	h.add_theme_color_override("font_color", COLOR_ACCENT)
	h.add_theme_font_size_override("font_size", 11)
	parent.add_child(h)

	var b: Label = Label.new()
	b.text = blurb
	b.add_theme_color_override("font_color", COLOR_INK)
	b.add_theme_font_size_override("font_size", 12)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(b)

	for e in entries:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		parent.add_child(row)

		var name_l: Label = Label.new()
		name_l.text = String(e.get("label", ""))
		name_l.add_theme_color_override("font_color", COLOR_INK)
		name_l.add_theme_font_size_override("font_size", 12)
		name_l.custom_minimum_size.x = 140.0
		row.add_child(name_l)

		var def_l: Label = Label.new()
		def_l.text = String(e.get("blurb", ""))
		def_l.add_theme_color_override("font_color", COLOR_INK_MUTED)
		def_l.add_theme_font_size_override("font_size", 12)
		def_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		def_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(def_l)


func _treasury_entries() -> Array:
	# Names are sourced from Kingdom.TreasuryCondition enum keys so the
	# glossary never falls behind the code.
	var keys: Array = Kingdom.TreasuryCondition.keys()
	var blurbs: Dictionary = {
		"FLUSH":    "Rich. Likely planning something costly.",
		"STABLE":   "Neither rich nor struggling. The default.",
		"STRAINED": "Months of runway are thin. Rulers begin to squeeze.",
		"INDEBTED": "The crown is borrowing, often without discretion.",
		"BROKE":    "The treasury is openly empty. Emergencies follow.",
	}
	var out: Array = []
	for k in keys:
		out.append({
			"id":    StringName(String(k).to_lower()),
			"label": String(k).capitalize(),
			"blurb": String(blurbs.get(k, "")),
		})
	return out


func _tax_entries() -> Array:
	var keys: Array = Kingdom.TaxLevel.keys()
	var blurbs: Dictionary = {
		"INDULGENT": "Barely collected. Popular; hollow treasury.",
		"MODEST":    "The traditional tithe. The default.",
		"BURDENED":  "Noticeably heavy. Revenue up, patience down.",
		"RUINOUS":   "Extraordinary levies, openly resented. Cannot last a year.",
	}
	var out: Array = []
	for k in keys:
		out.append({
			"id":    StringName(String(k).to_lower()),
			"label": String(k).capitalize(),
			"blurb": String(blurbs.get(k, "")),
		})
	return out


func _relationship_entries() -> Array:
	return [
		{"id": &"hostile", "label": "Hostile", "blurb": "They would harm you if they could. Any approach is costly."},
		{"id": &"cold",    "label": "Cold",    "blurb": "They will not act for you and will forget nothing."},
		{"id": &"neutral", "label": "Neutral", "blurb": "No particular feeling. Most names begin here."},
		{"id": &"warm",    "label": "Warm",    "blurb": "Some goodwill. Your letters are read, not discarded."},
		{"id": &"loyal",   "label": "Loyal",   "blurb": "A host. Will act on your behalf at the usual carefulness."},
		{"id": &"devoted", "label": "Devoted", "blurb": "A host who volunteers. The scarcest and most dangerous asset."},
	]


func _relations_entries() -> Array:
	return [
		{"id": &"at_war",  "label": "At war",  "blurb": "Active conflict. Peace is months away at best."},
		{"id": &"cold",    "label": "Cold",    "blurb": "Recent scars, or old grudges. Alliances are impossible."},
		{"id": &"neutral", "label": "Neutral", "blurb": "No particular feeling. The default edge."},
		{"id": &"warm",    "label": "Warm",    "blurb": "Trade passes easily; envoys are kept."},
		{"id": &"sworn",   "label": "Sworn",   "blurb": "Formally allied. Will enter a war if the other is attacked."},
	]


func _unrest_entries() -> Array:
	return [
		{"id": &"quiet",    "label": "Quiet",     "blurb": "Nothing is stirring. Children at the fountain, elders at the gate."},
		{"id": &"uneasy",   "label": "Uneasy",    "blurb": "A watchfulness in the markets. Nothing named, yet."},
		{"id": &"restless", "label": "Restless",  "blurb": "Knots of men arguing. The guard looks tired on purpose."},
		{"id": &"seething", "label": "Seething",  "blurb": "Broadsides at night. The crown's name is said wrong."},
		{"id": &"revolt",   "label": "In revolt", "blurb": "Past orderly. Stones in the square, doors barred, names shouted."},
	]


func _empty_state() -> Control:
	var l: Label = Label.new()
	l.text = "No letters yet. The mail will catch up with you."
	l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	l.add_theme_font_size_override("font_size", 13)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## §D4 One-shot welcome card that appears the first time the player
## opens Memoirs after the first pattern has been recorded. Framed as
## an in-world page ("What this is") rather than a tutorial tooltip.
func _build_welcome_card() -> Control:
	var card: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.88, 0.74, 1.0)
	sb.border_color = COLOR_ACCENT
	sb.border_width_left = 2
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	card.add_theme_stylebox_override("panel", sb)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	var title: Label = Label.new()
	title.text = "— the margin note —"
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	title.add_theme_font_size_override("font_size", 12)
	col.add_child(title)

	var body: Label = Label.new()
	body.text = (
		"You keep these pages because memory is a thing that bleeds."
		+ " A thing that once worked against a certain kind of man in a"
		+ " certain kind of town is written here so that it can work"
		+ " again. The archive does not think for you. It reminds you,"
		+ " and it grows stale, and when it grows too stale it asks to"
		+ " be walked through by hand."
	)
	body.add_theme_color_override("font_color", COLOR_INK)
	body.add_theme_font_size_override("font_size", 13)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)

	return card


func _year_heading(year: int) -> Control:
	var box: MarginContainer = MarginContainer.new()
	box.add_theme_constant_override("margin_top", 12)
	box.add_theme_constant_override("margin_bottom", 2)
	var h: Label = Label.new()
	# year here is GameDate.year (positive-BCE / negative-CE). Flip
	# the label once the game crosses into the common era.
	if year > 0:
		h.text = "%d BCE" % year
	else:
		h.text = "%d CE" % max(1, -year)
	h.add_theme_color_override("font_color", COLOR_ACCENT)
	h.add_theme_font_size_override("font_size", 12)
	box.add_child(h)
	return box


func _letter_row(letter: Letter) -> Control:
	var btn: Button = Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size.y = 40.0
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hover_sb: StyleBoxFlat = StyleBoxFlat.new()
	hover_sb.bg_color = Color(0.94, 0.88, 0.74, 1.0)
	hover_sb.corner_radius_top_left = 4
	hover_sb.corner_radius_top_right = 4
	hover_sb.corner_radius_bottom_left = 4
	hover_sb.corner_radius_bottom_right = 4
	hover_sb.content_margin_left = 10
	hover_sb.content_margin_right = 10
	hover_sb.content_margin_top = 6
	hover_sb.content_margin_bottom = 6
	var normal_sb: StyleBoxFlat = hover_sb.duplicate()
	normal_sb.bg_color = Color(0, 0, 0, 0)
	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)

	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hb)

	# Kind dot (shade communicates kind; fades when read).
	var dot_wrap: CenterContainer = CenterContainer.new()
	dot_wrap.custom_minimum_size.x = 10.0
	var dot: Panel = Panel.new()
	dot.custom_minimum_size = Vector2(6, 6)
	var dot_sb: StyleBoxFlat = StyleBoxFlat.new()
	var kind_color: Color = LetterKind.color_for(letter.kind)
	if letter.is_read:
		kind_color.a = 0.35
	dot_sb.bg_color = kind_color
	dot_sb.corner_radius_top_left = 4
	dot_sb.corner_radius_top_right = 4
	dot_sb.corner_radius_bottom_left = 4
	dot_sb.corner_radius_bottom_right = 4
	dot.add_theme_stylebox_override("panel", dot_sb)
	dot.tooltip_text = LetterKind.label_for(letter.kind)
	dot_wrap.add_child(dot)
	hb.add_child(dot_wrap)

	# Date
	var date_l: Label = Label.new()
	date_l.text = _format_short_date(letter.date)
	date_l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	date_l.add_theme_font_size_override("font_size", 11)
	date_l.custom_minimum_size.x = 90.0
	hb.add_child(date_l)

	# Sender
	var sender_l: Label = Label.new()
	sender_l.text = letter.sender
	sender_l.add_theme_color_override("font_color", COLOR_INK)
	sender_l.add_theme_font_size_override("font_size", 12)
	sender_l.custom_minimum_size.x = 200.0
	sender_l.clip_text = true
	hb.add_child(sender_l)

	# Subject
	var subject_l: Label = Label.new()
	subject_l.text = letter.subject
	subject_l.add_theme_color_override(
		"font_color", COLOR_INK if not letter.is_read else COLOR_INK_MUTED
	)
	subject_l.add_theme_font_size_override("font_size", 12)
	subject_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subject_l.clip_text = true
	hb.add_child(subject_l)

	btn.pressed.connect(func() -> void: _open_letter(letter))
	return btn


func _sort_newest_first(a: Letter, b: Letter) -> bool:
	# GameDate.year is positive BCE; smaller year = later. Within the
	# same year, month and day are normal (higher = later).
	var ay: int = a.date.year if a.date != null else 0
	var by: int = b.date.year if b.date != null else 0
	if ay != by:
		return ay < by   # smaller BCE year number is later in time
	var am: int = a.date.month if a.date != null else 0
	var bm: int = b.date.month if b.date != null else 0
	if am != bm:
		return am > bm
	var ad: int = a.date.day if a.date != null else 0
	var bd: int = b.date.day if b.date != null else 0
	return ad > bd


func _format_short_date(d: GameDate) -> String:
	if d == null:
		return ""
	return "%d %s" % [d.day, _month_name(d.month)]


func _month_name(m: int) -> String:
	const NAMES: Array[String] = [
		"January", "February", "March", "April", "May", "June",
		"July", "August", "September", "October", "November", "December",
	]
	var idx: int = clampi(m, 1, 12) - 1
	return NAMES[idx]


# --- Letter opening ----------------------------------------------------------

func _open_letter(letter: Letter) -> void:
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
	_render()


func _on_child_actor_link(actor_id: StringName) -> void:
	# Bubble up so the table scene can open the dossier, then close memoirs
	# so the dossier is not stacked underneath a dimmed sheet.
	actor_link_clicked.emit(actor_id)
	_child_letter_view = null
	close()


func _on_child_codebook_link(anchor: StringName) -> void:
	# Same pattern as actor links — bubble up, close memoirs so the
	# codebook opens clean.
	codebook_link_clicked.emit(anchor)
	_child_letter_view = null
	close()
