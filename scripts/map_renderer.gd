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

# Intelligence layer (§7.4 / §10.3). &"political" is the default
# kingdom-coloured political map. Other modes re-colour each cell by
# a per-province or per-kingdom metric, refreshed whenever the mode
# changes or the underlying data moves enough to matter.
const OVERLAY_POLITICAL: StringName  = &"political"
const OVERLAY_UNREST:    StringName  = &"unrest"
const OVERLAY_PROSPERITY: StringName = &"prosperity"
const OVERLAY_COVER:     StringName  = &"cover"
const OVERLAY_RELIGION:  StringName  = &"religion"
const OVERLAY_RIVALS:    StringName  = &"rivals"
const OVERLAY_MILITARY:  StringName  = &"military"
## §D3 Famine overlay. Surfaces provinces the simulation has marked
## with a `prod_modifier` of cause "famine" (set by UnrestManager /
## random events). The tint also darkens as population drift crosses
## into the PopulationManager "collapse" band, so pre-famine emptying
## still reads as a crisis even without the hard famine tag.
const OVERLAY_FAMINE:    StringName  = &"famine"

var _overlay_mode: StringName = OVERLAY_POLITICAL

# Overlay opacity is driven by a user-adjustable mix (§10.3). Default
# keeps the political skeleton visible so borders stay readable.
# 0.0 → political map. 1.0 → pure metric colour (no base tint).
var _overlay_mix: float = 0.65


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
	# Rebuild the palette when colourblind mode / focus ring flips.
	if Prefs != null and Prefs.has_signal("preferences_changed"):
		Prefs.preferences_changed.connect(refresh_palette)


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
		var base_col: Color = _region_fallback_color(cell)
		var col: Color = base_col
		var k_idx: int = 0
		if MapGeometry.is_sea_region(cell.region_id):
			col = Color(0.26, 0.40, 0.52)
			k_idx = 255
		elif region != null:
			owner_id = region.owning_kingdom
			var kingdom: Kingdom = WorldData.get_kingdom(owner_id)
			if kingdom != null:
				base_col = _kingdom_color(owner_id)
				k_idx = MapGeometry.kingdom_index(owner_id)
			else:
				k_idx = 0
			col = _cell_color_for_mode(cell, region, owner_id, base_col)
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


## Switch the intelligence overlay. Rebuilds the palette in place;
## cheap because we already walk every cell once at startup. Falls
## back to the political map if the mode is unknown.
func set_overlay_mode(mode: StringName) -> void:
	if _overlay_mode == mode:
		return
	_overlay_mode = mode
	_build_palette()


func overlay_mode() -> StringName:
	return _overlay_mode


## Adjust how aggressively the overlay tints the base political map.
## 0.0 = no tint (political map). 1.0 = fully replace with metric.
func set_overlay_mix(mix: float) -> void:
	var clamped: float = clampf(mix, 0.0, 1.0)
	if absf(clamped - _overlay_mix) < 0.001:
		return
	_overlay_mix = clamped
	if _overlay_mode != OVERLAY_POLITICAL:
		_build_palette()


func overlay_mix() -> float:
	return _overlay_mix


# --- Overlay colouring -----------------------------------------------------

# Every non-political mode re-reads live game state to produce a
# per-province tint. `_overlay_mix` controls how far we travel from
# the base political colour toward the metric colour.
func _cell_color_for_mode(_cell: MapCell, province: Province, kingdom_id: String, base_col: Color) -> Color:
	var out: Color = base_col
	match _overlay_mode:
		OVERLAY_POLITICAL:
			out = base_col
		OVERLAY_UNREST:
			out = base_col.lerp(_unrest_color(province), _overlay_mix)
		OVERLAY_PROSPERITY:
			out = base_col.lerp(_prosperity_color(kingdom_id), _overlay_mix)
		OVERLAY_COVER:
			out = base_col.lerp(_cover_color(kingdom_id), _overlay_mix)
		OVERLAY_RELIGION:
			out = base_col.lerp(_religion_color(province), _overlay_mix)
		OVERLAY_RIVALS:
			out = base_col.lerp(_rivals_color(kingdom_id), _overlay_mix)
		OVERLAY_MILITARY:
			out = base_col.lerp(_military_color(kingdom_id), _overlay_mix)
		OVERLAY_FAMINE:
			out = base_col.lerp(_famine_color(province), _overlay_mix)
	# §10.9 colour-blind remap — pass-through in "off" mode. Applied
	# at the dispatcher so every overlay branch benefits without
	# patching each palette function individually.
	return ColorblindPalette.remap_color(out)


## Calm green → raw red. Uses the province's current unrest score,
## clamped to the same 0..100 range the simulation writes.
func _unrest_color(province: Province) -> Color:
	var score: int = 0
	if Unrest != null and province != null:
		score = int(Unrest.get_unrest(province.id))
	var t: float = clampf(float(score) / 100.0, 0.0, 1.0)
	var calm: Color = Color(0.55, 0.72, 0.48)
	var burn: Color = Color(0.82, 0.22, 0.22)
	return calm.lerp(burn, t)


func _prosperity_color(kingdom_id: String) -> Color:
	if kingdom_id.is_empty() or WorldData == null:
		return Color(0.70, 0.68, 0.60)
	var k: Kingdom = WorldData.get_kingdom(kingdom_id)
	if k == null:
		return Color(0.70, 0.68, 0.60)
	match k.treasury_condition:
		Kingdom.TreasuryCondition.FLUSH:    return Color(0.28, 0.58, 0.88)
		Kingdom.TreasuryCondition.STABLE:   return Color(0.48, 0.72, 0.62)
		Kingdom.TreasuryCondition.STRAINED: return Color(0.82, 0.78, 0.32)
		Kingdom.TreasuryCondition.INDEBTED: return Color(0.85, 0.55, 0.28)
		Kingdom.TreasuryCondition.BROKE:    return Color(0.70, 0.20, 0.22)
	return Color(0.70, 0.68, 0.60)


## Cover fidelity: cold (no picture) → current (fresh). Matches the
## phrase labels the dossier header uses.
func _cover_color(kingdom_id: String) -> Color:
	if kingdom_id.is_empty() or Picture == null:
		return Color(0.45, 0.45, 0.48)
	var s: int = Picture.score_for(kingdom_id)
	if s >= 75: return Color(0.48, 0.78, 0.56)  # current
	if s >= 50: return Color(0.82, 0.78, 0.38)  # aging
	if s >= 20: return Color(0.82, 0.52, 0.28)  # stale
	return Color(0.40, 0.40, 0.44)              # cold


## Military strength per kingdom. Combines size (main driver) with
## quality (multiplier) so a small elite force reads louder than a
## big rabble. Cold grey → warm steel.
func _military_color(kingdom_id: String) -> Color:
	if kingdom_id.is_empty() or Armies == null:
		return Color(0.55, 0.55, 0.55)
	var a: Army = Armies.get_army(kingdom_id)
	if a == null:
		return Color(0.55, 0.55, 0.55)
	# Size caps around 40k in the classical era; quality is 0..100.
	var size_f: float = clampf(float(a.size) / 25000.0, 0.0, 1.0)
	var qual_f: float = clampf(float(a.quality) / 100.0, 0.0, 1.0)
	var strength: float = clampf(size_f * 0.75 + qual_f * 0.25, 0.0, 1.0)
	var weak: Color = Color(0.50, 0.52, 0.58)
	var strong: Color = Color(0.78, 0.35, 0.22)
	return weak.lerp(strong, strength)


## Rival-society activity per kingdom. Uses total foothold (the
## player's aggregated knowledge of rival presence) plus a small
## bonus for confirmed-pattern ops in the last two years, so freshly
## exposed nests pop even before foothold catches up. Cool blue →
## hot magenta.
func _rivals_color(kingdom_id: String) -> Color:
	if kingdom_id.is_empty() or Rivals == null or Fingerprints == null:
		return Color(0.45, 0.48, 0.55)
	var foothold: int = int(Rivals.total_foothold_in(kingdom_id))
	var recent: Array = Rivals.recent_ops_in(kingdom_id, 720)
	var hot_ops: int = 0
	for op in recent:
		var op_id: String = String(op.get("op_id", ""))
		if op_id.is_empty():
			continue
		if Fingerprints.level_for(op_id) >= Fingerprints.LEVEL_PATTERN:
			hot_ops += 1
	# Normalise: foothold caps at ~100 per kingdom, ops rarely >6.
	var heat: float = clampf(float(foothold) / 100.0 + float(hot_ops) * 0.12, 0.0, 1.0)
	var cool: Color = Color(0.30, 0.38, 0.52)
	var hot:  Color = Color(0.82, 0.22, 0.68)
	return cool.lerp(hot, heat)


## §D3 Famine overlay colour.
## Fields read:
##   - PopulationManager.is_famine(id): hard famine flag (from meta).
##   - PopulationManager.population_ratio(id): soft decline signal.
## Ochre (healthy) → scorched red (hard famine). Ratio below 0.85
## tints ochre → bone so pre-famine emptying reads as "something is
## wrong with the land" before the simulation stamps the word.
func _famine_color(province: Province) -> Color:
	if province == null or Population == null:
		return Color(0.76, 0.68, 0.40)
	var hard: bool = Population.is_famine(province.id)
	var ratio: float = Population.population_ratio(province.id)
	var ochre: Color = Color(0.82, 0.74, 0.44)       # well-fed
	var bone:  Color = Color(0.70, 0.66, 0.52)       # quiet emptying
	var scorched: Color = Color(0.78, 0.24, 0.18)    # outright famine
	if hard:
		# Blend a touch of bone into scorched if the ratio is still high,
		# so a fresh famine reads louder than a long-running one.
		var severity: float = clampf(1.0 - ratio + 0.2, 0.5, 1.0)
		return bone.lerp(scorched, severity)
	# No hard famine — map the decline band onto ochre→bone.
	var decline: float = clampf((1.0 - ratio) / 0.15, 0.0, 1.0)
	return ochre.lerp(bone, decline)


## Dominant religion per province. Each religion id hashes to a
## stable hue so splits/schisms get related-but-distinct colours.
func _religion_color(province: Province) -> Color:
	if province == null or Religions == null:
		return Color(0.65, 0.60, 0.52)
	var r: Religion = Religions.dominant_in(province.id)
	if r == null:
		return Color(0.60, 0.55, 0.50)
	var h: int = String(r.id).hash()
	# Golden-angle cycle through hues so neighbouring ids don't cluster.
	var hue: float = fposmod(float(h & 0xffffff) / float(0xffffff), 1.0)
	return Color.from_hsv(hue, 0.55, 0.80)


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


func _region_fallback_color(_cell: MapCell) -> Color:
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
