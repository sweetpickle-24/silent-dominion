extends Node
## Autoloaded as `Prefs`. Persistent user preferences — time
## controls, autosave behaviour, difficulty, accessibility.
##
## Written to `user://preferences.json` on change. Separate from the
## session save file because preferences follow the player across
## runs; they don't belong inside a specific chronicle.
##
## §10.4 (time controls), §10.6 (difficulty), §10.8 (save
## architecture), §10.9 (accessibility) all converge here.

const PREFS_PATH: String = "user://preferences.json"

signal preferences_changed

# --- Time controls (§10.4) --------------------------------------------------
var auto_pause_on_priority: bool = true

# --- Save architecture (§10.8) ----------------------------------------------
# Continuous autosave taps GameClock.day_passed and writes to a
# rotating pair of slots (A/B) every N in-game days, so a bad write
# never destroys the last good state. Zero disables it outright.
var continuous_autosave: bool = true
var autosave_interval_days: int = 30  # one game-month

# --- Difficulty (§10.6) -----------------------------------------------------
# Ironman gates manual saves. Only autosave + Archive-slot browsing
# remain. When toggled on mid-session the existing quicksave stays on
# disk, but the player can no longer overwrite it.
var ironman: bool = false

# --- Accessibility (§10.9) --------------------------------------------------
var reduced_motion: bool = false
var ui_font_scale: float = 1.0
# Colour-blind mode: "off" | "deuteranopia" | "protanopia" | "tritanopia".
# Remaps overlay hues via `scripts/ui/colorblind_palette.gd`. Default off
# preserves the stock palette entirely.
var colorblind_mode: StringName = &"off"
# Stronger focus ring for keyboard users who can't easily see the default.
var focus_ring_strong: bool = false

# --- Audio (§10.10) ---------------------------------------------------------
var sfx_volume: float = 0.6
var music_volume: float = 0.4
var ambient_volume: float = 0.5
var sfx_enabled: bool = true
var music_enabled: bool = true
var ambient_enabled: bool = true

# --- World persistence (§10.8) ----------------------------------------------
var world_persistence_enabled: bool = true

# --- Difficulty modifiers (§10.6) -------------------------------------------
var aggressive_rivals: bool = false
var lean_start: bool = false
var hostile_hosts: bool = false
var fast_hunters: bool = false
var brittle_cover: bool = false


const DEFAULT_FONT_SIZE: int = 14

func _ready() -> void:
	DevLogger.write("Prefs: ready")
	_load_from_disk()
	_apply_font_scale()
	preferences_changed.connect(_apply_font_scale)


## Scale the root viewport theme's default font size. Any control
## that doesn't override `font_size` inherits from here, so toggling
## the preference resizes most of the UI in one shot. Controls with
## explicit `font_size` overrides (headers, titles) keep their values
## — that's intentional; only the "body text" tier is rescaled.
func _apply_font_scale() -> void:
	var root: Window = get_tree().root
	var theme: Theme = root.theme
	if theme == null:
		theme = Theme.new()
		root.theme = theme
	theme.default_font_size = int(round(float(DEFAULT_FONT_SIZE) * ui_font_scale))


# --- Public setters ---------------------------------------------------------

func set_auto_pause(value: bool) -> void:
	if auto_pause_on_priority == value:
		return
	auto_pause_on_priority = value
	_persist()


func set_continuous_autosave(value: bool) -> void:
	if continuous_autosave == value:
		return
	continuous_autosave = value
	_persist()


func set_autosave_interval(days: int) -> void:
	var clamped: int = clampi(days, 1, 360)
	if autosave_interval_days == clamped:
		return
	autosave_interval_days = clamped
	_persist()


func set_ironman(value: bool) -> void:
	if ironman == value:
		return
	ironman = value
	_persist()


func set_reduced_motion(value: bool) -> void:
	if reduced_motion == value:
		return
	reduced_motion = value
	_persist()


## Public helper: callers pass their default animation length and
## get zero back when the user has opted into reduced motion. Lets
## views call `create_tween().tween_property(..., Prefs.anim_duration(0.18))`
## without sprinkling `if reduced_motion:` branches everywhere.
func anim_duration(base: float) -> float:
	if reduced_motion:
		return 0.0
	return base


## Convenience for a binary switch — returns 1.0 normally and 0.0
## when reduced motion is requested. Useful for anything that wants
## to multiply instead of branch.
func anim_scale() -> float:
	if reduced_motion:
		return 0.0
	return 1.0


func set_ui_font_scale(scale: float) -> void:
	var clamped: float = clampf(scale, 0.75, 1.75)
	if is_equal_approx(ui_font_scale, clamped):
		return
	ui_font_scale = clamped
	_persist()


# --- Audio setters (§10.10) -------------------------------------------------

func set_sfx_volume(v: float) -> void:
	var c: float = clampf(v, 0.0, 1.0)
	if is_equal_approx(sfx_volume, c): return
	sfx_volume = c
	_persist()


func set_music_volume(v: float) -> void:
	var c: float = clampf(v, 0.0, 1.0)
	if is_equal_approx(music_volume, c): return
	music_volume = c
	_persist()


func set_ambient_volume(v: float) -> void:
	var c: float = clampf(v, 0.0, 1.0)
	if is_equal_approx(ambient_volume, c): return
	ambient_volume = c
	_persist()


func set_sfx_enabled(b: bool) -> void:
	if sfx_enabled == b: return
	sfx_enabled = b
	_persist()


func set_music_enabled(b: bool) -> void:
	if music_enabled == b: return
	music_enabled = b
	_persist()


func set_ambient_enabled(b: bool) -> void:
	if ambient_enabled == b: return
	ambient_enabled = b
	_persist()


# --- Accessibility setters (§10.9) ------------------------------------------

func set_colorblind_mode(mode: StringName) -> void:
	var allowed: Array[StringName] = [&"off", &"deuteranopia", &"protanopia", &"tritanopia"]
	if not allowed.has(mode): return
	if colorblind_mode == mode: return
	colorblind_mode = mode
	_persist()


func set_focus_ring_strong(b: bool) -> void:
	if focus_ring_strong == b: return
	focus_ring_strong = b
	_persist()


# --- World persistence setter (§10.8) ---------------------------------------

func set_world_persistence_enabled(b: bool) -> void:
	if world_persistence_enabled == b: return
	world_persistence_enabled = b
	_persist()


# --- Difficulty setters (§10.6) ---------------------------------------------

func set_aggressive_rivals(b: bool) -> void:
	if aggressive_rivals == b: return
	aggressive_rivals = b
	_persist()


func set_lean_start(b: bool) -> void:
	if lean_start == b: return
	lean_start = b
	_persist()


func set_hostile_hosts(b: bool) -> void:
	if hostile_hosts == b: return
	hostile_hosts = b
	_persist()


func set_fast_hunters(b: bool) -> void:
	if fast_hunters == b: return
	fast_hunters = b
	_persist()


func set_brittle_cover(b: bool) -> void:
	if brittle_cover == b: return
	brittle_cover = b
	_persist()


# --- Disk I/O ---------------------------------------------------------------

func _persist() -> void:
	var blob: Dictionary = {
		"auto_pause_on_priority": auto_pause_on_priority,
		"continuous_autosave":    continuous_autosave,
		"autosave_interval_days": autosave_interval_days,
		"ironman":                ironman,
		"reduced_motion":         reduced_motion,
		"ui_font_scale":          ui_font_scale,
		"colorblind_mode":        String(colorblind_mode),
		"focus_ring_strong":      focus_ring_strong,
		"sfx_volume":             sfx_volume,
		"music_volume":           music_volume,
		"ambient_volume":         ambient_volume,
		"sfx_enabled":            sfx_enabled,
		"music_enabled":          music_enabled,
		"ambient_enabled":        ambient_enabled,
		"world_persistence_enabled": world_persistence_enabled,
		"aggressive_rivals":      aggressive_rivals,
		"lean_start":             lean_start,
		"hostile_hosts":          hostile_hosts,
		"fast_hunters":           fast_hunters,
		"brittle_cover":          brittle_cover,
	}
	var f: FileAccess = FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[Prefs] Could not write %s" % PREFS_PATH)
		return
	f.store_string(JSON.stringify(blob, "\t"))
	f.close()
	preferences_changed.emit()


func _load_from_disk() -> void:
	if not FileAccess.file_exists(PREFS_PATH):
		return
	var f: FileAccess = FileAccess.open(PREFS_PATH, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	auto_pause_on_priority = bool(d.get("auto_pause_on_priority", auto_pause_on_priority))
	continuous_autosave    = bool(d.get("continuous_autosave",    continuous_autosave))
	autosave_interval_days = int(d.get("autosave_interval_days",  autosave_interval_days))
	ironman                = bool(d.get("ironman",                ironman))
	reduced_motion         = bool(d.get("reduced_motion",         reduced_motion))
	ui_font_scale          = float(d.get("ui_font_scale",         ui_font_scale))
	colorblind_mode        = StringName(String(d.get("colorblind_mode", String(colorblind_mode))))
	focus_ring_strong      = bool(d.get("focus_ring_strong",      focus_ring_strong))
	sfx_volume             = float(d.get("sfx_volume",            sfx_volume))
	music_volume           = float(d.get("music_volume",          music_volume))
	ambient_volume         = float(d.get("ambient_volume",        ambient_volume))
	sfx_enabled            = bool(d.get("sfx_enabled",            sfx_enabled))
	music_enabled          = bool(d.get("music_enabled",          music_enabled))
	ambient_enabled        = bool(d.get("ambient_enabled",        ambient_enabled))
	world_persistence_enabled = bool(d.get("world_persistence_enabled", world_persistence_enabled))
	aggressive_rivals      = bool(d.get("aggressive_rivals",      aggressive_rivals))
	lean_start             = bool(d.get("lean_start",             lean_start))
	hostile_hosts          = bool(d.get("hostile_hosts",          hostile_hosts))
	fast_hunters           = bool(d.get("fast_hunters",           fast_hunters))
	brittle_cover          = bool(d.get("brittle_cover",          brittle_cover))
