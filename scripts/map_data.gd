extends Node
## Autoload: MapData.
##
## Owns the baked bitmap pipeline assets (provinces / terrain / shading
## bitmaps + per-cell metadata) at runtime. Other systems pull from here
## rather than touching files directly.
##
## Lifecycle:
##   1. On _ready(), try to load the three PNGs + cells.json from
##      res://assets/map/generated/ and res://data/.
##   2. If anything is missing AND we're running in the editor, trigger
##      an in-process bake (see run_inline_bake), write the outputs to
##      res://, and proceed. The user commits these files once.
##   3. In an exported build, missing assets are fatal (push_error).
##
## This decoupling means map rendering never does heavy compute inline.

signal map_ready

const BITMAP_DIR:   String = "res://assets/map/generated"
const PROVINCES_PNG: String = "res://assets/map/generated/provinces.png"
const TERRAIN_PNG:   String = "res://assets/map/generated/terrain.png"
const SHADING_PNG:   String = "res://assets/map/generated/shading.png"
const CELLS_JSON:    String = "res://data/map_cells.json"

var provinces_image: Image = null
var terrain_image: Image = null
var shading_image: Image = null
var provinces_texture: ImageTexture = null
var terrain_texture: ImageTexture = null
var shading_texture: ImageTexture = null

var bitmap_w: int = 0
var bitmap_h: int = 0

var cells: Dictionary = {}             # id:int -> MapCell
var cells_by_region: Dictionary = {}   # region_id:String -> Array[int]

var _ready_flag: bool = false


func _ready() -> void:
	DevLogger.write("MapData: ready")
	if not _everything_exists():
		if OS.has_feature("editor"):
			print("[MapData] bitmaps missing. Running inline bake (editor only)...")
			_run_inline_bake()
		else:
			push_error("[MapData] required bitmap assets missing, cannot run map.")
			return

	_load_assets()
	_ready_flag = true
	map_ready.emit()


func is_ready() -> bool:
	return _ready_flag


# --- Asset loading ----------------------------------------------------------

func _everything_exists() -> bool:
	return (
		FileAccess.file_exists(PROVINCES_PNG)
		and FileAccess.file_exists(TERRAIN_PNG)
		and FileAccess.file_exists(SHADING_PNG)
		and FileAccess.file_exists(CELLS_JSON)
	)


func _load_assets() -> void:
	provinces_image = _load_png(PROVINCES_PNG)
	terrain_image   = _load_png(TERRAIN_PNG)
	shading_image   = _load_png(SHADING_PNG)
	if provinces_image == null or terrain_image == null or shading_image == null:
		push_error("[MapData] failed to load one of the baked bitmaps")
		return

	bitmap_w = provinces_image.get_width()
	bitmap_h = provinces_image.get_height()

	# Cell id lookup is via pixel sampling, which needs the image in
	# CPU memory — keep the Image alive. Textures go to the GPU for
	# the shader.
	provinces_texture = ImageTexture.create_from_image(provinces_image)
	terrain_texture   = ImageTexture.create_from_image(terrain_image)
	shading_texture   = ImageTexture.create_from_image(shading_image)

	_load_cells()

	print("[MapData] loaded %d cells, bitmap %dx%d" % [cells.size(), bitmap_w, bitmap_h])


## Read a PNG through FileAccess so res:// paths work at runtime
## without going through the editor's resource importer.
func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img: Image = Image.new()
	var err: int = img.load_png_from_buffer(bytes)
	if err != OK:
		push_error("[MapData] load_png_from_buffer(%s) failed: %d" % [path, err])
		return null
	return img


func _load_cells() -> void:
	cells.clear()
	cells_by_region.clear()

	var raw: String = FileAccess.get_file_as_string(CELLS_JSON)
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_error("[MapData] cells JSON malformed")
		return
	var arr: Variant = (parsed as Dictionary).get("cells", [])
	if not (arr is Array):
		return
	for d in arr:
		if not (d is Dictionary):
			continue
		var c: MapCell = MapCell.from_dict(d)
		cells[c.id] = c
		if not cells_by_region.has(c.region_id):
			cells_by_region[c.region_id] = []
		(cells_by_region[c.region_id] as Array).append(c.id)


# --- Query API --------------------------------------------------------------

## Sample the provinces bitmap at a UV (in [0,1]) and return the cell
## id, or 0 for sea / nothing. UVs outside the texture return 0.
func cell_id_at_uv(uv: Vector2) -> int:
	if provinces_image == null:
		return 0
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return 0
	var px: int = clampi(int(uv.x * float(bitmap_w)), 0, bitmap_w - 1)
	var py: int = clampi(int(uv.y * float(bitmap_h)), 0, bitmap_h - 1)
	var c: Color = provinces_image.get_pixel(px, py)
	var r: int = int(round(c.r * 255.0))
	var g: int = int(round(c.g * 255.0))
	var b: int = int(round(c.b * 255.0))
	return r | (g << 8) | (b << 16)


func get_cell(id: int) -> MapCell:
	return cells.get(id)


func cells_in_region(region_id: String) -> Array:
	return cells_by_region.get(region_id, [])


# --- Inline bake ------------------------------------------------------------

## Runs the full bake in-process. Used when the generated assets are
## missing during editor development. Imports the bake script's logic
## by executing it as a SceneTree... except we're already in one. So
## instead we instantiate a non-SceneTree bake runner and drive it.
func _run_inline_bake() -> void:
	var runner: Node = preload("res://scripts/map_bake_runner.gd").new()
	add_child(runner)
	runner.bake()
	remove_child(runner)
	runner.queue_free()


## A lighter-weight facade other code can call, e.g. a menu action.
func force_rebake() -> void:
	_run_inline_bake()
	_load_assets()
	map_ready.emit()
