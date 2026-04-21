extends Control
## Table
##
## Root scene of Silent Dominion. The whole screen is a physical table.
## Objects on the table (map, inbox, codebook) are clicked to open their
## respective panel. Clicking outside or pressing Escape closes the panel.
##
## This is the scaffolding scene. Each object will later be replaced by a
## dedicated subsystem (map view, letter reader, codebook UI, etc.).

# --- Node references ----------------------------------------------------------

@onready var _map_scroll: Control     = $Objects/MapScroll
@onready var _inbox: Control          = $Objects/Inbox
@onready var _codebook: Control       = $Objects/Codebook

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

# Tracks the currently running tween per object so we can cancel cleanly
# when the mouse leaves mid-animation.
var _object_tweens: Dictionary = {}

# ------------------------------------------------------------------------------

func _ready() -> void:
	_panel_layer.visible = false
	_panel_layer.modulate.a = 0.0

	# Wire each object: hover feedback + click to open.
	_wire_object(_map_scroll, "The Map", _map_placeholder_text())
	_wire_object(_inbox,      "Inbox",   _inbox_placeholder_text())
	_wire_object(_codebook,   "Codebook",_codebook_placeholder_text())

	# Dimmer swallows clicks outside the panel and closes.
	_dimmer.gui_input.connect(_on_dimmer_input)
	_close_button.pressed.connect(close_panel)


func _unhandled_input(event: InputEvent) -> void:
	# Escape always closes the panel if one is open.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _panel_layer.visible:
			close_panel()
			get_viewport().set_input_as_handled()


# --- Object wiring ------------------------------------------------------------

func _wire_object(obj: Control, title: String, body: String) -> void:
	# Pivot in the centre so scale tweens look right.
	obj.pivot_offset = obj.size * 0.5

	obj.mouse_entered.connect(_on_object_hover.bind(obj, true))
	obj.mouse_exited.connect(_on_object_hover.bind(obj, false))
	obj.gui_input.connect(_on_object_input.bind(obj, title, body))


func _on_object_hover(obj: Control, entered: bool) -> void:
	if _panel_layer.visible:
		return
	var target: float = OBJECT_HOVER_SCALE if entered else 1.0
	_tween_object_scale(obj, target)


func _on_object_input(event: InputEvent, obj: Control, title: String, body: String) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_play_open_animation(obj)
		open_panel(title, body)


func _tween_object_scale(obj: Control, target: float) -> void:
	# Cancel any in-flight tween on this object so they don't stack.
	if _object_tweens.has(obj) and _object_tweens[obj] is Tween:
		(_object_tweens[obj] as Tween).kill()

	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(obj, "scale", Vector2(target, target), OBJECT_TWEEN_TIME)
	_object_tweens[obj] = tw


func _play_open_animation(obj: Control) -> void:
	# Quick punch: scale up then settle back before the panel takes focus.
	if _object_tweens.has(obj) and _object_tweens[obj] is Tween:
		(_object_tweens[obj] as Tween).kill()

	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(obj, "scale", Vector2(OBJECT_OPEN_SCALE, OBJECT_OPEN_SCALE), OBJECT_TWEEN_TIME)
	tw.tween_property(obj, "scale", Vector2.ONE, OBJECT_TWEEN_TIME)
	_object_tweens[obj] = tw


# --- Panel control ------------------------------------------------------------

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

	# Make sure no object is stuck in a hover-scaled state.
	for obj in [_map_scroll, _inbox, _codebook]:
		_tween_object_scale(obj, 1.0)


func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()


# --- Placeholder copy ---------------------------------------------------------
#
# These exist just so each panel shows something meaningful while we
# scaffold the real subsystems.

func _map_placeholder_text() -> String:
	return "A rolled map of the Mediterranean.\n\n" \
		+ "The cartography subsystem will hook in here:\n" \
		+ "regions, factions, trade routes, and your hidden agents."


func _inbox_placeholder_text() -> String:
	return "A stack of sealed letters waiting on the table.\n\n" \
		+ "The intelligence and correspondence system will deliver\n" \
		+ "reports, rumours, and contracts here."


func _codebook_placeholder_text() -> String:
	return "A leather-bound codebook.\n\n" \
		+ "Ciphers, contacts, oaths, and the names of those who\n" \
		+ "must never remember yours."
