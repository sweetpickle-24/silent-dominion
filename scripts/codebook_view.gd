extends Control
## §D1 — The Codebook is the player's encrypted-correspondence desk.
##
## It is no longer a glossary. The glossary has moved to Memoirs §30.1
## "System reference", where it is wired to live system constants so it
## cannot drift.
##
## Three sections, top to bottom:
##
##   1. CIPHERED CONTACTS — a list of Actors you share an active cipher
##      with. At campaign start this holds exactly the starter coordinator.
##   2. NEW CIPHERED MESSAGE — pick a contact, write a short body, seal
##      and send. A cipher-stamped Letter is dropped into the Inbox as an
##      outgoing record.
##   3. DECRYPT INBOX — lists incoming letters whose cipher_id is known
##      to the player. Clicking one opens the LetterView unsealed.

signal closed

var _pending_anchor: StringName = &""

func set_anchor_id(a: StringName) -> void:
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

var _contacts_column: VBoxContainer
var _decrypt_column: VBoxContainer
var _compose_container: VBoxContainer
var _compose_body: TextEdit
var _selected_contact: Actor = null
var _selected_label: Label


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

	if Codebook != null:
		Codebook.ciphers_changed.connect(_render)
		Codebook.contacts_changed.connect(_render)
	if Inbox != null:
		Inbox.letters_changed.connect(_render)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
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
	_sheet.offset_left = -400.0
	_sheet.offset_right = 400.0
	_sheet.offset_top = -320.0
	_sheet.offset_bottom = 320.0
	_sheet.mouse_filter = MOUSE_FILTER_STOP
	add_child(_sheet)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_sheet.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title: Label = Label.new()
	title.text = "The Codebook"
	title.add_theme_color_override("font_color", COLOR_INK)
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var sub: Label = Label.new()
	sub.text = "Where ciphers are kept, sealed letters written, and incoming seals broken. For the glossary, see Memoirs — System reference."
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
	_content.add_theme_constant_override("separation", 10)
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
	for c in _content.get_children():
		c.queue_free()

	_render_contacts()
	_divider()
	_render_compose()
	_divider()
	_render_decrypt_inbox()


func _render_contacts() -> void:
	_section("CIPHERED CONTACTS",
		"Names you share an active cipher with. A letter sealed under the cipher cannot be read by anyone else who intercepts it.")
	_contacts_column = VBoxContainer.new()
	_contacts_column.add_theme_constant_override("separation", 4)
	_content.add_child(_contacts_column)

	var list: Array[Actor] = Codebook.contacts() if Codebook != null else []
	if list.is_empty():
		_line("No active ciphers. Your correspondence is plaintext.", COLOR_INK_MUTED)
		return
	for a in list:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_contacts_column.add_child(row)

		var name_l: Label = Label.new()
		name_l.text = a.display_name()
		name_l.add_theme_color_override("font_color", COLOR_INK)
		name_l.add_theme_font_size_override("font_size", 14)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)

		var cid: StringName = Codebook.cipher_for_contact(a.id)
		var ciph_l: Label = Label.new()
		ciph_l.text = Codebook.cipher_display(cid)
		ciph_l.add_theme_color_override("font_color", COLOR_ACCENT)
		ciph_l.add_theme_font_size_override("font_size", 11)
		row.add_child(ciph_l)

		var use_btn: Button = Button.new()
		use_btn.text = "Write to"
		use_btn.add_theme_font_size_override("font_size", 11)
		use_btn.focus_mode = Control.FOCUS_NONE
		use_btn.pressed.connect(_select_contact.bind(a))
		row.add_child(use_btn)


func _select_contact(a: Actor) -> void:
	_selected_contact = a
	if _selected_label != null:
		_selected_label.text = "To: %s (under %s)" % [
			a.display_name(),
			Codebook.cipher_display(Codebook.cipher_for_contact(a.id)),
		]


func _render_compose() -> void:
	_section("NEW CIPHERED MESSAGE",
		"Seal a short instruction under the chosen contact's cipher. The outbound letter is stamped into your inbox as a record of what you sent.")
	_compose_container = VBoxContainer.new()
	_compose_container.add_theme_constant_override("separation", 6)
	_content.add_child(_compose_container)

	_selected_label = Label.new()
	if _selected_contact != null:
		_selected_label.text = "To: %s (under %s)" % [
			_selected_contact.display_name(),
			Codebook.cipher_display(Codebook.cipher_for_contact(_selected_contact.id)),
		]
	else:
		_selected_label.text = "To: — pick a contact above."
	_selected_label.add_theme_color_override("font_color", COLOR_INK_MUTED)
	_selected_label.add_theme_font_size_override("font_size", 12)
	_compose_container.add_child(_selected_label)

	_compose_body = TextEdit.new()
	_compose_body.custom_minimum_size.y = 80.0
	_compose_body.placeholder_text = "Short instructions — one paragraph. This will be sealed under the cipher."
	_compose_container.add_child(_compose_body)

	var seal_btn: Button = Button.new()
	seal_btn.text = "Seal and send"
	seal_btn.focus_mode = Control.FOCUS_NONE
	seal_btn.pressed.connect(_on_seal_pressed)
	_compose_container.add_child(seal_btn)


func _on_seal_pressed() -> void:
	if _selected_contact == null or _compose_body == null:
		return
	var body: String = _compose_body.text.strip_edges()
	if body.is_empty():
		return
	var cid: StringName = Codebook.cipher_for_contact(_selected_contact.id)
	if cid == &"":
		return
	var letter: Letter = Letter.create(
		StringName("outbound_%s_%d" % [String(_selected_contact.id), Time.get_ticks_msec()]),
		"You, to %s" % _selected_contact.display_name(),
		GameDate.today(),
		"Sealed instructions",
		body,
		&"action",
	)
	letter.cipher_id = cid
	letter.is_read = true  # outbound — already seen
	if Inbox != null:
		Inbox.add_letter(letter)
	_compose_body.text = ""


func _render_decrypt_inbox() -> void:
	_section("DECRYPT INBOX",
		"Incoming letters sealed under a cipher you hold. Anything stamped with a cipher you do not know stays illegible in your Inbox.")
	_decrypt_column = VBoxContainer.new()
	_decrypt_column.add_theme_constant_override("separation", 4)
	_content.add_child(_decrypt_column)

	if Inbox == null:
		return
	var any: bool = false
	for l in Inbox.letters:
		if l == null:
			continue
		if l.cipher_id == &"":
			continue
		if not Codebook.knows_cipher(l.cipher_id):
			continue
		any = true
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_decrypt_column.add_child(row)

		var sub: Label = Label.new()
		sub.text = l.subject
		sub.add_theme_color_override("font_color", COLOR_INK)
		sub.add_theme_font_size_override("font_size", 13)
		sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sub)

		var ciph: Label = Label.new()
		ciph.text = Codebook.cipher_display(l.cipher_id)
		ciph.add_theme_color_override("font_color", COLOR_ACCENT)
		ciph.add_theme_font_size_override("font_size", 11)
		row.add_child(ciph)
	if not any:
		_line("No sealed correspondence in the inbox.", COLOR_INK_MUTED)


# --- Helpers -----------------------------------------------------------------

func _section(title: String, blurb: String) -> void:
	var h: Label = Label.new()
	h.text = title
	h.add_theme_color_override("font_color", COLOR_ACCENT)
	h.add_theme_font_size_override("font_size", 11)
	_content.add_child(h)

	var b: Label = Label.new()
	b.text = blurb
	b.add_theme_color_override("font_color", COLOR_INK)
	b.add_theme_font_size_override("font_size", 13)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(b)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size.y = 4.0
	_content.add_child(spacer)


func _line(text: String, color: Color) -> void:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 12)
	_content.add_child(l)


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
