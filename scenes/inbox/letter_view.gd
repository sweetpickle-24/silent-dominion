extends Control
## LetterView
##
## Full-screen overlay that presents a single Letter as a parchment sheet.
## Animates the wax seal cracking (if the letter was unread) and the
## letter itself unfolding from a small folded state to full size.
##
## Instantiate, call `display(letter)`, then add as a child of the table
## root. The view frees itself on close and emits `closed`.

signal closed
signal actor_link_clicked(actor_id: StringName)
signal codebook_link_clicked(anchor: StringName)

@onready var _dimmer: ColorRect         = $Dimmer
@onready var _letter_root: Control      = $LetterRoot
@onready var _paper: PanelContainer     = $LetterRoot/Paper
@onready var _sender_label: Label       = $LetterRoot/Paper/Margin/VBox/Header/Sender
@onready var _date_label: Label         = $LetterRoot/Paper/Margin/VBox/Header/Date
@onready var _subject_label: Label      = $LetterRoot/Paper/Margin/VBox/Subject
@onready var _body_label: RichTextLabel = $LetterRoot/Paper/Margin/VBox/Body
@onready var _vbox: VBoxContainer       = $LetterRoot/Paper/Margin/VBox
@onready var _seal_whole: Panel         = $LetterRoot/SealWhole
@onready var _seal_pieces: Control      = $LetterRoot/SealPieces
@onready var _seal_left: Panel          = $LetterRoot/SealPieces/SealLeft
@onready var _seal_right: Panel         = $LetterRoot/SealPieces/SealRight
@onready var _close_button: Button      = $CloseButton

const FOLDED_SCALE: Vector2 = Vector2(0.55, 0.08)
const CLOSE_TWEEN_TIME: float = 0.22
const FADE_IN_TIME: float = 0.18
const SEAL_FLEX_TIME: float = 0.09
const SEAL_SHATTER_TIME: float = 0.28
const UNFOLD_TIME: float = 0.55

# Worn look applied when the letter was already read before opening.
const READ_MODULATE: Color = Color(0.92, 0.86, 0.72, 1.0)
const UNREAD_MODULATE: Color = Color(1.0, 0.98, 0.92, 1.0)

var _letter: Letter
var _was_unread: bool = false
var _is_closing: bool = false
var _confidence_band: PanelContainer = null


func _ready() -> void:
	_dimmer.gui_input.connect(_on_dimmer_input)
	_close_button.pressed.connect(close)
	_body_label.meta_clicked.connect(_on_meta_clicked)
	_body_label.meta_hover_started.connect(_on_meta_hover_started)
	_body_label.meta_hover_ended.connect(_on_meta_hover_ended)


func _on_meta_clicked(meta: Variant) -> void:
	# Letter bodies use BBCode meta tags to cross-link to dossiers. Format:
	#   [url=actor:<actor_id>]Display Name[/url]
	# Any other meta kind is ignored here; extend as more link types
	# arrive (province, kingdom, historical event, etc.).
	var s: String = String(meta)
	if s.begins_with("actor:"):
		var id: StringName = StringName(s.substr(len("actor:")))
		actor_link_clicked.emit(id)
		close()
	elif s.begins_with("codebook:"):
		var anchor: StringName = StringName(s.substr(len("codebook:")))
		codebook_link_clicked.emit(anchor)
		close()


func _on_meta_hover_started(_meta: Variant) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)


func _on_meta_hover_ended(_meta: Variant) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


# --- Public API ---------------------------------------------------------------

func display(letter: Letter) -> void:
	_letter = letter
	_was_unread = not letter.is_read

	_sender_label.text = letter.sender
	_date_label.text   = letter.date.format_long() if letter.date else ""
	_subject_label.text = letter.subject
	# §D1 — sealed letters the player cannot read render as illegible.
	if letter.is_illegible():
		_sender_label.text  = "Unknown hand"
		_subject_label.text = "Sealed under an unknown cipher"
		_body_label.text    = (
			"The letter is stamped with a cipher-mark you do not yet hold. "
			+ "Rows of substituted letters, a few proper names in the clear, "
			+ "but nothing you can read through without the matching key. "
			+ "Set it aside and come back to it when you have opened this cipher."
		)
	else:
		_body_label.text    = letter.body

	# Worn paper tint for already-read letters.
	_paper.self_modulate = UNREAD_MODULATE if _was_unread else READ_MODULATE

	_render_confidence_band()

	_play_open_sequence()


# --- Confidence band (§18 fog-of-intel) -------------------------------------

func _render_confidence_band() -> void:
	if _confidence_band != null and is_instance_valid(_confidence_band):
		_confidence_band.queue_free()
		_confidence_band = null
	if _letter == null or not _letter.has_confidence_band():
		return

	var tier: StringName = _letter.confidence_tier()
	var bg: Color
	var fg: Color
	var label: String
	var suffix: String
	match tier:
		&"high":
			bg = Color(0.80, 0.78, 0.52, 0.55)   # aged parchment gold
			fg = Color(0.22, 0.18, 0.08, 1.0)
			label = "Confidence: high"
			suffix = " — corroborated or first-hand."
		&"medium":
			bg = Color(0.78, 0.64, 0.28, 0.55)
			fg = Color(0.26, 0.18, 0.08, 1.0)
			label = "Confidence: medium"
			suffix = " — plausible, not yet cross-referenced."
		_:
			bg = Color(0.62, 0.18, 0.12, 0.55)
			fg = Color(0.28, 0.10, 0.06, 1.0)
			label = "Confidence: low"
			suffix = " — single unverified source. Treat what follows as their claim, not yours."

	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_left = 3
	sb.border_color = fg
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS

	var lbl: Label = Label.new()
	lbl.text = "%s  (%d/100)%s" % [label, _letter.confidence, suffix]
	lbl.add_theme_color_override("font_color", fg)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(lbl)

	# Insert directly above the body (after subject).
	_vbox.add_child(panel)
	var body_idx: int = _body_label.get_index()
	_vbox.move_child(panel, body_idx)
	_confidence_band = panel


# --- Animation ----------------------------------------------------------------

func _play_open_sequence() -> void:
	# Initial state.
	modulate.a = 0.0
	_letter_root.pivot_offset = _letter_root.size * 0.5
	_letter_root.scale = FOLDED_SCALE
	_paper.modulate.a = 0.0

	_seal_whole.pivot_offset = _seal_whole.size * 0.5
	_seal_pieces.pivot_offset = _seal_pieces.size * 0.5
	_seal_left.position = Vector2.ZERO
	_seal_left.rotation = 0.0
	_seal_right.position = Vector2.ZERO
	_seal_right.rotation = 0.0

	if _was_unread:
		_seal_whole.visible = true
		_seal_whole.scale = Vector2.ONE
		_seal_whole.modulate.a = 1.0
		_seal_pieces.visible = false
		_seal_pieces.modulate.a = 0.0
	else:
		# Already broken — pieces sit rotated off to the sides.
		_seal_whole.visible = false
		_seal_pieces.visible = true
		_seal_pieces.modulate.a = 0.75
		_seal_left.position  = Vector2(-36, 10)
		_seal_left.rotation  = -0.7
		_seal_right.position = Vector2( 36, 10)
		_seal_right.rotation = 0.7

	# Fade the whole overlay in.
	var fade: Tween = create_tween()
	fade.tween_property(self, "modulate:a", 1.0, Prefs.anim_duration(FADE_IN_TIME))

	if _was_unread:
		await _animate_seal_break()

	await _animate_unfold()

	if _was_unread and _letter != null:
		Inbox.mark_read(_letter.id)


func _animate_seal_break() -> void:
	# Reduced motion: jump straight to the broken-seal final state.
	if Prefs.reduced_motion:
		_seal_whole.visible = false
		_seal_pieces.visible = true
		_seal_pieces.modulate.a = 0.75
		_seal_left.position = Vector2(-36, 10)
		_seal_left.rotation = -0.7
		_seal_right.position = Vector2(36, 10)
		_seal_right.rotation = 0.7
		return
	# Tiny wobble, then the seal splits and the pieces fly apart.
	var flex: Tween = create_tween()
	flex.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	flex.tween_property(_seal_whole, "scale", Vector2(1.18, 1.18), SEAL_FLEX_TIME)
	flex.tween_property(_seal_whole, "scale", Vector2(0.0, 0.0), SEAL_FLEX_TIME)
	flex.parallel().tween_property(_seal_whole, "modulate:a", 0.0, SEAL_FLEX_TIME)
	await flex.finished

	_seal_whole.visible = false
	_seal_pieces.visible = true
	_seal_pieces.modulate.a = 1.0

	var shatter: Tween = create_tween().set_parallel(true)
	shatter.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	shatter.tween_property(_seal_left,  "position", Vector2(-36, 10), SEAL_SHATTER_TIME)
	shatter.tween_property(_seal_left,  "rotation", -0.7, SEAL_SHATTER_TIME)
	shatter.tween_property(_seal_right, "position", Vector2( 36, 10), SEAL_SHATTER_TIME)
	shatter.tween_property(_seal_right, "rotation",  0.7, SEAL_SHATTER_TIME)
	shatter.tween_property(_seal_pieces, "modulate:a", 0.75, SEAL_SHATTER_TIME)
	await shatter.finished


func _animate_unfold() -> void:
	if Prefs.reduced_motion:
		_letter_root.scale = Vector2.ONE
		_paper.modulate.a = 1.0
		return
	var unfold: Tween = create_tween().set_parallel(true)
	unfold.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	unfold.tween_property(_letter_root, "scale", Vector2.ONE, UNFOLD_TIME)
	unfold.tween_property(_paper, "modulate:a", 1.0, UNFOLD_TIME * 0.7) \
		.set_delay(UNFOLD_TIME * 0.3)
	await unfold.finished


func close() -> void:
	if _is_closing:
		return
	_is_closing = true

	var tw: Tween = create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	var close_t: float = Prefs.anim_duration(CLOSE_TWEEN_TIME)
	tw.tween_property(self, "modulate:a", 0.0, close_t)
	tw.tween_property(_letter_root, "scale", FOLDED_SCALE, close_t)
	await tw.finished

	closed.emit()
	queue_free()


# --- Input --------------------------------------------------------------------

func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		close()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				close()
				get_viewport().set_input_as_handled()
			KEY_J, KEY_DOWN:
				_step_letter(1)
				get_viewport().set_input_as_handled()
			KEY_K, KEY_UP:
				_step_letter(-1)
				get_viewport().set_input_as_handled()


## §10.9 keyboard nav: J/K (or down/up) walks the inbox in place
## without closing and re-opening the view. Wraps at both ends.
func _step_letter(direction: int) -> void:
	if Inbox == null or _letter == null:
		return
	var letters: Array = Inbox.letters
	if letters.is_empty():
		return
	var idx: int = -1
	for i in range(letters.size()):
		var l: Letter = letters[i]
		if l != null and l.id == _letter.id:
			idx = i
			break
	if idx < 0:
		return
	var next: int = posmod(idx + direction, letters.size())
	var target: Letter = letters[next]
	if target == null:
		return
	if _was_unread and _letter != null:
		Inbox.mark_read(_letter.id)
	display(target)
