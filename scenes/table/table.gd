extends Control
## Table
##
## Root scene of Silent Dominion. The whole screen is a physical table.
## Objects on the table (map, inbox, codebook) are clicked to open their
## respective subsystem.
##
## Currently only the inbox has real behaviour; the map and codebook still
## show placeholder panels.

const LetterViewScene: PackedScene = preload("res://scenes/inbox/letter_view.tscn")

# --- Node references ----------------------------------------------------------

@onready var _map_scroll: Control     = $Objects/MapScroll
@onready var _inbox: Control          = $Objects/Inbox
@onready var _codebook: Control       = $Objects/Codebook

@onready var _inbox_seal: Panel       = $Objects/Inbox/Letter1/WaxSeal
@onready var _inbox_badge: Control    = $Objects/Inbox/UnreadBadge
@onready var _inbox_badge_count: Label = $Objects/Inbox/UnreadBadge/Count

@onready var _panel_layer: Control    = $PanelLayer
@onready var _dimmer: ColorRect       = $PanelLayer/Dimmer
@onready var _panel: PanelContainer   = $PanelLayer/PanelContent
@onready var _panel_title: Label      = $PanelLayer/PanelContent/Margin/VBox/Title
@onready var _panel_body: Label       = $PanelLayer/PanelContent/Margin/VBox/Body
@onready var _close_button: Button    = $PanelLayer/PanelContent/Margin/VBox/CloseButton

# --- Tuning -------------------------------------------------------------------

const OBJECT_HOVER_SCALE: float       = 1.04
const OBJECT_OPEN_SCALE: float        = 1.12
const OBJECT_TWEEN_TIME: float        = 0.12
const PANEL_TWEEN_TIME: float         = 0.18
const BADGE_PULSE_TIME: float         = 0.9

# Tracks the currently running tween per object so hover/click animations
# don't stack when the mouse moves mid-animation.
var _object_tweens: Dictionary = {}
var _badge_tween: Tween

# True while a LetterView overlay is open. Used to suppress hover feedback.
var _overlay_active: bool = false

# ------------------------------------------------------------------------------

func _ready() -> void:
	_panel_layer.visible = false
	_panel_layer.modulate.a = 0.0

	_wire_object(_map_scroll, _on_map_clicked)
	_wire_object(_inbox, _on_inbox_clicked)
	_wire_object(_codebook, _on_codebook_clicked)

	_dimmer.gui_input.connect(_on_dimmer_input)
	_close_button.pressed.connect(close_panel)

	Inbox.letters_changed.connect(_refresh_inbox_visual)
	_refresh_inbox_visual()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _panel_layer.visible:
			close_panel()
			get_viewport().set_input_as_handled()


# --- Object wiring ------------------------------------------------------------

func _wire_object(obj: Control, on_click: Callable) -> void:
	obj.pivot_offset = obj.size * 0.5
	obj.mouse_entered.connect(_on_object_hover.bind(obj, true))
	obj.mouse_exited.connect(_on_object_hover.bind(obj, false))
	obj.gui_input.connect(_on_object_input.bind(obj, on_click))


func _on_object_hover(obj: Control, entered: bool) -> void:
	if _panel_layer.visible or _overlay_active:
		return
	var target: float = OBJECT_HOVER_SCALE if entered else 1.0
	_tween_object_scale(obj, target)


func _on_object_input(event: InputEvent, obj: Control, on_click: Callable) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_play_open_animation(obj)
		on_click.call()


func _tween_object_scale(obj: Control, target: float) -> void:
	if _object_tweens.has(obj) and _object_tweens[obj] is Tween:
		(_object_tweens[obj] as Tween).kill()

	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(obj, "scale", Vector2(target, target), OBJECT_TWEEN_TIME)
	_object_tweens[obj] = tw


func _play_open_animation(obj: Control) -> void:
	if _object_tweens.has(obj) and _object_tweens[obj] is Tween:
		(_object_tweens[obj] as Tween).kill()

	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(obj, "scale", Vector2(OBJECT_OPEN_SCALE, OBJECT_OPEN_SCALE), OBJECT_TWEEN_TIME)
	tw.tween_property(obj, "scale", Vector2.ONE, OBJECT_TWEEN_TIME)
	_object_tweens[obj] = tw


# --- Per-object actions -------------------------------------------------------

func _on_map_clicked() -> void:
	open_panel("The Map", _map_placeholder_text())


func _on_codebook_clicked() -> void:
	open_panel("Codebook", _codebook_placeholder_text())


func _on_inbox_clicked() -> void:
	var letter: Letter = Inbox.get_top_letter()
	if letter == null:
		open_panel("Inbox", "The table is bare. No letters have come.")
		return
	_open_letter_view(letter)


func _open_letter_view(letter: Letter) -> void:
	_overlay_active = true
	var view: Control = LetterViewScene.instantiate()
	add_child(view)
	view.closed.connect(_on_letter_view_closed)
	view.display(letter)


func _on_letter_view_closed() -> void:
	_overlay_active = false
	for obj in [_map_scroll, _inbox, _codebook]:
		_tween_object_scale(obj, 1.0)


# --- Placeholder panel (map / codebook) ---------------------------------------

func open_panel(title: String, body: String) -> void:
	_panel_title.text = title
	_panel_body.text  = body

	_panel_layer.visible = true
	_panel_layer.modulate.a = 0.0
	_panel.scale = Vector2(0.92, 0.92)
	_panel.pivot_offset = _panel.size * 0.5

	var tw: Tween = create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel_layer, "modulate:a", 1.0, PANEL_TWEEN_TIME)
	tw.tween_property(_panel, "scale", Vector2.ONE, PANEL_TWEEN_TIME)


func close_panel() -> void:
	if not _panel_layer.visible:
		return

	var tw: Tween = create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_panel_layer, "modulate:a", 0.0, PANEL_TWEEN_TIME)
	tw.tween_property(_panel, "scale", Vector2(0.96, 0.96), PANEL_TWEEN_TIME)
	await tw.finished
	_panel_layer.visible = false

	for obj in [_map_scroll, _inbox, _codebook]:
		_tween_object_scale(obj, 1.0)


func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()


# --- Inbox visual state -------------------------------------------------------
#
# Keep the wax seal on the top letter of the stack visible only while there
# are unread letters, and show a small red badge with the unread count that
# pulses softly to draw the eye.

func _refresh_inbox_visual() -> void:
	var unread: int = Inbox.get_unread_count()
	_inbox_seal.visible = unread > 0
	_inbox_badge.visible = unread > 0
	_inbox_badge_count.text = str(unread)

	if _badge_tween != null:
		_badge_tween.kill()
		_badge_tween = null

	if unread > 0:
		_inbox_badge.pivot_offset = _inbox_badge.size * 0.5
		_badge_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		_badge_tween.tween_property(_inbox_badge, "scale", Vector2(1.12, 1.12), BADGE_PULSE_TIME)
		_badge_tween.tween_property(_inbox_badge, "scale", Vector2.ONE, BADGE_PULSE_TIME)


# --- Placeholder copy ---------------------------------------------------------

func _map_placeholder_text() -> String:
	return "A rolled map of the Mediterranean.\n\n" \
		+ "The cartography subsystem will hook in here:\n" \
		+ "regions, factions, trade routes, and your hidden agents."


func _codebook_placeholder_text() -> String:
	return "A leather-bound codebook.\n\n" \
		+ "Ciphers, contacts, oaths, and the names of those who\n" \
		+ "must never remember yours."
