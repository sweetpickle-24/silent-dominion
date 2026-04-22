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
	_body_label.text    = letter.body

	# Worn paper tint for already-read letters.
	_paper.self_modulate = UNREAD_MODULATE if _was_unread else READ_MODULATE

	_play_open_sequence()


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
	fade.tween_property(self, "modulate:a", 1.0, FADE_IN_TIME)

	if _was_unread:
		await _animate_seal_break()

	await _animate_unfold()

	if _was_unread and _letter != null:
		Inbox.mark_read(_letter.id)


func _animate_seal_break() -> void:
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
	tw.tween_property(self, "modulate:a", 0.0, CLOSE_TWEEN_TIME)
	tw.tween_property(_letter_root, "scale", FOLDED_SCALE, CLOSE_TWEEN_TIME)
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
		if event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
