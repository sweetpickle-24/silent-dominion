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
@onready var _memoirs: Control        = $Objects/Memoirs
@onready var _public_news: Control    = $Objects/PublicNews
@onready var _ledger: Control         = $Objects/Ledger
@onready var _dossiers: Control       = $Objects/Dossiers
@onready var _compose: Control        = $Objects/Compose

@onready var _inbox_seal: Panel       = $Objects/Inbox/Letter1/WaxSeal
@onready var _inbox_badge: Control    = $Objects/Inbox/UnreadBadge
@onready var _inbox_badge_count: Label = $Objects/Inbox/UnreadBadge/Count

@onready var _time_date_label: Label  = $TimeDial/HBox/DateTablet/Margin/Date
@onready var _btn_pause: Button       = $TimeDial/HBox/Markers/Pause
@onready var _btn_day: Button         = $TimeDial/HBox/Markers/Day
@onready var _btn_month: Button       = $TimeDial/HBox/Markers/Month

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
	_wire_object(_memoirs, _on_memoirs_clicked)
	_wire_object(_public_news, _on_public_news_clicked)
	_wire_object(_ledger, _on_ledger_clicked)
	_wire_object(_dossiers, _on_dossiers_clicked)
	_wire_object(_compose, _on_compose_clicked)

	_dimmer.gui_input.connect(_on_dimmer_input)
	_close_button.pressed.connect(close_panel)

	Inbox.letters_changed.connect(_refresh_inbox_visual)
	_refresh_inbox_visual()

	_wire_time_dial()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _panel_layer.visible:
			close_panel()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F1:
			# Developer shortcut: dump the loaded world to the console.
			WorldData.print_debug_dump()
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


func _on_memoirs_clicked() -> void:
	open_panel("Memoirs", _memoirs_placeholder_text())


func _on_public_news_clicked() -> void:
	open_panel("Public Dispatches", _public_news_placeholder_text())


func _on_ledger_clicked() -> void:
	open_panel("Ledger", _ledger_placeholder_text())


func _on_dossiers_clicked() -> void:
	open_panel("Dossiers", _dossiers_placeholder_text())


func _on_compose_clicked() -> void:
	open_panel("Compose a Letter", _compose_placeholder_text())


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
	for obj in _all_objects():
		_tween_object_scale(obj, 1.0)


func _all_objects() -> Array:
	return [_map_scroll, _inbox, _codebook, _memoirs,
			_public_news, _ledger, _dossiers, _compose]


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

	for obj in _all_objects():
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


# --- Time dial ----------------------------------------------------------------
#
# Five brass markers share a ButtonGroup so exactly one is pressed at any
# time. Pressing a marker sets the corresponding GameClock speed; the clock
# emits signals we use to keep the date tablet in sync.

func _wire_time_dial() -> void:
	var group: ButtonGroup = ButtonGroup.new()
	_btn_pause.button_group  = group
	_btn_day.button_group    = group
	_btn_month.button_group  = group

	_btn_pause.pressed.connect(func() -> void:  GameClock.set_speed(GameClock.Speed.PAUSED))
	_btn_day.pressed.connect(func() -> void:    GameClock.set_speed(GameClock.Speed.DAY))
	_btn_month.pressed.connect(func() -> void:  GameClock.set_speed(GameClock.Speed.MONTH))

	GameClock.day_passed.connect(_on_day_passed)
	GameClock.speed_changed.connect(_on_speed_changed)

	_refresh_time_display()
	_on_speed_changed(GameClock.speed)


func _on_day_passed(_year: int, _month: int, _day: int) -> void:
	_refresh_time_display()


func _on_speed_changed(speed: int) -> void:
	# Keep the pressed marker in sync in case speed is changed from elsewhere
	# (e.g. a future hotkey). Uses set_pressed_no_signal to avoid re-firing.
	_btn_pause.set_pressed_no_signal(speed  == GameClock.Speed.PAUSED)
	_btn_day.set_pressed_no_signal(speed    == GameClock.Speed.DAY)
	_btn_month.set_pressed_no_signal(speed  == GameClock.Speed.MONTH)


func _refresh_time_display() -> void:
	_time_date_label.text = GameClock.format_date()


# --- Placeholder copy ---------------------------------------------------------

func _map_placeholder_text() -> String:
	return "A rolled map of the Mediterranean.\n\n" \
		+ "The cartography subsystem will hook in here:\n" \
		+ "regions, factions, trade routes, and your hidden agents."


func _codebook_placeholder_text() -> String:
	return "A leather-bound codebook.\n\n" \
		+ "Ciphers, contacts, oaths, and the names of those who\n" \
		+ "must never remember yours."


func _memoirs_placeholder_text() -> String:
	return "Your memoirs. A worn journal of centuries.\n\n" \
		+ "Patterns across eras, faces that keep returning\n" \
		+ "in different bodies, and notes to your future self."


func _public_news_placeholder_text() -> String:
	return "Public dispatches, posted for anyone who can read.\n\n" \
		+ "Kings dying, cities burning, famines declared —\n" \
		+ "the news the world already knows. Compare it to\n" \
		+ "what your network has told you."


func _ledger_placeholder_text() -> String:
	return "A heavy accounts book.\n\n" \
		+ "Treasuries, bribes in flight, debts owed and owed\n" \
		+ "to you, and every silver piece you have quietly moved."


func _dossiers_placeholder_text() -> String:
	return "A stack of profile cards.\n\n" \
		+ "Names, faces, last-known whereabouts, temperaments,\n" \
		+ "loyalties, and the leverage you hold over each of them."


func _compose_placeholder_text() -> String:
	return "A blank sheet, a quill, an inkwell, a stick of wax\n" \
		+ "and your seal ring.\n\n" \
		+ "This is how orders leave the table. Every action you\n" \
		+ "take is a letter sealed and sent."
