extends Control
## Full-screen overlay for the Codebook object on the table.
##
## A qualitative glossary. Every band the player sees elsewhere in the
## game (treasury, tax, purse, exposure, relationship, tax, host
## threshold, kingdom relations) is listed here with plain-language
## definitions. No numbers. The codebook is meant to replace the need
## for a wiki — if a phrase appears on the table, it is defined here.
##
## Organised as sections with headings. Scrolls vertically. Closes on
## ESC or outside click.

signal closed

## Optional anchor to scroll the glossary to on open. Set via
## `set_anchor()` before the view is parented.
var _pending_anchor: StringName = &""
var _section_headers: Dictionary = {}   # StringName -> Control

## Set before adding this view to the tree. Scrolls the glossary to
## the section with the given id after the first frame.
func set_anchor(a: StringName) -> void:
	_pending_anchor = a

# --- Visual tokens -----------------------------------------------------------

const COLOR_DIMMER: Color         = Color(0, 0, 0, 0.62)
const COLOR_PARCHMENT: Color      = Color(0.96, 0.92, 0.82, 1.0)
const COLOR_PARCHMENT_EDGE: Color = Color(0.55, 0.42, 0.28, 0.7)
const COLOR_INK: Color            = Color(0.22, 0.14, 0.06, 1.0)
const COLOR_INK_MUTED: Color      = Color(0.22, 0.14, 0.06, 0.65)
const COLOR_ACCENT: Color         = Color(0.44, 0.36, 0.14, 1.0)
const COLOR_WAX: Color            = Color(0.55, 0.08, 0.08, 1.0)
const COLOR_GREEN: Color          = Color(0.18, 0.34, 0.22, 1.0)

# --- Nodes -------------------------------------------------------------------

var _dimmer: ColorRect
var _sheet: PanelContainer
var _content: VBoxContainer
var _scroll: ScrollContainer


# --- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP

	_build_dimmer()
	_build_sheet()
	_render()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)

	if _pending_anchor != &"":
		# Defer: the ScrollContainer needs its child sizes to settle
		# before we can ask for a header's position in it.
		call_deferred("_scroll_to_anchor", _pending_anchor)


func _scroll_to_anchor(anchor: StringName) -> void:
	var header: Control = _section_headers.get(anchor, null)
	if header == null or _scroll == null:
		return
	# Pass the header's y in content space as the scroll offset.
	var y: float = header.position.y
	_scroll.scroll_vertical = int(max(0.0, y - 4.0))
	# A brief highlight so the eye catches it.
	var original: Color = header.get_theme_color("font_color")
	header.add_theme_color_override("font_color", COLOR_WAX)
	var tw: Tween = create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(func() -> void:
		header.add_theme_color_override("font_color", original))


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
	_dimmer.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
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
	_sheet.offset_left = -360.0
	_sheet.offset_right = 360.0
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
	title.text = "The Codebook"
	title.add_theme_color_override("font_color", COLOR_INK)
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var sub: Label = Label.new()
	sub.text = "Every phrase the table uses, in plain words. Reach for this whenever a cue seems vague."
	sub.add_theme_color_override("font_color", COLOR_INK_MUTED)
	sub.add_theme_font_size_override("font_size", 12)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(sub)

	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("color", COLOR_PARCHMENT_EDGE)
	root.add_child(sep)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)

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
	_section("THE PURSE", "How much silver you have on hand. Shown as a band, never a number.", &"purse")
	_entry("Bone dry", "The purse is empty. Nothing leaves it until something enters it.", COLOR_WAX)
	_entry("Thin", "Silver present, but not much. One expensive move strips the bottom.", COLOR_WAX)
	_entry("Lean", "Enough for careful work. Not enough for noise.", COLOR_ACCENT)
	_entry("Comfortable", "Enough to live many seasons and still pay a paymaster.", COLOR_INK)
	_entry("Deep", "You could fund a small war, quietly.", COLOR_GREEN)
	_entry("Bottomless", "Silver is no longer the constraint.", COLOR_GREEN)

	_divider()

	_section("EXPOSURE",
		"How visible your hand has become. High exposure bars louder instruments; quiet ones remain available longer.",
		&"exposure")
	_entry("Unknown", "No one is looking for you. All instruments are on the table.", COLOR_GREEN)
	_entry("Suspected", "Someone, somewhere, is asking the wrong questions. Loud work becomes risky.", COLOR_ACCENT)
	_entry("Watched", "A specific court is paying attention. Most aggressive moves are barred.", COLOR_ACCENT)
	_entry("Pursued", "You are hunted. Only the quietest instruments remain usable.", COLOR_WAX)
	_entry("Burned", "The world knows your shape. Nothing loud will survive. Time to disappear.", COLOR_WAX)

	_divider()

	_section("TREASURIES OF CROWNS",
		"The fiscal state of each kingdom. Rulers adjust the tax dial in response.",
		&"treasury")
	_entry("Flush", "Rich. Likely planning something costly next.", COLOR_GREEN)
	_entry("Stable", "Neither rich nor struggling. The default state.", COLOR_INK)
	_entry("Strained", "Months of runway are thin. Rulers begin to squeeze.", COLOR_ACCENT)
	_entry("Indebted", "The crown is borrowing, often without discretion.", COLOR_WAX)
	_entry("Broke", "The treasury is openly empty. Emergencies follow.", COLOR_WAX)

	_divider()

	_section("TAX BENCHES",
		"How hard the crown squeezes its provinces. Shifts with treasury state. Ruinous and burdened settings cannot last forever.",
		&"tax")
	_entry("Indulgent", "Barely collected. Popular; hollow treasury.", COLOR_GREEN)
	_entry("Modest", "The traditional tithe. The default.", COLOR_INK)
	_entry("Burdened", "Noticeably heavy. Revenue up, patience down.", COLOR_ACCENT)
	_entry("Ruinous", "Extraordinary levies, openly resented. Cannot last a year.", COLOR_WAX)

	_divider()

	_section("RELATIONSHIP WITH A NAME",
		"Where a specific person stands with you. Changes through cultivation, bribery, rumor, and time.",
		&"relationship")
	_entry("Hostile", "They would harm you if they could. Any approach is costly.", COLOR_WAX)
	_entry("Cold", "They will not act for you and will forget nothing.", COLOR_ACCENT)
	_entry("Neutral", "No particular feeling. Most names begin here.", COLOR_INK_MUTED)
	_entry("Warm", "Some goodwill. Your letters are read, not discarded.", COLOR_ACCENT)
	_entry("Loyal", "A host. Will act on your behalf at the usual carefulness.", COLOR_GREEN)
	_entry("Devoted", "A host who volunteers. The scarcest and most dangerous asset.", COLOR_GREEN)

	_divider()

	_section("HOSTS (§5)",
		"Named figures loyal enough to act for you. Only non-rulers can become hosts; rulers are influenced, not owned.",
		&"hosts")
	_entry("Host threshold",
		"A relationship crosses into host territory at about 'loyal'. Below that, even the friendliest name will not risk their neck for yours.",
		COLOR_GREEN)
	_entry("Via host",
		"Actions tagged 'via host' route through the loyal actor instead of your own hand. Exposure stays low; the host's traits drive the roll.",
		COLOR_GREEN)

	_divider()

	_section("KINGDOMS, TO EACH OTHER",
		"The map detail panel describes how a crown stands with its neighbors in these terms.",
		&"relations")
	_entry("At war", "Active conflict. Peace treaties are months away at best.", COLOR_WAX)
	_entry("Cold", "Recent scars, or old grudges. Alliances are impossible; war is possible.", COLOR_ACCENT)
	_entry("Neutral", "No particular feeling. The default edge.", COLOR_INK_MUTED)
	_entry("Warm", "Trade passes easily; envoys are kept.", COLOR_ACCENT)
	_entry("Sworn", "Formally allied. Will enter a war with the other if the other is attacked.", COLOR_GREEN)

	_divider()

	_section("PROVINCE MOOD",
		"Every populated province carries a mood that shifts with taxes, war, and your own rumor-work. Shown only on the Map.",
		&"unrest")
	_entry("Quiet", "Nothing is stirring. Children at the fountain, elders at the gate.", COLOR_GREEN)
	_entry("Uneasy", "A watchfulness in the markets. Nothing named, yet.", COLOR_ACCENT)
	_entry("Restless", "Knots of men arguing. The guard looks tired on purpose.", COLOR_ACCENT)
	_entry("Seething", "Broadsides at night. The crown's name is said wrong.", COLOR_WAX)
	_entry("In revolt", "Past orderly. Stones in the square, doors barred, names shouted.", COLOR_WAX)

	_divider()

	_section("THE TIME DIAL",
		"Clock speeds, top-right. Pause, day, and month. No faster setting exists yet.",
		&"time")
	_entry("Pause", "Time freezes. Useful for reading or composing without pressure.", COLOR_INK_MUTED)
	_entry("Day (I)",  "One day per real second.", COLOR_INK)
	_entry("Month (II)", "One month per real second. Most of your life passes here.", COLOR_INK)

	_divider()

	_section("WHAT LANDS IN THE INBOX",
		"Every letter the player receives is one of a few kinds.",
		&"inbox")
	_entry("Report", "Your own instrument has resolved — success or failure.", COLOR_INK)
	_entry("From a host", "A loyal actor writes to you unprompted, about their city.", COLOR_GREEN)
	_entry("A name falls / won", "A host crosses the threshold, into or out of your stable.", COLOR_ACCENT)
	_entry("Monthly brief", "Your factotum's short summary of the month that just ended.", COLOR_INK_MUTED)


# --- Helpers -----------------------------------------------------------------

func _section(title: String, blurb: String, anchor_id: StringName = &"") -> void:
	var h: Label = Label.new()
	h.text = title
	h.add_theme_color_override("font_color", COLOR_ACCENT)
	h.add_theme_font_size_override("font_size", 11)
	_content.add_child(h)

	if anchor_id != &"":
		_section_headers[anchor_id] = h

	var b: Label = Label.new()
	b.text = blurb
	b.add_theme_color_override("font_color", COLOR_INK)
	b.add_theme_font_size_override("font_size", 13)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(b)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size.y = 4.0
	_content.add_child(spacer)


func _entry(term: String, defn: String, accent: Color) -> void:
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	_content.add_child(hb)

	var dot: Panel = Panel.new()
	dot.custom_minimum_size = Vector2(6, 6)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = accent
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	dot.add_theme_stylebox_override("panel", sb)
	var dot_wrap: CenterContainer = CenterContainer.new()
	dot_wrap.custom_minimum_size.x = 14.0
	dot_wrap.add_child(dot)
	hb.add_child(dot_wrap)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(col)

	var term_l: Label = Label.new()
	term_l.text = term
	term_l.add_theme_color_override("font_color", COLOR_INK)
	term_l.add_theme_font_size_override("font_size", 13)
	col.add_child(term_l)

	var def_l: Label = Label.new()
	def_l.text = defn
	def_l.add_theme_color_override("font_color", COLOR_INK_MUTED)
	def_l.add_theme_font_size_override("font_size", 12)
	def_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(def_l)


func _divider() -> void:
	var spacer_a: Control = Control.new()
	spacer_a.custom_minimum_size.y = 8.0
	_content.add_child(spacer_a)
	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("color", COLOR_PARCHMENT_EDGE)
	_content.add_child(sep)
	var spacer_b: Control = Control.new()
	spacer_b.custom_minimum_size.y = 8.0
	_content.add_child(spacer_b)
