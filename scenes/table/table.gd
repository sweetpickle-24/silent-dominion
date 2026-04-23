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
const PreferencesViewScript: Script     = preload("res://scripts/preferences_view.gd")
const ArchiveIndicatorScript: Script    = preload("res://scripts/archive_indicator.gd")
const CodebookViewScript: Script        = preload("res://scripts/codebook_view.gd")
const MemoirsViewScript: Script         = preload("res://scripts/memoirs_view.gd")
const RosterViewScript: Script          = preload("res://scripts/roster_view.gd")
const VaultViewScript: Script           = preload("res://scripts/vault_view.gd")
const LibraryViewScript: Script         = preload("res://scripts/library_view.gd")
const LegendIndicatorScript: Script     = preload("res://scripts/legend_indicator.gd")
const ImmortalDialogueViewScript: Script = preload("res://scripts/immortal_dialogue_view.gd")

# --- Node references ----------------------------------------------------------

@onready var _map_scroll: Control     = $Objects/MapScroll
@onready var _inbox: Control          = $Objects/Inbox
@onready var _codebook: Control       = $Objects/Codebook
@onready var _memoirs: Control        = $Objects/Memoirs
@onready var _public_news: Control    = $Objects/PublicNews
@onready var _ledger: Control         = $Objects/Ledger
@onready var _dossiers: Control       = $Objects/Dossiers
@onready var _roster: Control         = $Objects/Roster
@onready var _vault: Control          = $Objects/Vault
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
	_wire_object(_roster, _on_roster_clicked)
	_wire_object(_vault, _on_vault_clicked)
	_wire_object(_compose, _on_compose_clicked)

	_dimmer.gui_input.connect(_on_dimmer_input)
	_close_button.pressed.connect(close_panel)

	Inbox.letters_changed.connect(_refresh_inbox_visual)
	_refresh_inbox_visual()

	# §C5 open the immortal dialogue overlay when an immortal agrees
	# to a live exchange (typically after a successful request_contact).
	Immortals.dialogue_requested.connect(_on_immortal_dialogue_requested)

	_wire_time_dial()
	_install_pending_tray()
	_install_exposure_indicator()
	_install_purse_indicator()
	_install_archive_indicator()
	_install_legend_indicator()
	_install_public_news_badge()
	_install_object_unread_dots()
	_install_inbox_kind_strip()
	# §D4 dim gated table objects until the player has something to
	# read there. Fade each back in when Unlocks signals surface.
	_install_unlock_gating()

	# If the player arrived here via 'Return to X' on the title screen,
	# Session carries the slot to load. Apply it after the scene is
	# fully wired so signal handlers (inbox badge, time dial) are
	# already listening.
	_apply_pending_load()
	Session.in_game = true
	# Kick the scripted-beat checker now that we are in-game. On a fresh
	# campaign this fires the opening letter; on a reload it's a no-op
	# because the fired-set has been restored.
	Beats.check_now()


func _apply_pending_load() -> void:
	var slot: String = Session.consume_pending_load()
	if slot == "":
		# Fresh campaign — apply §10.6 difficulty modifiers that only
		# make sense at new game. Loaded saves already carry their
		# own state so we don't touch them.
		_apply_new_game_difficulty()
		return
	if SaveManager.load_from_slot(slot):
		_refresh_inbox_visual()
		_refresh_time_display()


func _apply_new_game_difficulty() -> void:
	var dp: DifficultyProfile = DifficultyProfile.current()
	var mult: float = dp.starting_purse_multiplier()
	if mult < 1.0 and Purse != null:
		var new_silver: int = int(floor(float(Purse.silver) * mult))
		Purse.silver = maxi(0, new_silver)
	# §10.8 cross-playthrough persistence: fold in legacy imports
	# from prior runs. No-op on first ever campaign.
	if WorldProfile != null:
		var report: Dictionary = WorldProfile.apply_legacy_imports()
		var any_import: bool = (
			int(report.get("entities_imported", 0)) > 0
			or int(report.get("families_imported", 0)) > 0
			or int(report.get("fingerprints_revealed", 0)) > 0
			or bool(report.get("rumour_seeded", false))
		)
		if any_import:
			print("[WorldProfile] legacy import: %s" % report)


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


func _install_legend_indicator() -> void:
	var ind: Control = Control.new()
	ind.set_script(LegendIndicatorScript)
	ind.name = "LegendIndicator"
	ind.anchor_left = 0.0
	ind.anchor_right = 0.0
	ind.anchor_top = 0.0
	ind.anchor_bottom = 0.0
	ind.offset_left = 20.0
	ind.offset_top = 140.0
	ind.offset_right = 280.0
	ind.offset_bottom = 190.0
	ind.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(ind)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	# System-level keys always available, even while an overlay is open.
	match event.keycode:
		KEY_ESCAPE:
			if _panel_layer.visible:
				close_panel()
				get_viewport().set_input_as_handled()
			return
		KEY_F1:
			WorldData.print_debug_dump()
			Actors.print_debug_dump()
			Whispers.debug_dump()
			get_viewport().set_input_as_handled()
			return
		KEY_F5:
			# §10.6 Ironman: manual saves are blocked. Continuous
			# autosave handles persistence; the player doesn't get
			# to pick a moment.
			if Prefs != null and Prefs.ironman:
				push_warning("[Save] Ironman: manual save disabled")
			else:
				SaveManager.save_to_slot()
			get_viewport().set_input_as_handled()
			return
		KEY_F9:
			# §10.6 Ironman: quickload resumes from the latest
			# autosave slot rather than a player-chosen one.
			var slot: String = SaveManager.DEFAULT_SLOT
			if Prefs != null and Prefs.ironman:
				var latest: String = TimeCtl.latest_autosave_slot()
				if latest.is_empty():
					push_warning("[Save] Ironman: no autosave to resume from")
					get_viewport().set_input_as_handled()
					return
				slot = latest
			if SaveManager.load_from_slot(slot):
				close_panel()
				_refresh_inbox_visual()
				_refresh_time_display()
			get_viewport().set_input_as_handled()
			return
		KEY_F10:
			_open_slots_view()
			get_viewport().set_input_as_handled()
			return
		KEY_COMMA:
			if event.ctrl_pressed or event.meta_pressed:
				_open_preferences_view()
				get_viewport().set_input_as_handled()
				return
		KEY_K:
			# Ctrl+Shift+K drafts a chronicle to disk (§10.8).
			if event.ctrl_pressed and event.shift_pressed:
				var path: String = Chronicle.save_to_markdown()
				if not path.is_empty():
					print("[Chronicle] written to ", path)
				get_viewport().set_input_as_handled()
				return
		KEY_F12:
			# Dev-only stress harness (§9.3). F12 = 100 years;
			# Shift+F12 = 500 years; Ctrl+Shift+F12 = save-reload
			# round-trip (100y, save, load, 400y).
			if event.ctrl_pressed and event.shift_pressed:
				StressTest.run_save_roundtrip(100, 400)
			elif event.shift_pressed:
				StressTest.run_years(500)
			else:
				StressTest.run_years(100)
			_refresh_time_display()
			_refresh_inbox_visual()
			get_viewport().set_input_as_handled()
			return
		KEY_G:
			# §9.5 automated playtest arc. Ctrl+Shift+G only so it
			# doesn't collide with the regular G letter shortcut the
			# bare table reserves for future use.
			if event.ctrl_pressed and event.shift_pressed:
				var arc: Dictionary = StressTest.run_growth_arc(500)
				print("[PlaytestArc] completed: %s" % arc)
				_refresh_time_display()
				_refresh_inbox_visual()
				get_viewport().set_input_as_handled()
				return

	# Hotkeys below operate on the bare table. Swallow them while any
	# overlay is open so in-overlay focus/typing isn't hijacked.
	if _overlay_active or _panel_layer.visible:
		return

	# Modifier-bearing shortcuts — only the question-mark sheet needs one.
	if event.shift_pressed and event.keycode == KEY_SLASH:
		open_panel("Shortcuts", _hotkey_sheet_text())
		get_viewport().set_input_as_handled()
		return

	match event.keycode:
		KEY_SPACE:
			_toggle_pause()
			get_viewport().set_input_as_handled()
		KEY_1:
			GameClock.set_speed(GameClock.Speed.DAY)
			get_viewport().set_input_as_handled()
		KEY_2:
			GameClock.set_speed(GameClock.Speed.MONTH)
			get_viewport().set_input_as_handled()
		KEY_I:
			_on_inbox_clicked()
			get_viewport().set_input_as_handled()
		KEY_M:
			_on_map_clicked()
			get_viewport().set_input_as_handled()
		KEY_N:
			_on_public_news_clicked()
			get_viewport().set_input_as_handled()
		KEY_L:
			_on_ledger_clicked()
			get_viewport().set_input_as_handled()
		KEY_D:
			_on_dossiers_clicked()
			get_viewport().set_input_as_handled()
		KEY_O:
			_on_roster_clicked()
			get_viewport().set_input_as_handled()
		KEY_V:
			_on_vault_clicked()
			get_viewport().set_input_as_handled()
		KEY_R:
			_on_memoirs_clicked()
			get_viewport().set_input_as_handled()
		KEY_C:
			_on_compose_clicked()
			get_viewport().set_input_as_handled()
		KEY_B:
			_on_codebook_clicked()
			get_viewport().set_input_as_handled()
		KEY_F:
			_on_library_clicked()
			get_viewport().set_input_as_handled()


# Space toggles between PAUSED and the last non-paused speed. First
# press from a fresh game starts the day dial.
var _last_active_speed: int = -1

## Human-readable list of in-game shortcuts, shown by pressing "?".
func _hotkey_sheet_text() -> String:
	return (
		"Time\n"
		+ "  Space       — pause / resume\n"
		+ "  1           — day by day\n"
		+ "  2           — month by month\n"
		+ "\n"
		+ "Open on the table\n"
		+ "  I           — Inbox\n"
		+ "  R           — Memoirs (letter archive)\n"
		+ "  N           — Public News\n"
		+ "  M           — Map\n"
		+ "  L           — Ledger\n"
		+ "  D           — Dossiers\n"
		+ "  O           — Organisation (Roster)\n"
		+ "  V           — Vault (banking network)\n"
		+ "  C           — Compose a letter\n"
		+ "  B           — Codebook\n"
		+ "  F           — Fingerprint Library (rivals)\n"
		+ "\n"
		+ "System\n"
		+ "  Esc         — close the top overlay\n"
		+ "  F5 / F9     — quicksave / quickload\n"
		+ "  F10         — archive of saved seasons\n"
		+ "  Ctrl + ,    — preferences\n"
		+ "  Ctrl+Shift+K — write a chronicle of this session to disk\n"
		+ "  F12         — fast-forward 100 years (dev stress test)\n"
		+ "  Shift+F12   — fast-forward 500 years\n"
		+ "  Ctrl+Shift+F12 — save/reload round-trip harness\n"
		+ "  Shift + ?   — this list\n"
	)


func _toggle_pause() -> void:
	var current: int = GameClock.speed
	if current == GameClock.Speed.PAUSED:
		var resume_to: int = _last_active_speed
		if resume_to <= GameClock.Speed.PAUSED:
			resume_to = GameClock.Speed.DAY
		GameClock.set_speed(resume_to)
	else:
		_last_active_speed = current
		GameClock.set_speed(GameClock.Speed.PAUSED)


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

	if Prefs.reduced_motion:
		obj.scale = Vector2(target, target)
		return
	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(obj, "scale", Vector2(target, target), OBJECT_TWEEN_TIME)
	_object_tweens[obj] = tw


func _play_open_animation(obj: Control) -> void:
	if _object_tweens.has(obj) and _object_tweens[obj] is Tween:
		(_object_tweens[obj] as Tween).kill()

	if Prefs.reduced_motion:
		obj.scale = Vector2.ONE
		return
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


# --- Preferences overlay ----------------------------------------------------

func _open_preferences_view() -> void:
	if _overlay_active:
		return
	_overlay_active = true
	var view: Control = Control.new()
	view.set_script(PreferencesViewScript)
	view.name = "PreferencesView"
	view.anchor_right = 1.0
	view.anchor_bottom = 1.0
	add_child(view)
	view.closed.connect(_on_preferences_view_closed)


func _on_preferences_view_closed() -> void:
	_overlay_active = false


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
		view.call("set_anchor_id", anchor)
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
	view.actor_link_clicked.connect(_on_letter_actor_link_clicked)
	view.codebook_link_clicked.connect(_on_letter_codebook_link_clicked)


func _on_dossier_view_closed() -> void:
	_overlay_active = false


func _on_roster_clicked() -> void:
	_open_roster_view()


func _open_roster_view() -> void:
	if _overlay_active:
		return
	_overlay_active = true
	var view: Control = Control.new()
	view.set_script(RosterViewScript)
	view.name = "RosterView"
	view.anchor_right = 1.0
	view.anchor_bottom = 1.0
	add_child(view)
	view.closed.connect(_on_roster_view_closed)


func _on_roster_view_closed() -> void:
	_overlay_active = false


func _on_vault_clicked() -> void:
	_open_vault_view()


func _open_vault_view() -> void:
	if _overlay_active:
		return
	_overlay_active = true
	var view: Control = Control.new()
	view.set_script(VaultViewScript)
	view.name = "VaultView"
	view.anchor_right = 1.0
	view.anchor_bottom = 1.0
	add_child(view)
	view.closed.connect(_on_vault_view_closed)


func _on_vault_view_closed() -> void:
	_overlay_active = false


func _on_library_clicked() -> void:
	_open_library_view()


func _open_library_view() -> void:
	if _overlay_active:
		return
	_overlay_active = true
	var view: Control = Control.new()
	view.set_script(LibraryViewScript)
	view.name = "LibraryView"
	view.anchor_right = 1.0
	view.anchor_bottom = 1.0
	add_child(view)
	view.closed.connect(_on_library_view_closed)


func _on_library_view_closed() -> void:
	_overlay_active = false


func _on_immortal_dialogue_requested(immortal_id: StringName, tree: Dictionary) -> void:
	# An overlay-within-overlay would be confusing; if something is
	# already open we drop the dialogue. The peer's opening letter
	# is still delivered separately, so the event is not lost.
	if _overlay_active:
		return
	_overlay_active = true
	var view: Control = Control.new()
	view.set_script(ImmortalDialogueViewScript)
	view.name = "ImmortalDialogueView"
	view.anchor_right = 1.0
	view.anchor_bottom = 1.0
	add_child(view)
	if view.has_method("configure"):
		view.call("configure", immortal_id, tree)
	view.closed.connect(_on_immortal_dialogue_closed)


func _on_immortal_dialogue_closed() -> void:
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
	view.actor_link_clicked.connect(_on_letter_actor_link_clicked)
	view.codebook_link_clicked.connect(_on_letter_codebook_link_clicked)
	view.show_actor(actor)


func _on_letter_view_closed() -> void:
	_overlay_active = false
	for obj in _all_objects():
		_tween_object_scale(obj, 1.0)


func _all_objects() -> Array:
	return [_map_scroll, _inbox, _codebook, _memoirs,
			_public_news, _ledger, _dossiers, _roster, _vault, _compose]


# --- Placeholder panel (map / codebook) ---------------------------------------

func open_panel(title: String, body: String) -> void:
	_panel_title.text = title
	_panel_body.text  = body

	_panel_layer.visible = true
	_panel_layer.modulate.a = 0.0
	_panel.scale = Vector2(0.92, 0.92)
	_panel.pivot_offset = _panel.size * 0.5

	if Prefs.reduced_motion:
		_panel_layer.modulate.a = 1.0
		_panel.scale = Vector2.ONE
		return
	var tw: Tween = create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel_layer, "modulate:a", 1.0, PANEL_TWEEN_TIME)
	tw.tween_property(_panel, "scale", Vector2.ONE, PANEL_TWEEN_TIME)


func close_panel() -> void:
	if not _panel_layer.visible:
		return

	if Prefs.reduced_motion:
		_panel_layer.modulate.a = 0.0
		_panel.scale = Vector2(0.96, 0.96)
		_panel_layer.visible = false
		for obj in _all_objects():
			_tween_object_scale(obj, 1.0)
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

	if unread > 0 and not Prefs.reduced_motion:
		_inbox_badge.pivot_offset = _inbox_badge.size * 0.5
		_badge_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		_badge_tween.tween_property(_inbox_badge, "scale", Vector2(1.12, 1.12), BADGE_PULSE_TIME)
		_badge_tween.tween_property(_inbox_badge, "scale", Vector2.ONE, BADGE_PULSE_TIME)

	_refresh_inbox_kind_strip()


# --- Inbox kind strip --------------------------------------------------------
#
# A tiny row of colored pips under the inbox, one per kind of unread letter
# on the stack. Gives a player a skim-level sense of what's waiting: a green
# pip means a host letter, a blue one means intel, a wax-red means a
# resolved action report, etc. Pips appear left-to-right in a stable kind
# order for scan-ability.

const _KIND_STRIP_ORDER: Array[StringName] = [
	&"action", &"intel", &"host", &"digest", &"news", &"intro", &"misc",
]
var _inbox_kind_strip: HBoxContainer


func _install_inbox_kind_strip() -> void:
	_inbox_kind_strip = HBoxContainer.new()
	_inbox_kind_strip.name = "KindStrip"
	_inbox_kind_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inbox_kind_strip.add_theme_constant_override("separation", 3)
	# Park just under the unread badge. The badge is anchored inside
	# the inbox; positioning in local inbox-space is fine.
	_inbox_kind_strip.position = _inbox_badge.position + Vector2(-4, _inbox_badge.size.y + 4)
	_inbox.add_child(_inbox_kind_strip)
	_refresh_inbox_kind_strip()


func _refresh_inbox_kind_strip() -> void:
	if _inbox_kind_strip == null:
		return
	for child in _inbox_kind_strip.get_children():
		child.queue_free()

	var counts: Dictionary = {}
	for l in Inbox.letters:
		if l.is_read:
			continue
		var k: StringName = l.kind
		counts[k] = int(counts.get(k, 0)) + 1

	if counts.is_empty():
		_inbox_kind_strip.visible = false
		return
	_inbox_kind_strip.visible = true

	for kind in _KIND_STRIP_ORDER:
		var n: int = int(counts.get(kind, 0))
		if n <= 0:
			continue
		_inbox_kind_strip.add_child(_make_kind_pip(kind, n))


func _make_kind_pip(kind: StringName, count: int) -> Control:
	var p: Panel = Panel.new()
	p.custom_minimum_size = Vector2(7.0, 7.0)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = LetterKind.color_for(kind)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 2
	p.add_theme_stylebox_override("panel", sb)
	var label: String = LetterKind.label_for(kind)
	if label == "":
		label = String(kind)
	p.tooltip_text = "%s  x%d" % [label, count]
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


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
	if Eras != null:
		Eras.era_changed.connect(_on_era_changed)
	if Base != null:
		# Base transitions repaint the date tooltip; the state
		# shown there drives the player's situational awareness.
		Base.base_changed.connect(_on_base_state_changed)
		Base.move_started.connect(_on_base_move_started)
		Base.transition_ended.connect(_on_base_transition_ended)

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
	var base_date: String = GameClock.format_date()
	if Eras != null and Eras.current != null:
		_time_date_label.text = "%s  ·  %s" % [base_date, Eras.current.display_name]
		var tooltip: String = Eras.current.blurb
		if Base != null:
			tooltip = "%s\n\n%s" % [Base.headline(), tooltip]
		_time_date_label.tooltip_text = tooltip
	else:
		_time_date_label.text = base_date
		if Base != null:
			_time_date_label.tooltip_text = Base.headline()


func _on_era_changed(_prev: StringName, _new_id: StringName) -> void:
	_refresh_time_display()


func _on_base_state_changed(_old_p: String, _new_p: String) -> void:
	_refresh_time_display()


func _on_base_move_started(_dst: String, _days: int) -> void:
	_refresh_time_display()


func _on_base_transition_ended(_kid: String) -> void:
	_refresh_time_display()


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
	_unread_dots[Notifications.KEY_MAP]      = _make_unread_dot(_map_scroll)

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


# --- §D4 Unlock-gated objects ------------------------------------------------
#
# Memoirs, Vault, Library, and Roster are dimmed until the player has
# something to read there. The gating is a modulate change on the
# object's root Control; input still passes through so the player can
# click a dim object — opening it reveals the welcome card.

const _UNLOCK_DIM_ALPHA: float = 0.32
var _unlock_objects: Dictionary = {}   # StringName -> Control

func _install_unlock_gating() -> void:
	_unlock_objects[Unlocks.ID_MEMOIRS] = _memoirs
	_unlock_objects[Unlocks.ID_VAULT]   = _vault
	_unlock_objects[Unlocks.ID_ROSTER]  = _roster
	# Library lives on the Dossiers object in this build (same panel
	# surface). Dim Dossiers' "Library" affordance via its root; if
	# this layout ever separates them, map the right node here.
	_unlock_objects[Unlocks.ID_LIBRARY] = _dossiers

	for id_any in _unlock_objects.keys():
		var id: StringName = id_any
		var obj: Control = _unlock_objects[id]
		if obj == null:
			continue
		obj.modulate.a = 1.0 if Unlocks.is_surfaced(id) else _UNLOCK_DIM_ALPHA

	Unlocks.surface_unlocked.connect(_on_unlock_surfaced)


func _on_unlock_surfaced(id: StringName) -> void:
	var obj: Control = _unlock_objects.get(id, null)
	if obj == null:
		return
	var tw: Tween = create_tween()
	tw.tween_property(obj, "modulate:a", 1.0, Prefs.anim_duration(0.32))
