extends Control
class_name MapRenderer
## Single-ColorRect GPU map renderer.
##
## Owns:
##   - A ColorRect sized to the logical map canvas (MapData bitmap res).
##   - A ShaderMaterial running map_render.gdshader.
##   - A 1D palette texture indexed by cell id (built in CPU, uploaded
##     as an ImageTexture). RGB = political colour, A = kingdom index.
##
## Drives:
##   - Pan/zoom transform via a parent Control's pivot_offset/scale.
##   - Shader uniforms for zoom, hover/select, palette updates on
##     ownership events.
##
## All of the map's heavy work is per-pixel shading on the GPU; CPU side
## only rebuilds the palette (tiny 1D texture) when owners change.

const SHADER_PATH: String = "res://assets/map/map_render.gdshader"

@export var political_zoom_start: float = 0.9
@export var political_zoom_end:   float = 3.2

var _rect: ColorRect = null
var _material: ShaderMaterial = null
var _palette_image: Image = null
var _palette_texture: ImageTexture = null
var _palette_count: int = 0

var _bitmap_w: int = 0
var _bitmap_h: int = 0

var _hover_cell_id: int = 0
var _select_cell_id: int = 0
var _zoom: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # handled by parent view
	set_clip_contents(false)

	_rect = ColorRect.new()
	_rect.name = "MapColorRect"
	_rect.color = Color(0, 0, 0, 1)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

	if MapData.is_ready():
		_setup()
	else:
		MapData.map_ready.connect(_setup)


func _setup() -> void:
	_bitmap_w = MapData.bitmap_w
	_bitmap_h = MapData.bitmap_h

	_rect.size = Vector2(float(_bitmap_w), float(_bitmap_h))
	custom_minimum_size = _rect.size
	size = _rect.size

	var shader: Shader = load(SHADER_PATH)
	if shader == null:
		push_error("[MapRenderer] shader missing: %s" % SHADER_PATH)
		return
	_material = ShaderMaterial.new()
	_material.shader = shader
	_rect.material = _material

	_material.set_shader_parameter("province_tex", MapData.provinces_texture)
	_material.set_shader_parameter("terrain_tex",  MapData.terrain_texture)
	_material.set_shader_parameter("shading_tex",  MapData.shading_texture)
	_material.set_shader_parameter("bitmap_size",  Vector2(float(_bitmap_w), float(_bitmap_h)))
	_material.set_shader_parameter("political_zoom_start", political_zoom_start)
	_material.set_shader_parameter("political_zoom_end",   political_zoom_end)

	_build_palette()
	_push_view_state()

	if WorldData.has_signal("world_loaded"):
		WorldData.world_loaded.connect(_build_palette)


# --- Palette ---------------------------------------------------------------

## (Re)build the 1D palette from the current WorldData ownership table.
## Called once at startup and whenever province ownership changes. The
## palette size is padded to the next power of two ≥ max cell id, so the
## shader's texture lookup doesn't need a count uniform fight with
## texture() filtering.
func _build_palette() -> void:
	var max_id: int = 0
	for cid in MapData.cells.keys():
		if int(cid) > max_id:
			max_id = int(cid)
	_palette_count = maxi(max_id + 1, 16)
	# Round up to multiple of 4 for tidiness.
	_palette_count = ((_palette_count + 3) / 4) * 4

	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(_palette_count * 4)
	for i in range(bytes.size()):
		bytes[i] = 0

	# palette[0] is the "no cell" slot: deep sea, kingdom index 255
	# so the shader's sea-aware branches treat un-assigned pixels as
	# ocean rather than unclaimed land.
	bytes[0] = 66
	bytes[1] = 102
	bytes[2] = 133
	bytes[3] = 255

	for cid in MapData.cells.keys():
		var cell: MapCell = MapData.cells[cid]
		var region: Province = WorldData.get_province(cell.region_id)
		var owner_id: String = ""
		var col: Color = _region_fallback_color(cell)
		var k_idx: int = 0
		if MapGeometry.is_sea_region(cell.region_id):
			col = Color(0.26, 0.40, 0.52)
			k_idx = 255
		elif region != null:
			owner_id = region.owning_kingdom
			var kingdom: Kingdom = WorldData.get_kingdom(owner_id)
			if kingdom != null:
				col = _kingdom_color(owner_id)
				k_idx = MapGeometry.kingdom_index(owner_id)
			else:
				k_idx = 0
		var off: int = cell.id * 4
		if off + 3 < bytes.size():
			bytes[off + 0] = int(col.r * 255.0)
			bytes[off + 1] = int(col.g * 255.0)
			bytes[off + 2] = int(col.b * 255.0)
			bytes[off + 3] = k_idx

	_palette_image = Image.create_from_data(_palette_count, 1, false, Image.FORMAT_RGBA8, bytes)
	_palette_texture = ImageTexture.create_from_image(_palette_image)
	if _material != null:
		_material.set_shader_parameter("palette_tex", _palette_texture)
		_material.set_shader_parameter("palette_count", float(_palette_count))


## Public: let outer systems force a palette refresh after mutating
## province ownership.
func refresh_palette() -> void:
	_build_palette()


func _kingdom_color(id: String) -> Color:
	match id:
		"athens":          return Color(0.60, 0.48, 0.75)
		"sparta":          return Color(0.75, 0.28, 0.30)
		"corinth":         return Color(0.25, 0.62, 0.60)
		"macedon":         return Color(0.82, 0.68, 0.30)
		"persia":          return Color(0.28, 0.50, 0.78)
		"egypt":           return Color(0.92, 0.86, 0.58)
		"carthage":        return Color(0.60, 0.20, 0.22)
		"rome":            return Color(0.88, 0.52, 0.30)
		"etruscan_league": return Color(0.40, 0.58, 0.32)
		"thebes":          return Color(0.55, 0.40, 0.22)
		"syracuse":        return Color(0.52, 0.72, 0.62)
		"massalia":        return Color(0.42, 0.60, 0.78)
		"odrysia":         return Color(0.72, 0.55, 0.32)
		"molossia":        return Color(0.60, 0.50, 0.28)
		"colchis":         return Color(0.48, 0.58, 0.70)
		"nabatea":         return Color(0.74, 0.58, 0.38)
		"kush":            return Color(0.55, 0.35, 0.28)
		"cyrene":          return Color(0.68, 0.78, 0.52)
		"tartessos":       return Color(0.68, 0.42, 0.36)
	return Color(0.70, 0.65, 0.52)


func _region_fallback_color(cell: MapCell) -> Color:
	# Used when no owner is set (unclaimed tribal land). A muted parchment.
	return Color(0.78, 0.72, 0.54)


# --- View / zoom --------------------------------------------------------------

func set_view_zoom(z: float) -> void:
	_zoom = z
	_push_view_state()


func set_hover_cell(id: int) -> void:
	_hover_cell_id = id
	_push_view_state()


func set_selected_cell(id: int) -> void:
	_select_cell_id = id
	_push_view_state()


func bitmap_size() -> Vector2:
	return Vector2(float(_bitmap_w), float(_bitmap_h))


func _push_view_state() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("zoom", _zoom)
	_material.set_shader_parameter("hover_id",  _hover_cell_id)
	_material.set_shader_parameter("select_id", _select_cell_id)
