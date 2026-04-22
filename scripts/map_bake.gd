class_name MapBakeJob
extends RefCounted
## Map bake job. Generates the bitmap pipeline assets and writes them
## under res://. Runs inline from MapData on first boot, or manually via
## a CLI entry point.
##
## Outputs:
##   res://assets/map/generated/provinces.png  (RGBA8, RGB encodes cell id)
##   res://assets/map/generated/terrain.png    (RGBA8, RGB = terrain tint)
##   res://assets/map/generated/shading.png    (RGBA8, R = hillshade)
##   res://data/map_cells.json                 (per-cell metadata)
##
## Algorithm:
##   1. Rasterise each region polygon (bbox-restricted point-in-polygon)
##      into a pixel→region_idx grid. Same for the landmass mask.
##   2. Scatter Voronoi seeds inside each region, count proportional to
##      region area. Bucket into a spatial hash.
##   3. Per pixel: region_idx -> nearest seed in that region (fallback
##      to nearest land seed for land pixels outside every region).
##   4. Per pixel: write provinces bitmap (id in RGB), terrain bitmap
##      (terrain-tinted colour + noise), shading bitmap (multi-octave
##      simplex hillshade).
##   5. Write three PNGs + cells JSON.

const OUT_DIR: String = "res://assets/map/generated"
const CELLS_JSON: String = "res://data/map_cells.json"
const LAND_GEOJSON: String = "res://data/natural_earth_mediterranean.json"

# Bitmap resolution. 2048x1024 gives ~1400 px per cell at 1500 cells,
# which holds up fine at 10x zoom. A bigger bitmap scales the bake
# time linearly; 4096x2048 takes ~4x longer.
const BITMAP_W: int = 2048
const BITMAP_H: int = 1024

const TARGET_CELLS_LAND: int = 1200
const TARGET_CELLS_SEA:  int =  300
const MIN_CELLS_PER_REGION: int = 4

const BAKE_SEED: int = 0x5D1E7E53

# Noise warping is still used for INTER-REGION boundaries so that
# hand-drawn region edges look organic, but the coastline itself
# comes straight from Natural Earth and does not get warped (that
# data is already accurate).
const REGION_NOISE_AMP:  float = 18.0
const REGION_NOISE_FREQ: float = 0.010


# --- Terrain palette --------------------------------------------------------

const TERRAIN_PLAINS:    Color = Color(0.70, 0.66, 0.40)
const TERRAIN_FOREST:    Color = Color(0.30, 0.42, 0.22)
const TERRAIN_MOUNTAINS: Color = Color(0.48, 0.42, 0.36)
const TERRAIN_DESERT:    Color = Color(0.92, 0.81, 0.54)
const TERRAIN_COASTAL:   Color = Color(0.80, 0.72, 0.54)
const TERRAIN_HILLS:     Color = Color(0.60, 0.54, 0.34)
const TERRAIN_STEPPE:    Color = Color(0.78, 0.66, 0.40)
const TERRAIN_SEA:       Color = Color(0.32, 0.46, 0.56)
const TERRAIN_WILDERNESS: Color = Color(0.55, 0.52, 0.42)

# Maximum distance (pixels) a land pixel can be from its nearest
# land-region seed before it is classified as "wilderness" — real
# land that no kingdom in our known world claims. Roughly a week's
# ride at the map scale.
const WILDERNESS_MAX_DIST_SQ: float = 140.0 * 140.0

const TERRAIN_ENUM_PLAINS:    int = 0
const TERRAIN_ENUM_FOREST:    int = 1
const TERRAIN_ENUM_MOUNTAINS: int = 2
const TERRAIN_ENUM_DESERT:    int = 3
const TERRAIN_ENUM_COASTAL:   int = 4
const TERRAIN_ENUM_HILLS:     int = 5
const TERRAIN_ENUM_STEPPE:    int = 6


# --- State ------------------------------------------------------------------

var _region_ids: Array[String] = []
var _region_polys: Array = []
var _region_terrain: PackedInt32Array = PackedInt32Array()
var _region_is_sea: PackedByteArray = PackedByteArray()

var _landmass_polys: Array = []

var _region_grid: PackedInt32Array = PackedInt32Array()
var _land_mask: PackedByteArray = PackedByteArray()

var _region_noise_x: FastNoiseLite = null
var _region_noise_y: FastNoiseLite = null

const HASH_W: int = 64
const HASH_H: int = 32
var _seeds_pos: PackedVector2Array = PackedVector2Array()
var _seeds_region_idx: PackedInt32Array = PackedInt32Array()
var _seeds_cell_id: PackedInt32Array = PackedInt32Array()
var _hash: Array = []

var _cell_pixel_count: PackedInt32Array = PackedInt32Array()
var _cell_centroid_sum_x: PackedFloat64Array = PackedFloat64Array()
var _cell_centroid_sum_y: PackedFloat64Array = PackedFloat64Array()
var _cell_neighbor_sets: Array = []


# --- Entry point ------------------------------------------------------------

func run() -> void:
	var t0: int = Time.get_ticks_msec()
	print("[bake] ================ map bake start ================")

	var world_terrain: Dictionary = _read_world_terrains()
	_prepare_regions(world_terrain)
	_prepare_landmasses()
	_init_region_noise()

	# Landmasses first so region rasterisation can skip land-regions
	# for sea pixels and vice-versa.
	print("[bake] rasterising landmasses ...")
	_rasterise_landmasses()

	print("[bake] rasterising regions ...")
	_rasterise_regions()

	print("[bake] placing Voronoi seeds ...")
	_place_seeds()

	print("[bake] building spatial hash ...")
	_build_hash()

	print("[bake] assigning cells + baking bitmaps ...")
	var bytes_out: Dictionary = _bake_pixels()

	print("[bake] writing PNGs ...")
	_ensure_dir(OUT_DIR)
	_save_png(OUT_DIR + "/provinces.png", BITMAP_W, BITMAP_H, Image.FORMAT_RGBA8, bytes_out["provinces"])
	_save_png(OUT_DIR + "/terrain.png",   BITMAP_W, BITMAP_H, Image.FORMAT_RGBA8, bytes_out["terrain"])
	_save_png(OUT_DIR + "/shading.png",   BITMAP_W, BITMAP_H, Image.FORMAT_RGBA8, bytes_out["shading"])

	print("[bake] writing cells JSON ...")
	_write_cells_json()

	var dt: float = float(Time.get_ticks_msec() - t0) / 1000.0
	print("[bake] ================ done in %.1fs ================" % dt)


# --- Preparation ------------------------------------------------------------

func _read_world_terrains() -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists("res://data/world_500bce.json"):
		push_error("[bake] world_500bce.json missing")
		return out
	var raw: String = FileAccess.get_file_as_string("res://data/world_500bce.json")
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return out
	var provinces: Array = (parsed as Dictionary).get("provinces", [])
	for p in provinces:
		if not (p is Dictionary):
			continue
		var rid: String = String(p.get("id", ""))
		if rid.is_empty():
			continue
		out[rid] = _terrain_string_to_enum(String(p.get("terrain", "PLAINS")))
	return out


func _terrain_string_to_enum(s: String) -> int:
	match s.to_upper():
		"PLAINS":    return TERRAIN_ENUM_PLAINS
		"FOREST":    return TERRAIN_ENUM_FOREST
		"MOUNTAINS": return TERRAIN_ENUM_MOUNTAINS
		"DESERT":    return TERRAIN_ENUM_DESERT
		"COASTAL":   return TERRAIN_ENUM_COASTAL
		"HILLS":     return TERRAIN_ENUM_HILLS
		"STEPPE":    return TERRAIN_ENUM_STEPPE
	return TERRAIN_ENUM_PLAINS


func _prepare_regions(world_terrain: Dictionary) -> void:
	_region_ids.clear()
	_region_polys.clear()
	_region_terrain = PackedInt32Array()
	_region_is_sea = PackedByteArray()

	var src: Dictionary = MapGeometry.norm_regions()
	for rid in src.keys():
		_region_ids.append(String(rid))
		_region_polys.append(_norm_poly_to_px(src[rid]))
		_region_terrain.append(int(world_terrain.get(rid, TERRAIN_ENUM_PLAINS)))
		_region_is_sea.append(1 if MapGeometry.is_sea_region(rid) else 0)

	print("[bake]   %d regions prepared" % _region_ids.size())


func _prepare_landmasses() -> void:
	_landmass_polys.clear()
	if not FileAccess.file_exists(LAND_GEOJSON):
		push_error("[bake] Natural Earth land file missing: %s" % LAND_GEOJSON)
		# Fall back to hand polygons so the bake still produces something.
		for norm in MapGeometry.norm_landmasses():
			_landmass_polys.append(_norm_poly_to_px(norm))
		return

	var raw: String = FileAccess.get_file_as_string(LAND_GEOJSON)
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_error("[bake] Natural Earth JSON malformed")
		return
	var polys: Variant = (parsed as Dictionary).get("polygons", [])
	if not (polys is Array):
		return
	var total_verts: int = 0
	for poly in polys:
		if not (poly is Array):
			continue
		var latlon: Array = []
		for pt in poly:
			if not (pt is Array) or (pt as Array).size() < 2:
				continue
			latlon.append(Vector2(float(pt[0]), float(pt[1])))
		if latlon.size() < 3:
			continue
		var norm: PackedVector2Array = MapGeometry.latlon_poly_to_norm(latlon)
		var px: PackedVector2Array = _norm_poly_to_px(norm)
		_landmass_polys.append(px)
		total_verts += px.size()
	print("[bake]   %d landmasses prepared from Natural Earth (%d verts)"
		% [_landmass_polys.size(), total_verts])


func _norm_poly_to_px(norm: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for p in norm:
		out.append(Vector2(p.x * float(BITMAP_W), p.y * float(BITMAP_H)))
	return out


func _init_region_noise() -> void:
	_region_noise_x = FastNoiseLite.new()
	_region_noise_x.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_region_noise_x.seed = BAKE_SEED ^ 0xC0A57
	_region_noise_x.frequency = REGION_NOISE_FREQ
	_region_noise_x.fractal_type = FastNoiseLite.FRACTAL_FBM
	_region_noise_x.fractal_octaves = 3
	_region_noise_x.fractal_lacunarity = 2.1
	_region_noise_x.fractal_gain = 0.55

	_region_noise_y = FastNoiseLite.new()
	_region_noise_y.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_region_noise_y.seed = BAKE_SEED ^ 0xCA57B
	_region_noise_y.frequency = REGION_NOISE_FREQ
	_region_noise_y.fractal_type = FastNoiseLite.FRACTAL_FBM
	_region_noise_y.fractal_octaves = 3
	_region_noise_y.fractal_lacunarity = 2.1
	_region_noise_y.fractal_gain = 0.55


## Returns a small noise-warped query point for INTER-region
## boundaries. We keep hand-drawn region shapes organic without
## touching the Natural-Earth coastline.
func _region_warp(px: float, py: float) -> Vector2:
	var nx: float = _region_noise_x.get_noise_2d(px, py)
	var ny: float = _region_noise_y.get_noise_2d(px, py)
	return Vector2(px + nx * REGION_NOISE_AMP, py + ny * REGION_NOISE_AMP)


# --- Rasterisation ----------------------------------------------------------

func _rasterise_regions() -> void:
	_region_grid.resize(BITMAP_W * BITMAP_H)
	for i in range(_region_grid.size()):
		_region_grid[i] = -1

	var margin: int = int(ceil(REGION_NOISE_AMP)) + 2
	for region_idx in range(_region_ids.size()):
		var poly: PackedVector2Array = _region_polys[region_idx]
		var is_sea: bool = _region_is_sea[region_idx] == 1
		var bbox: Rect2 = MapGeometry.poly_bbox(poly)
		var x0: int = maxi(0, int(floor(bbox.position.x)) - margin)
		var y0: int = maxi(0, int(floor(bbox.position.y)) - margin)
		var x1: int = mini(BITMAP_W, int(ceil(bbox.position.x + bbox.size.x)) + margin)
		var y1: int = mini(BITMAP_H, int(ceil(bbox.position.y + bbox.size.y)) + margin)
		for y in range(y0, y1):
			var row_off: int = y * BITMAP_W
			for x in range(x0, x1):
				if _region_grid[row_off + x] != -1:
					continue
				# Clip against real land mask so land-regions can't
				# claim water and sea-regions can't claim land.
				var is_land_pixel: bool = _land_mask[row_off + x] == 1
				if is_sea and is_land_pixel:
					continue
				if (not is_sea) and not is_land_pixel:
					continue
				var q: Vector2 = _region_warp(float(x) + 0.5, float(y) + 0.5)
				if Geometry2D.is_point_in_polygon(q, poly):
					_region_grid[row_off + x] = region_idx


## Rasterise the Natural-Earth coastline exactly. No warping — the
## source data already captures every fjord and island we care about.
func _rasterise_landmasses() -> void:
	_land_mask.resize(BITMAP_W * BITMAP_H)
	for i in range(_land_mask.size()):
		_land_mask[i] = 0

	for poly in _landmass_polys:
		var bbox: Rect2 = MapGeometry.poly_bbox(poly)
		var x0: int = maxi(0, int(floor(bbox.position.x)))
		var y0: int = maxi(0, int(floor(bbox.position.y)))
		var x1: int = mini(BITMAP_W, int(ceil(bbox.position.x + bbox.size.x)))
		var y1: int = mini(BITMAP_H, int(ceil(bbox.position.y + bbox.size.y)))
		for y in range(y0, y1):
			var row_off: int = y * BITMAP_W
			for x in range(x0, x1):
				if _land_mask[row_off + x] == 1:
					continue
				if Geometry2D.is_point_in_polygon(Vector2(float(x) + 0.5, float(y) + 0.5), poly):
					_land_mask[row_off + x] = 1


# --- Voronoi seeds ----------------------------------------------------------

func _place_seeds() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = BAKE_SEED

	var land_areas: PackedFloat64Array = PackedFloat64Array()
	var sea_areas:  PackedFloat64Array = PackedFloat64Array()
	land_areas.resize(_region_ids.size())
	sea_areas.resize(_region_ids.size())
	var total_land_area: float = 0.0
	var total_sea_area:  float = 0.0
	for region_idx in range(_region_ids.size()):
		var a: float = absf(_polygon_area(_region_polys[region_idx]))
		if _region_is_sea[region_idx] == 1:
			sea_areas[region_idx] = a
			total_sea_area += a
		else:
			land_areas[region_idx] = a
			total_land_area += a

	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(_region_ids.size())
	for region_idx in range(_region_ids.size()):
		var target: int
		if _region_is_sea[region_idx] == 1:
			target = int(round(sea_areas[region_idx] / maxf(total_sea_area, 1.0) * float(TARGET_CELLS_SEA)))
		else:
			target = int(round(land_areas[region_idx] / maxf(total_land_area, 1.0) * float(TARGET_CELLS_LAND)))
		counts[region_idx] = maxi(target, MIN_CELLS_PER_REGION)

	_seeds_pos = PackedVector2Array()
	_seeds_region_idx = PackedInt32Array()
	_seeds_cell_id = PackedInt32Array()
	var next_id: int = 1   # 0 is reserved for void

	for region_idx in range(_region_ids.size()):
		var poly: PackedVector2Array = _region_polys[region_idx]
		var bbox: Rect2 = MapGeometry.poly_bbox(poly)
		var want: int = counts[region_idx]
		var got: int = 0
		var attempts: int = 0
		var max_attempts: int = want * 80
		var min_dist_sq: float = (bbox.size.length() * bbox.size.length()) / maxf(float(want) * 2.2, 1.0)
		while got < want and attempts < max_attempts:
			attempts += 1
			var pt: Vector2 = Vector2(
				rng.randf_range(bbox.position.x, bbox.position.x + bbox.size.x),
				rng.randf_range(bbox.position.y, bbox.position.y + bbox.size.y),
			)
			if not Geometry2D.is_point_in_polygon(pt, poly):
				continue
			# Tiny Poisson-disc reject: no two seeds of the same region
			# closer than min_dist. We only check the last 48 seeds to
			# stay O(N).
			var too_close: bool = false
			var lo: int = maxi(0, _seeds_pos.size() - 48)
			for i in range(_seeds_pos.size() - 1, lo - 1, -1):
				if _seeds_region_idx[i] != region_idx:
					continue
				if _seeds_pos[i].distance_squared_to(pt) < min_dist_sq:
					too_close = true
					break
			if too_close:
				continue
			_seeds_pos.append(pt)
			_seeds_region_idx.append(region_idx)
			_seeds_cell_id.append(next_id)
			next_id += 1
			got += 1

	print("[bake]   placed %d seeds" % _seeds_pos.size())


func _polygon_area(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var a: float = 0.0
	for i in range(poly.size()):
		var j: int = (i + 1) % poly.size()
		a += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	return a * 0.5


# --- Spatial hash + nearest-seed --------------------------------------------

func _build_hash() -> void:
	_hash.resize(HASH_W * HASH_H)
	for i in range(_hash.size()):
		_hash[i] = []
	for i in range(_seeds_pos.size()):
		var gx: int = clampi(int(_seeds_pos[i].x * float(HASH_W) / float(BITMAP_W)), 0, HASH_W - 1)
		var gy: int = clampi(int(_seeds_pos[i].y * float(HASH_H) / float(BITMAP_H)), 0, HASH_H - 1)
		(_hash[gy * HASH_W + gx] as Array).append(i)


## Nearest seed cell id matching a predicate.
##   match_region_idx >= 0: only seeds in that exact region.
##   match_region_idx == -1: seeds where _region_is_sea == want_sea.
##   max_dist_sq > 0: return 0 if nothing is within that squared distance.
func _nearest_cell_id(px: float, py: float, match_region_idx: int, want_sea: int = 0, max_dist_sq: float = 0.0) -> int:
	var cell_w: float = float(BITMAP_W) / float(HASH_W)
	var cell_h: float = float(BITMAP_H) / float(HASH_H)
	var gx: int = clampi(int(px / cell_w), 0, HASH_W - 1)
	var gy: int = clampi(int(py / cell_h), 0, HASH_H - 1)

	var best: float = INF
	var best_id: int = 0
	var radius: int = 0
	var max_radius: int = maxi(HASH_W, HASH_H)
	var min_step: float = minf(cell_w, cell_h)

	while radius <= max_radius:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dy) != radius and absi(dx) != radius:
					continue
				var cx: int = gx + dx
				var cy: int = gy + dy
				if cx < 0 or cy < 0 or cx >= HASH_W or cy >= HASH_H:
					continue
				for si in _hash[cy * HASH_W + cx]:
					var sri: int = _seeds_region_idx[si]
					var ok: bool
					if match_region_idx >= 0:
						ok = (sri == match_region_idx)
					else:
						ok = (_region_is_sea[sri] == want_sea)
					if not ok:
						continue
					var sp: Vector2 = _seeds_pos[si]
					var d: float = (sp.x - px) * (sp.x - px) + (sp.y - py) * (sp.y - py)
					if d < best:
						best = d
						best_id = _seeds_cell_id[si]
		if best_id != 0:
			var step: float = float(radius) * min_step
			if best < step * step:
				break
		radius += 1
	if max_dist_sq > 0.0 and best > max_dist_sq:
		return 0
	return best_id


# --- Bake pass --------------------------------------------------------------

func _bake_pixels() -> Dictionary:
	var noise_terrain: FastNoiseLite = FastNoiseLite.new()
	noise_terrain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_terrain.seed = BAKE_SEED
	noise_terrain.frequency = 0.0035

	var noise_shade: FastNoiseLite = FastNoiseLite.new()
	noise_shade.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_shade.seed = BAKE_SEED ^ 0x1337
	noise_shade.frequency = 0.0060
	noise_shade.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_shade.fractal_octaves = 4

	var n_cells: int = _seeds_pos.size() + 1
	_cell_pixel_count = PackedInt32Array()
	_cell_pixel_count.resize(n_cells)
	_cell_centroid_sum_x = PackedFloat64Array()
	_cell_centroid_sum_x.resize(n_cells)
	_cell_centroid_sum_y = PackedFloat64Array()
	_cell_centroid_sum_y.resize(n_cells)
	_cell_neighbor_sets.resize(n_cells)
	for i in range(n_cells):
		_cell_neighbor_sets[i] = {}

	var provinces_bytes: PackedByteArray = PackedByteArray()
	provinces_bytes.resize(BITMAP_W * BITMAP_H * 4)
	var terrain_bytes:   PackedByteArray = PackedByteArray()
	terrain_bytes.resize(BITMAP_W * BITMAP_H * 4)
	var shading_bytes:   PackedByteArray = PackedByteArray()
	shading_bytes.resize(BITMAP_W * BITMAP_H * 4)

	var prev_row_cells: PackedInt32Array = PackedInt32Array()
	prev_row_cells.resize(BITMAP_W)
	var curr_row_cells: PackedInt32Array = PackedInt32Array()
	curr_row_cells.resize(BITMAP_W)

	var last_pct: int = -1
	for y in range(BITMAP_H):
		var pct: int = int(float(y) / float(BITMAP_H) * 100.0)
		if pct != last_pct and pct % 5 == 0:
			print("[bake]   %d%%" % pct)
			last_pct = pct
		var row_off: int = y * BITMAP_W
		var fy: float = float(y) + 0.5
		var left_cell: int = 0
		for x in range(BITMAP_W):
			var i: int = row_off + x
			var fx: float = float(x) + 0.5
			var region_idx: int = _region_grid[i]
			var is_land: bool = _land_mask[i] == 1

			var cell_id: int = 0
			var is_wilderness: bool = false
			if region_idx >= 0:
				cell_id = _nearest_cell_id(fx, fy, region_idx)
			elif is_land:
				cell_id = _nearest_cell_id(fx, fy, -1, 0, WILDERNESS_MAX_DIST_SQ)
				if cell_id == 0:
					is_wilderness = true

			var b4: int = i * 4
			provinces_bytes[b4 + 0] = cell_id & 0xFF
			provinces_bytes[b4 + 1] = (cell_id >> 8) & 0xFF
			provinces_bytes[b4 + 2] = (cell_id >> 16) & 0xFF
			provinces_bytes[b4 + 3] = 255

			# Terrain comes from the cell's region so unassigned-land
			# pixels still colour correctly once they've been adopted.
			# Wilderness (real land outside any known region) gets a
			# dedicated muted colour so it reads as land but isn't
			# coloured by any kingdom in the political overlay.
			var terr: Color = TERRAIN_SEA
			var is_sea_cell: bool = true
			if cell_id > 0:
				var cri: int = _seeds_region_idx[cell_id - 1]
				is_sea_cell = (_region_is_sea[cri] == 1)
				terr = TERRAIN_SEA if is_sea_cell else _terrain_base(_region_terrain[cri])
			elif is_wilderness:
				terr = TERRAIN_WILDERNESS
				is_sea_cell = false
			var nt: float = noise_terrain.get_noise_2d(fx, fy) * 0.5 + 0.5
			var tint: float = 0.85 + nt * 0.30
			terrain_bytes[b4 + 0] = clampi(int(terr.r * tint * 255.0), 0, 255)
			terrain_bytes[b4 + 1] = clampi(int(terr.g * tint * 255.0), 0, 255)
			terrain_bytes[b4 + 2] = clampi(int(terr.b * tint * 255.0), 0, 255)
			terrain_bytes[b4 + 3] = 255

			var ns: float = noise_shade.get_noise_2d(fx, fy) * 0.5 + 0.5
			var shade: float = 0.35 + ns * 0.65 if is_land else 0.50 + ns * 0.25
			var s8: int = clampi(int(shade * 255.0), 0, 255)
			shading_bytes[b4 + 0] = s8
			shading_bytes[b4 + 1] = s8
			shading_bytes[b4 + 2] = s8
			shading_bytes[b4 + 3] = 255

			if cell_id > 0 and cell_id < n_cells:
				_cell_pixel_count[cell_id] += 1
				_cell_centroid_sum_x[cell_id] += fx
				_cell_centroid_sum_y[cell_id] += fy
				if left_cell > 0 and left_cell != cell_id:
					(_cell_neighbor_sets[cell_id] as Dictionary)[left_cell] = true
					(_cell_neighbor_sets[left_cell] as Dictionary)[cell_id] = true
				var up_cell: int = prev_row_cells[x]
				if up_cell > 0 and up_cell != cell_id:
					(_cell_neighbor_sets[cell_id] as Dictionary)[up_cell] = true
					(_cell_neighbor_sets[up_cell] as Dictionary)[cell_id] = true
			curr_row_cells[x] = cell_id
			left_cell = cell_id

		for x2 in range(BITMAP_W):
			prev_row_cells[x2] = curr_row_cells[x2]

	return {
		"provinces": provinces_bytes,
		"terrain":   terrain_bytes,
		"shading":   shading_bytes,
	}


func _terrain_base(t: int) -> Color:
	match t:
		TERRAIN_ENUM_PLAINS:    return TERRAIN_PLAINS
		TERRAIN_ENUM_FOREST:    return TERRAIN_FOREST
		TERRAIN_ENUM_MOUNTAINS: return TERRAIN_MOUNTAINS
		TERRAIN_ENUM_DESERT:    return TERRAIN_DESERT
		TERRAIN_ENUM_COASTAL:   return TERRAIN_COASTAL
		TERRAIN_ENUM_HILLS:     return TERRAIN_HILLS
		TERRAIN_ENUM_STEPPE:    return TERRAIN_STEPPE
	return TERRAIN_PLAINS


# --- Output -----------------------------------------------------------------

func _ensure_dir(path: String) -> void:
	var d: DirAccess = DirAccess.open("res://")
	if d == null:
		push_error("[bake] cannot open res://")
		return
	if not d.dir_exists(path):
		d.make_dir_recursive(path)


func _save_png(path: String, w: int, h: int, fmt: int, bytes: PackedByteArray) -> void:
	var img: Image = Image.create_from_data(w, h, false, fmt, bytes)
	var err: int = img.save_png(path)
	if err != OK:
		push_error("[bake] save_png failed for %s (err %d)" % [path, err])
	else:
		print("[bake]   wrote %s (%dx%d)" % [path, w, h])


func _write_cells_json() -> void:
	var cells: Array = []
	for i in range(_seeds_pos.size()):
		var cell_id: int = _seeds_cell_id[i]
		var region_idx: int = _seeds_region_idx[i]
		var cx: float
		var cy: float
		if _cell_pixel_count[cell_id] > 0:
			cx = float(_cell_centroid_sum_x[cell_id]) / float(_cell_pixel_count[cell_id])
			cy = float(_cell_centroid_sum_y[cell_id]) / float(_cell_pixel_count[cell_id])
		else:
			cx = _seeds_pos[i].x
			cy = _seeds_pos[i].y
		var neighbors_arr: Array = []
		for nid in (_cell_neighbor_sets[cell_id] as Dictionary).keys():
			neighbors_arr.append(int(nid))
		cells.append({
			"id": cell_id,
			"region_id": _region_ids[region_idx],
			"terrain":   _region_terrain[region_idx],
			"center_uv": [cx / float(BITMAP_W), cy / float(BITMAP_H)],
			"pixel_count": _cell_pixel_count[cell_id],
			"neighbors": neighbors_arr,
		})

	var payload: Dictionary = {
		"_meta": {
			"bitmap_w": BITMAP_W,
			"bitmap_h": BITMAP_H,
			"seed": BAKE_SEED,
			"count": cells.size(),
		},
		"cells": cells,
	}
	var f: FileAccess = FileAccess.open(CELLS_JSON, FileAccess.WRITE)
	if f == null:
		push_error("[bake] cannot open %s for write" % CELLS_JSON)
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	print("[bake]   wrote %s (%d cells)" % [CELLS_JSON, cells.size()])
