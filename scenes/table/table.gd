extends Control
## Table
##
## Root scene of Silent Dominion. The whole screen is a physical table.
## Objects on the table (map, inbox, codebook) are clicked to open their
## respective subsystem.
##
## Currently only the inbox has real behaviour; the map and codebook still
## show placeholder panels.

const LetterViewScene: PackedScene      = preload("res://scenes/inbox/letter_view.tscn")
const PendingTrayScript: Script         = preload("res://scripts/pending_tray.gd")
const DossierViewScript: Script         = preload("res://scripts/dossier_view.gd")
const ComposeViewScript: Script         = preload("res://scripts/compose_view.gd")
const ExposureIndicatorScript: Script   = preload("res://scripts/exposure_indicator.gd")
const LedgerViewScript: Script          = preload("res://scripts/ledger_view.gd")
const PublicNewsViewScript: Script      = preload("res://scripts/public_news_view.gd")
const MapViewScript: Script             = preload("res://scripts/map_view.gd")
const PurseIndicatorScript: Script      = preload("res://scripts/purse_indicator.gd")
const SlotsViewScript: Script           = preload("res://scripts/slots_view.gd")
const ArchiveIndicatorScript: Script    = preload("res://scripts/archive_indicator.gd")
const CodebookViewScript: Script        = preload("res://scripts/codebook_view.gd")
const MemoirsViewScript: Script         = preload("res://scripts/memoirs_view.gd")

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
	_install_pending_tray()
	_install_exposure_indicator()
	_install_purse_indicator()
	_install_archive_indicator()
	_install_public_news_badge()
	_install_object_unread_dots()

	# If the player arrived here via 'Return to X' on the title screen,
	# Session carries the slot to load. Apply it after the scene is
	# fully wired so signal handlers (inbox badge, time dial) are
	# already listening.
	_apply_pending_load()


func _apply_pending_load() -> void:
	var slot: String = Session.consume_pending_load()
	if slot == "":
		return
	if SaveManager.load_from_slot(slot):
		_refresh_inbox_visual()
		_refresh_time_display()


# --- Pending actions tray ----------------------------------------------------
#
# Built in code so the tscn stays focused on the static table objects.
# Anchored top-right, sitting directly beneath the TimeDial so the time
# controls and the "awaiting reply" stack read as one chronology corner.

func _install_pending_tray() -> void:
	var tray: Control = Control.new()
	tray.set_script(PendingTrayScript)
	tray.name = "PendingTray"
	tray.anchor_left = 1.0
	tray.anchor_right = 1.0
	tray.anchor_top = 0.0
	tray.anchor_bottom = 0.0
	tray.offset_left = -380.0
	tray.offset_right = -20.0
	tray.offset_top = 96.0           # just below TimeDial (which ends at y=84)
	tray.offset_bottom = 180.0
	tray.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tray.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(tray)


# --- Exposure indicator ------------------------------------------------------
#
# Anchored top-left, the visual counterweight to the TimeDial. Shows the
# current exposure level as a qualitative phrase (no raw number).

# --- Public News unread badge ------------------------------------------------
#
# Tiny red wax-dot + count in the top-right of the folded broadsheet.
# Appears only when PublicNews has unread entries.

var _news_badge: Control
var _news_badge_count: Label


func _install_public_news_badge() -> void:
	_news_badge = Control.new()
	_news_badge.name = "UnreadBadge"
	_news_badge.anchor_left = 1.0
	_news_badge.anchor_right = 1.0
	_news_badge.anchor_top = 0.0
	_news_badge.anchor_bottom = 0.0
	_news_badge.offset_left = -28.0
	_news_badge.offset_top = -6.0
	_news_badge.offset_right = -4.0
	_news_badge.offset_bottom = 18.0
	_news_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var dot: Panel = Panel.new()
	dot.anchor_right = 1.0
	dot.anchor_bottom = 1.0
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.55, 0.08, 0.08, 1.0)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	dot.add_theme_stylebox_override("panel", sb)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_news_badge.add_child(dot)

	_news_badge_count = Label.new()
	_news_badge_count.anchor_right = 1.0
	_news_badge_count.anchor_bottom = 1.0
	_news_badge_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_news_badge_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_news_badge_count.add_theme_color_override("font_color", Color.WHITE)
	_news_badge_count.add_theme_font_size_override("font_size", 11)
	_news_badge_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_news_badge.add_child(_news_badge_count)

	_public_news.add_child(_news_badge)

	PublicNews.news_changed.connect(_refresh_public_news_badge)
	_refresh_public_news_badge()


func _refresh_public_news_badge() -> void:
	if _news_badge == null:
		return
	var n: int = PublicNews.unread_count()
	_news_badge.visible = n > 0
	_news_badge_count.text = str(n) if n < 100 else "99+"


func _install_exposure_indicator() -> void:
	var ind: Control = Control.new()
	ind.set_script(ExposureIndicatorScript)
	ind.name = "ExposureIndicator"
	ind.anchor_left = 0.0
	ind.anchor_right = 0.0
	ind.anchor_top = 0.0
	ind.anchor_bottom = 0.0
	ind.offset_left = 20.0
	ind.offset_top = 20.0
	ind.offset_right = 260.0
	ind.offset_bottom = 54.0
	ind.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(ind)


func _install_purse_indicator() -> void:
	var ind: Control = Control.new()
	ind.set_script(PurseIndicatorScript)
	ind.name = "PurseIndicator"
	ind.anchor_left = 0.0
	ind.anchor_right = 0.0
	ind.anchor_top = 0.0
	ind.anchor_bottom = 0.0
	ind.offset_left = 20.0
	ind.offset_top = 60.0
	ind.offset_right = 260.0
	ind.offset_bottom = 94.0
	ind.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(ind)


func _install_archive_indicator() -> void:
	var ind: Control = Control.new()
	ind.set_script(ArchiveIndicatorScript)
	ind.name = "ArchiveIndicator"
	ind.anchor_left = 0.0
	ind.anchor_right = 0.0
	ind.anchor_top = 0.0
	ind.anchor_bottom = 0.0
	ind.offset_left = 20.0
	ind.offset_top = 100.0
	ind.offset_right = 260.0
	ind.offset_bottom = 134.0
	ind.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(ind)
	ind.pressed.connect(_open_slots_view)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _panel_layer.visible:
			close_panel()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F1:
			# Developer shortcut: dump the loaded world to the console.
			WorldData.print_debug_dump()
			Actors.print_debug_dump()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F5:
			# Quicksave.
			SaveManager.save_to_slot()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F9:
			# Quickload.
			if SaveManager.load_from_slot():
				close_panel()
				_refresh_inbox_visual()
				_refresh_time_display()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F10:
			# Open the Archive (save slots) overlay.
			_open_slots_view()
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
	Notifications.mark_seen(Notifications.KEY_MAP)
	_open_map_view()


func _open_map_view() -> void:
	if _overlay_active:
		return
	_overlay_active = true
	var view: Control = Control.new()
	view.set_script(MapViewScript)
	view.name = "MapView"
	view.anchor_right = 1.0
	view.anchor_bottom = 1.0
	add_child(view)
	view.closed.connect(_on_map_view_closed)


func _on_map_view_closed() -> void:
	_overlay_active = false


# --- Archive (save slots) overlay --------------------------------------------

func _open_slots_view() -> void:
	if _overlay_active:
		return
	_overlay_active = true
	var view: Control = Control.new()
	view.set_script(SlotsViewScript)
	view.name = "SlotsView"
	view.anchor_right = 1.0
	view.anchor_bottom = 1.0
	add_child(view)
	view.closed.connect(_on_slots_view_closed)


func _on_slots_view_closed() -> void:
	_overlay_active = false
	# A load may have changed the world under us; re-seat the table UI.
	close_panel()
	_refresh_inbox_visual()
	_refresh_time_display()


func _on_codebook_clicked() -> void:
	_open_codebook_view()


func _open_codebook_view(anchor: StringName = &"") -> void:
	if _overlay_active:
		return
	_overlay_active = true
	var view: Control = Control.new()
	view.set_script(CodebookViewScript)
	view.name = "CodebookView"
	view.anchor_right = 1.0
	view.anchor_bottom = 1.0
	if anchor != &"":
		view.call("set_anchor", anchor)
	add_child(view)
	view.closed.connect(_on_codebook_view_closed)


func _on_letter_codebook_link_clicked(anchor: StringName) -> void:
	_open_codebook_view(anchor)


func _on_codebook_view_closed() -> void:
	_overlay_active = false


func _on_memoirs_clicked() -> void:
	_open_memoirs_view()


func _open_memoirs_view() -> void:
	if _overlay_active:
		return
	_overlay_active = true
	var view: Control = Control.new()
	view.set_script(MemoirsViewScript)
	view.name = "MemoirsView"
	view.anchor_right = 1.0
	view.anchor_bottom = 1.0
	add_child(view)
	view.closed.connect(_on_memoirs_view_closed)
	view.actor_link_clicked.connect(_on_letter_actor_link_clicked)
	view.codebook_link_clicked.connect(_on_letter_codebook_link_clicked)


func _on_memoirs_view_closed() -> void:
	_overlay_active = false


func _on_public_news_clicked() -> void:
	_open_public_news_view()


func _open_public_news_view() -> void:
	if _overlay_active:
		return
	_overlay_active = true
	var view: Control = Control.new()
	view.set_script(PublicNewsViewScript)
	view.name = "PublicNewsView"
	view.anchor_right = 1.0
	view.anchor_bottom = 1.0
	add_child(view)
	view.closed.connect(_on_public_news_view_closed)
	view.actor_link_clicked.connect(_on_letter_actor_link_clicked)
	view.codebook_link_clicked.connect(_on_letter_codebook_link_clicked)


func _on_public_news_view_closed() -> void:
	_overlay_active = false
	_refresh_public_news_badge()


func _on_ledger_clicked() -> void:
	Notifications.mark_seen(Notifications.KEY_LEDGER)
	_open_ledger_view()


func _open_ledger_view() -> void:
	if _overlay_active:
		return
	_overlay_active = true
	var view: Control = Control.new()
	view.set_script(LedgerViewScript)
	view.name = "LedgerView"
	view.anchor_right = 1.0
	view.anchor_bottom = 1.0
	add_child(view)
	view.closed.connect(_on_ledger_view_closed)


func _on_ledger_view_closed() -> void:
	_overlay_active = false


func _on_dossiers_clicked() -> void:
	Notifications.mark_seen(Notifications.KEY_DOSSIERS)
	_open_dossier_view()


func _open_dossier_view() -> void:
	if _overlay_active:
		return
	_overlay_active = true
	var view: Control = Control.new()
	view.set_script(DossierViewScript)
	view.name = "DossierView"
	view.anchor_right = 1.0
	view.anchor_bottom = 1.0
	add_child(view)
	view.closed.connect(_on_dossier_view_closed)


func _on_dossier_view_closed() -> void:
	_overlay_active = false


func _on_compose_clicked() -> void:
	_open_compose_view()


func _open_compose_view() -> void:
	if _overlay_active:
		return
	_overlay_active = true
	var view: Control = Control.new()
	view.set_script(ComposeViewScript)
	view.name = "ComposeView"
	view.anchor_right = 1.0
	view.anchor_bottom = 1.0
	add_child(view)
	view.closed.connect(_on_compose_view_closed)


func _on_compose_view_closed() -> void:
	_overlay_active = false


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
	view.actor_link_clicked.connect(_on_letter_actor_link_clicked)
	view.codebook_link_clicked.connect(_on_letter_codebook_link_clicked)
	view.display(letter)


func _on_letter_actor_link_clicked(actor_id: StringName) -> void:
	# Letter has emitted the click and is closing itself. We want to open
	# the dossier view on that actor once the letter is gone so overlay
	# state stays consistent.
	var actor: Actor = Actors.get_actor(actor_id)
	if actor == null:
		return
	# Defer one frame so the letter's close tween finishes and
	# _on_letter_view_closed runs first, clearing _overlay_active.
	call_deferred("_open_dossier_view_for_actor", actor)


func _open_dossier_view_for_actor(actor: Actor) -> void:
	if _overlay_active:
		# Still mid-close; try again shortly.
		call_deferred("_open_dossier_view_for_actor", actor)
		return
	_overlay_active = true
	var view: Control = Control.new()
	view.set_script(DossierViewScript)
	view.name = "DossierView"
	view.anchor_right = 1.0
	view.anchor_bottom = 1.0
	add_child(view)
	view.closed.connect(_on_dossier_view_closed)
	view.show_actor(actor)


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


# --- Per-object unread dots --------------------------------------------------
#
# The inbox and news scroll have their own unread badges. The rest of
# the table (ledger, dossiers, map) gets a smaller wax dot tied to the
# Notifications autoload. The dot appears when new material has landed
# and hides when the object is opened.

var _unread_dots: Dictionary = {}  # StringName -> Panel

func _install_object_unread_dots() -> void:
	_unread_dots[Notifications.KEY_LEDGER]   = _make_unread_dot(_ledger)
	_unread_dots[Notifications.KEY_DOSSIERS] = _make_unread_dot(_dossiers)
	_unread_dots[Notifications.KEY_MAP]      = _make_unread_dot(_map)

	Notifications.changed.connect(_refresh_object_unread_dots)
	_refresh_object_unread_dots()


func _make_unread_dot(parent: Control) -> Panel:
	if parent == null:
		return null
	var dot: Panel = Panel.new()
	dot.name = "UnseenDot"
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.anchor_left = 1.0
	dot.anchor_right = 1.0
	dot.anchor_top = 0.0
	dot.anchor_bottom = 0.0
	dot.offset_left = -18.0
	dot.offset_top = -2.0
	dot.offset_right = -4.0
	dot.offset_bottom = 12.0

	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.55, 0.08, 0.08, 1.0)
	sb.corner_radius_top_left = 7
	sb.corner_radius_top_right = 7
	sb.corner_radius_bottom_left = 7
	sb.corner_radius_bottom_right = 7
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	dot.add_theme_stylebox_override("panel", sb)
	dot.visible = false
	parent.add_child(dot)
	return dot


func _refresh_object_unread_dots() -> void:
	for key in _unread_dots.keys():
		var d: Panel = _unread_dots[key]
		if d == null:
			continue
		d.visible = Notifications.has_any(key)
