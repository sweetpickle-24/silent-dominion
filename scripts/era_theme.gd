extends Node
## Autoloaded as `EraTheme`. Per-era visual tokens for §10.1, §10.2, §9.1.
##
## Reacts to `Eras.era_changed` and re-emits `theme_changed(era_id)`.
## Registered views get a subtle `modulate` tint applied so the whole
## table shifts tone as the ages turn, without per-view refactors.
##
## Views that want deeper integration can pull tokens directly:
##   - `palette()` / `palette_color(key)`
##   - `typography()`
##   - `map_tint()` / `map_tint_color(key)`
##   - `surface_kind()`  (returns "wax_tablet" | "vellum" | "parchment" | ...)
##
## Surface textures are procedural — see `build_surface_texture(kind)` —
## so no binary assets ship. Safe to call before `_ready` completes:
## all accessors fall back to the `fallback` block in the data file.

signal theme_changed(era_id: StringName)

const DATA_PATH: String = "res://data/eras_theme.json"

var _fallback: Dictionary = {}
var _eras: Dictionary = {} # era_id -> entry
var _registered: Array[Control] = []


func _ready() -> void:
	DevLogger.write("EraTheme: ready")
	_load_data()
	if Eras != null and Eras.has_signal("era_changed"):
		Eras.era_changed.connect(_on_era_changed)
	# First emission — deferred so consumers have finished _ready.
	call_deferred("_emit_current")


# --- Public API --------------------------------------------------------------

func current_id() -> StringName:
	if Eras == null:
		return &""
	return Eras.current_id()


func palette() -> Dictionary:
	return _entry().get("palette", _fallback.get("palette", {}))


func palette_color(key: String, default_col: Color = Color(0.22, 0.14, 0.06, 1.0)) -> Color:
	var p: Dictionary = palette()
	return _to_color(p.get(key, null), default_col)


func typography() -> Dictionary:
	return _entry().get("typography", _fallback.get("typography", {}))


func map_tint() -> Dictionary:
	return _entry().get("map_tint", _fallback.get("map_tint", {}))


func map_tint_color(key: String, default_col: Color = Color(0.76, 0.68, 0.40, 1.0)) -> Color:
	var m: Dictionary = map_tint()
	return _to_color(m.get(key, null), default_col)


func tint_color() -> Color:
	var v: Variant = _entry().get("tint", _fallback.get("tint", [1.0, 1.0, 1.0, 1.0]))
	return _to_color(v, Color(1, 1, 1, 1))


func surface_kind() -> String:
	return String(_entry().get("surface", _fallback.get("surface", "parchment")))


## Register a root view control. Its `modulate` is nudged toward the
## era tint on every transition. De-registers on tree exit.
func register_view(c: Control) -> void:
	if c == null or _registered.has(c):
		return
	_registered.append(c)
	if not c.tree_exited.is_connected(_on_view_gone):
		c.tree_exited.connect(_on_view_gone.bind(c))
	_apply_tint_to(c)


## Generate a procedural surface texture. Returns a tiny
## `GradientTexture2D` suitable for `TextureRect.texture`. Kinds:
##   - wax_tablet: dark, yellow-brown, soft grain
##   - vellum:     warm cream with mottle
##   - parchment:  classic parchment
##   - printed_page: cooler, bluer, printed-looking
##   - ledger_bound: flat modern off-white
func build_surface_texture(kind: String = "") -> GradientTexture2D:
	var k: String = kind if kind != "" else surface_kind()
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	match k:
		"wax_tablet":
			grad.colors = PackedColorArray([
				Color(0.42, 0.28, 0.14, 1.0),
				Color(0.56, 0.38, 0.20, 1.0),
				Color(0.36, 0.24, 0.12, 1.0),
			])
		"vellum":
			grad.colors = PackedColorArray([
				Color(0.94, 0.88, 0.72, 1.0),
				Color(0.90, 0.82, 0.64, 1.0),
				Color(0.82, 0.72, 0.54, 1.0),
			])
		"printed_page":
			grad.colors = PackedColorArray([
				Color(0.97, 0.96, 0.92, 1.0),
				Color(0.92, 0.91, 0.86, 1.0),
				Color(0.88, 0.86, 0.80, 1.0),
			])
		"ledger_bound":
			grad.colors = PackedColorArray([
				Color(0.98, 0.96, 0.92, 1.0),
				Color(0.95, 0.93, 0.88, 1.0),
				Color(0.92, 0.90, 0.85, 1.0),
			])
		_:
			grad.colors = PackedColorArray([
				Color(0.95, 0.90, 0.76, 1.0),
				Color(0.92, 0.86, 0.70, 1.0),
				Color(0.84, 0.76, 0.58, 1.0),
			])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.05, 0.0)
	tex.fill_to   = Vector2(0.95, 1.0)
	tex.width = 256
	tex.height = 256
	return tex


# --- Internals ---------------------------------------------------------------

func _entry() -> Dictionary:
	var id: StringName = current_id()
	if id == &"":
		return _fallback
	return _eras.get(id, _fallback)


func _emit_current() -> void:
	var id: StringName = current_id()
	for c in _registered:
		if is_instance_valid(c):
			_apply_tint_to(c)
	theme_changed.emit(id)


func _on_era_changed(_prev: StringName, new_id: StringName) -> void:
	for c in _registered:
		if is_instance_valid(c):
			_animate_tint_to(c)
	theme_changed.emit(new_id)


func _apply_tint_to(c: Control) -> void:
	c.modulate = tint_color()


func _animate_tint_to(c: Control) -> void:
	var target: Color = tint_color()
	var dur: float = 0.6
	if Prefs != null:
		dur = Prefs.anim_duration(dur)
	if dur <= 0.0:
		c.modulate = target
		return
	var tw: Tween = c.create_tween()
	tw.tween_property(c, "modulate", target, dur)


func _on_view_gone(c: Control) -> void:
	_registered.erase(c)


func _to_color(v: Variant, default_col: Color) -> Color:
	if v is Color:
		return v
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v
		var r: float = float(a[0])
		var g: float = float(a[1])
		var b: float = float(a[2])
		var alpha: float = float(a[3]) if a.size() >= 4 else 1.0
		return Color(r, g, b, alpha)
	return default_col


func _load_data() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("[EraTheme] %s missing — using hardcoded fallback." % DATA_PATH)
		_install_default_fallback()
		return
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		_install_default_fallback()
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_install_default_fallback()
		return
	_fallback = (parsed as Dictionary).get("fallback", {})
	var eras_raw: Variant = (parsed as Dictionary).get("eras", {})
	_eras.clear()
	if eras_raw is Dictionary:
		for key in (eras_raw as Dictionary).keys():
			_eras[StringName(String(key))] = (eras_raw as Dictionary)[key]
	if _fallback.is_empty():
		_install_default_fallback()


func _install_default_fallback() -> void:
	_fallback = {
		"palette": {
			"ink":        [0.22, 0.14, 0.06, 1.0],
			"ink_muted":  [0.22, 0.14, 0.06, 0.65],
			"paper":      [0.96, 0.92, 0.82, 1.0],
			"paper_edge": [0.55, 0.42, 0.28, 0.70],
			"accent":     [0.44, 0.36, 0.14, 1.0],
			"danger":     [0.58, 0.22, 0.12, 1.0],
			"gold":       [0.82, 0.64, 0.22, 1.0],
			"seal_red":   [0.55, 0.08, 0.08, 1.0],
			"shadow":     [0.0, 0.0, 0.0, 0.55],
		},
		"typography": {"title_size": 22, "body_size": 13, "family": "serif", "letter_spacing": 0},
		"map_tint": {
			"province":  [0.76, 0.68, 0.40, 1.0],
			"sea":       [0.22, 0.32, 0.44, 1.0],
			"road":      [0.52, 0.40, 0.22, 1.0],
			"border":    [0.30, 0.22, 0.12, 1.0],
			"parchment": [0.90, 0.84, 0.70, 1.0],
		},
		"tint": [1.0, 1.0, 1.0, 1.0],
		"surface": "parchment",
	}
