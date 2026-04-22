class_name MapBakeJob
extends RefCounted
## Map bake job. Generates the bitmap pipeline assets and writes them
## under res://. Runs inline from MapData on first boot or manually
## via the CLI entry point `scripts/map_bake_main.gd`.
##
## Outputs:
##   res://assets/map/generated/provinces.png  (RGBA8, RGB = cell id)
##   res://assets/map/generated/terrain.png    (RGBA8, RGB = terrain tint)
##   res://assets/map/generated/shading.png    (RGBA8, R = hillshade)
##   res://data/map_cells.json                 (per-cell metadata)
##
## Pipeline (v3):
##   1. Rasterise the Natural-Earth coastline into a land mask.
##   2. Uniformly Poisson-disc-sample ~N cell seeds across ALL land.
##      Spacing is computed from total land area so cells end up the
##      same size no matter which region they land in.
##   3. Each seed is assigned to the *region* whose centre point is
##      closest (region centres come from `MapGeometry.latlon_regions`).
##   4. Per pixel: nearest seed (bucketed spatial hash) → cell id;
##      terrain = parent region's terrain; kingdom = parent region's
##      owner.
##   5. Sea pixels get cell id 0 — no cells, no borders, no clicks.
##
## The old hand-drawn region polygons are gone. Regions cover all of
## the real land implicitly — no grey holes.

const OUT_DIR: String = "res://assets/map/generated"
const CELLS_JSON: String = "res://data/map_cells.json"
const LAND_GEOJSON: String = "res://data/natural_earth_mediterranean.json"

const BITMAP_W: int = 2048
const BITMAP_H: int = 1024

# Target cell count across the entire visible land area. ~1500 gives
# roughly "CK3 county density" at our bbox scale.
const TARGET_CELLS: int = 1500

const BAKE_SEED: int = 0x5D1E7E53


# --- Terrain palette --------------------------------------------------------

const TERRAIN_PLAINS:    Color = Color(0.72, 0.68, 0.42)
const TERRAIN_FOREST:    Color = Color(0.30, 0.44, 0.22)
const TERRAIN_MOUNTAINS: Color = Color(0.52, 0.46, 0.38)
const TERRAIN_DESERT:    Color = Color(0.92, 0.82, 0.54)
const TERRAIN_COASTAL:   Color = Color(0.80, 0.72, 0.54)
const TERRAIN_HILLS:     Color = Color(0.62, 0.56, 0.34)
const TERRAIN_STEPPE:    Color = Color(0.80, 0.70, 0.44)
const TERRAIN_SEA:       Color = Color(0.28, 0.42, 0.54)

const TERRAIN_ENUM_PLAINS:    int = 0
const TERRAIN_ENUM_FOREST:    int = 1
const TERRAIN_ENUM_MOUNTAINS: int = 2
const TERRAIN_ENUM_DESERT:    int = 3
const TERRAIN_ENUM_COASTAL:   int = 4
const TERRAIN_ENUM_HILLS:     int = 5
const TERRAIN_ENUM_STEPPE:    int = 6


# --- State ------------------------------------------------------------------

var _region_ids: Array[String] = []
var _region_terrain: PackedInt32Array = PackedInt32Array()
var _region_center_px: PackedVector2Array = PackedVector2Array()

var _landmass_polys: Array = []
var _land_mask: PackedByteArray = PackedByteArray()
var _land_pixel_count: int = 0

# Voronoi seeds — one per cell.
var _seeds_pos: PackedVector2Array = PackedVector2Array()
var _seeds_region_idx: PackedInt32Array = PackedInt32Array()
var _seeds_cell_id: PackedInt32Array = PackedInt32Array()

# Spatial hash for nearest-seed queries.
const HASH_W: int = 128
const HASH_H: int = 64
var _hash: Array = []

# Cell -> aggregate stats (built in the bake pass).
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

	print("[bake] rasterising landmasses ...")
	_rasterise_landmasses()

	print("[bake] placing uniform Voronoi seeds ...")
	_place_seeds_uniform()

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
	_region_terrain = PackedInt32Array()
	_region_center_px = PackedVector2Array()

	var src: Dictionary = MapGeometry.latlon_regions()
	for rid in src.keys():
		var r: Dictionary = src[rid]
		_region_ids.append(String(rid))
		# Region terrain: authoritative from MapGeometry; world JSON
		# override if it carries one (keeps old content working).
		var t_str: String = String(r.get("terrain", "PLAINS"))
		var t: int = _terrain_string_to_enum(t_str)
		if world_terrain.has(rid):
			t = int(world_terrain[rid])
		_region_terrain.append(t)
		_region_center_px.append(
			MapGeometry.region_center_px(r, BITMAP_W, BITMAP_H)
		)
	print("[bake]   %d regions prepared" % _region_ids.size())


func _prepare_landmasses() -> void:
	_landmass_polys.clear()
	if not FileAccess.file_exists(LAND_GEOJSON):
		push_error("[bake] Natural Earth land file missing: %s" % LAND_GEOJSON)
		return
	var raw: String = FileAccess.get_file_as_string(LAND_GEOJSON)
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
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


# --- Rasterisation ----------------------------------------------------------

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

	_land_pixel_count = 0
	for i in range(_land_mask.size()):
		_land_pixel_count += _land_mask[i]
	print("[bake]   land mask: %d / %d pixels (%.1f%%)"
		% [_land_pixel_count, _land_mask.size(),
		   100.0 * float(_land_pixel_count) / float(_land_mask.size())])


# --- Uniform Voronoi seeds --------------------------------------------------
#
# Proper Poisson-disc via dart-throwing with a seed spatial hash. All
# existing seeds within a 3x3 hash neighbourhood are checked (not just
# the last N), so accepted seeds really are min_dist apart. This is
# what makes cell sizes uniform.

func _place_seeds_uniform() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = BAKE_SEED

	# Target area per cell — derived from real land area so cells are
	# the same size regardless of which region they end up in.
	var area_per_cell: float = float(_land_pixel_count) / float(TARGET_CELLS)
	# Poisson-disc min distance: a dart-throwing disc that packs to
	# ~hex density yields area ≈ r^2 * sqrt(3) * π / (2π) ≈ r² * 1.5.
	# Back-solving for r and scaling 0.85× accounts for coast wastage.
	var min_dist: float = sqrt(area_per_cell / 1.5) * 0.85
	var min_dist_sq: float = min_dist * min_dist

	print("[bake]   poisson disc: target=%d, min_dist=%.1fpx" % [TARGET_CELLS, min_dist])

	# Spatial hash sized so a 3x3 neighbourhood covers min_dist radius.
	# Cell side = min_dist / sqrt(2) guarantees the 3x3 block fully
	# contains the disc.
	var hash_cell: float = min_dist / sqrt(2.0)
	var hw: int = maxi(1, int(ceil(float(BITMAP_W) / hash_cell)))
	var hh: int = maxi(1, int(ceil(float(BITMAP_H) / hash_cell)))
	var seed_hash: Array = []
	seed_hash.resize(hw * hh)
	for i in range(seed_hash.size()):
		seed_hash[i] = -1  # -1 = empty; one seed per cell max

	_seeds_pos = PackedVector2Array()
	_seeds_region_idx = PackedInt32Array()
	_seeds_cell_id = PackedInt32Array()
	var next_id: int = 1  # cell 0 reserved for sea / void

	var max_attempts: int = TARGET_CELLS * 40
	var attempts: int = 0
	while _seeds_pos.size() < TARGET_CELLS and attempts < max_attempts:
		attempts += 1
		var pt: Vector2 = Vector2(
			rng.randf_range(0.0, float(BITMAP_W)),
			rng.randf_range(0.0, float(BITMAP_H)),
		)
		# Must be on land.
		var ix: int = int(pt.x)
		var iy: int = int(pt.y)
		if ix < 0 or iy < 0 or ix >= BITMAP_W or iy >= BITMAP_H:
			continue
		if _land_mask[iy * BITMAP_W + ix] != 1:
			continue
		# Poisson-disc check against the 3x3 hash neighbourhood.
		var gx: int = clampi(int(pt.x / hash_cell), 0, hw - 1)
		var gy: int = clampi(int(pt.y / hash_cell), 0, hh - 1)
		var too_close: bool = false
		for dy in range(-2, 3):
			if too_close:
				break
			var cy: int = gy + dy
			if cy < 0 or cy >= hh:
				continue
			for dx in range(-2, 3):
				var cx: int = gx + dx
				if cx < 0 or cx >= hw:
					continue
				var neighbor: int = seed_hash[cy * hw + cx]
				if neighbor < 0:
					continue
				if _seeds_pos[neighbor].distance_squared_to(pt) < min_dist_sq:
					too_close = true
					break
		if too_close:
			continue

		# Accept.
		var sid: int = _seeds_pos.size()
		_seeds_pos.append(pt)
		_seeds_region_idx.append(_closest_region_idx(pt))
		_seeds_cell_id.append(next_id)
		next_id += 1
		seed_hash[gy * hw + gx] = sid

	print("[bake]   placed %d seeds (target %d, attempts %d)"
		% [_seeds_pos.size(), TARGET_CELLS, attempts])


func _closest_region_idx(px: Vector2) -> int:
	var best: float = INF
	var best_idx: int = 0
	for i in range(_region_center_px.size()):
		var d: float = _region_center_px[i].distance_squared_to(px)
		if d < best:
			best = d
			best_idx = i
	return best_idx


# --- Spatial hash + nearest-seed --------------------------------------------

func _build_hash() -> void:
	_hash.resize(HASH_W * HASH_H)
	for i in range(_hash.size()):
		_hash[i] = []
	for i in range(_seeds_pos.size()):
		var gx: int = clampi(int(_seeds_pos[i].x * float(HASH_W) / float(BITMAP_W)), 0, HASH_W - 1)
		var gy: int = clampi(int(_seeds_pos[i].y * float(HASH_H) / float(BITMAP_H)), 0, HASH_H - 1)
		(_hash[gy * HASH_W + gx] as Array).append(i)


func _nearest_cell_id(px: float, py: float) -> int:
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
	return best_id


# --- Bake pass --------------------------------------------------------------

func _bake_pixels() -> Dictionary:
	var noise_terrain: FastNoiseLite = FastNoiseLite.new()
	noise_terrain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_terrain.seed = BAKE_SEED
	noise_terrain.frequency = 0.0040

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
			var is_land: bool = _land_mask[i] == 1

			# Sea pixels never get a cell. Shader paints them as water.
			var cell_id: int = 0
			if is_land:
				cell_id = _nearest_cell_id(fx, fy)

			var b4: int = i * 4
			provinces_bytes[b4 + 0] = cell_id & 0xFF
			provinces_bytes[b4 + 1] = (cell_id >> 8) & 0xFF
			provinces_bytes[b4 + 2] = (cell_id >> 16) & 0xFF
			provinces_bytes[b4 + 3] = 255

			# Terrain.
			var terr: Color = TERRAIN_SEA
			if cell_id > 0:
				var cri: int = _seeds_region_idx[cell_id - 1]
				terr = _terrain_base(_region_terrain[cri])
			var nt: float = noise_terrain.get_noise_2d(fx, fy) * 0.5 + 0.5
			var tint: float = 0.85 + nt * 0.30
			terrain_bytes[b4 + 0] = clampi(int(terr.r * tint * 255.0), 0, 255)
			terrain_bytes[b4 + 1] = clampi(int(terr.g * tint * 255.0), 0, 255)
			terrain_bytes[b4 + 2] = clampi(int(terr.b * tint * 255.0), 0, 255)
			terrain_bytes[b4 + 3] = 255

			# Shading: bolder on land, flatter on water.
			var ns: float = noise_shade.get_noise_2d(fx, fy) * 0.5 + 0.5
			var shade: float = 0.35 + ns * 0.65 if is_land else 0.48 + ns * 0.18
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
