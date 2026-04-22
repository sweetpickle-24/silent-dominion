class_name MapGeometry
extends RefCounted
## Single source of truth for the Mediterranean geography.
##
## Holds hand-authored (lon, lat) polygons for landmasses and the
## 25 historical regions, plus the projection constants that map
## those coordinates to a normalised [0, 1] canvas. Both the bake
## script and the runtime map renderer import from here so the
## polygons are never duplicated.

# --- Projection --------------------------------------------------------------
#
# Linear equirectangular projection. The known-world bounding box is
# chosen so the Mediterranean sits comfortably inside a 2:1 aspect.

const MAP_LON_W: float = -10.0
const MAP_LON_E: float =  60.0
const MAP_LAT_N: float =  52.0
const MAP_LAT_S: float =  15.0
const MAP_ASPECT: float = (MAP_LON_E - MAP_LON_W) / (MAP_LAT_N - MAP_LAT_S)


static func ll_to_norm(lon: float, lat: float) -> Vector2:
	var x: float = (lon - MAP_LON_W) / (MAP_LON_E - MAP_LON_W)
	var y: float = (MAP_LAT_N - lat) / (MAP_LAT_N - MAP_LAT_S)
	return Vector2(x, y)


static func latlon_poly_to_norm(pts: Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for v in pts:
		out.append(ll_to_norm(v.x, v.y))
	return out


# --- Landmasses --------------------------------------------------------------

static func latlon_landmasses() -> Array:
	return [
		# Iberia
		[
			Vector2(-9.5, 43.5), Vector2(-8.0, 44.0), Vector2(-4.0, 43.5),
			Vector2(-1.0, 44.0), Vector2( 2.0, 42.5), Vector2( 3.3, 42.0),
			Vector2( 2.0, 41.0), Vector2( 0.5, 40.0), Vector2(-0.5, 39.0),
			Vector2(-1.5, 37.5), Vector2(-3.0, 37.0), Vector2(-5.5, 36.0),
			Vector2(-7.0, 37.0), Vector2(-8.7, 37.5), Vector2(-9.5, 38.5),
			Vector2(-9.0, 41.0),
		],
		# Gaul (greater France)
		[
			Vector2(-5.0, 48.5), Vector2(-1.5, 49.0), Vector2( 2.0, 51.0),
			Vector2( 3.5, 51.0), Vector2( 5.0, 51.0), Vector2( 7.0, 50.5),
			Vector2( 8.0, 49.0), Vector2( 8.0, 47.0), Vector2( 7.0, 45.8),
			Vector2( 6.0, 43.3), Vector2( 3.0, 43.0), Vector2( 1.0, 42.5),
			Vector2(-1.0, 43.0), Vector2(-1.5, 45.0), Vector2(-1.5, 47.0),
			Vector2(-4.0, 48.0),
		],
		# Italy (boot)
		[
			Vector2( 7.0, 44.3), Vector2( 9.0, 44.7), Vector2(10.0, 44.5),
			Vector2(12.0, 45.0), Vector2(13.5, 45.8), Vector2(14.0, 44.5),
			Vector2(14.0, 42.0), Vector2(15.5, 41.8), Vector2(17.0, 41.0),
			Vector2(18.5, 40.5), Vector2(18.0, 40.0), Vector2(17.0, 40.0),
			Vector2(16.5, 38.5), Vector2(15.8, 38.0), Vector2(13.5, 38.5),
			Vector2(11.0, 40.5), Vector2( 9.8, 42.0), Vector2( 8.5, 43.0),
			Vector2( 7.0, 43.7),
		],
		# Sicily
		[
			Vector2(12.5, 38.2), Vector2(15.1, 38.3), Vector2(15.6, 37.5),
			Vector2(15.0, 36.7), Vector2(12.5, 37.2),
		],
		# Sardinia
		[
			Vector2( 8.5, 41.2), Vector2( 9.8, 41.0), Vector2( 9.8, 39.0),
			Vector2( 8.5, 39.2),
		],
		# Corsica
		[
			Vector2( 9.0, 43.0), Vector2( 9.5, 43.0), Vector2( 9.5, 41.5),
			Vector2( 8.7, 41.5),
		],
		# Greek Balkans
		[
			Vector2(13.5, 46.0), Vector2(17.0, 46.0), Vector2(22.0, 44.0),
			Vector2(27.0, 42.0), Vector2(28.5, 41.0), Vector2(27.0, 40.5),
			Vector2(25.0, 40.2), Vector2(23.0, 39.7), Vector2(24.0, 39.0),
			Vector2(24.0, 38.2), Vector2(23.5, 37.8), Vector2(23.5, 37.3),
			Vector2(22.5, 37.1), Vector2(22.8, 36.8), Vector2(22.0, 36.7),
			Vector2(21.5, 37.0), Vector2(21.5, 37.5), Vector2(22.0, 38.0),
			Vector2(21.0, 38.3), Vector2(20.5, 38.8), Vector2(20.0, 39.0),
			Vector2(19.5, 40.0), Vector2(18.5, 42.0), Vector2(17.5, 43.0),
			Vector2(15.5, 44.0),
		],
		# Anatolia
		[
			Vector2(26.0, 40.5), Vector2(27.0, 41.0), Vector2(30.0, 41.2),
			Vector2(35.0, 41.5), Vector2(40.0, 41.5), Vector2(42.0, 41.0),
			Vector2(42.0, 40.0), Vector2(42.0, 38.0), Vector2(42.0, 37.0),
			Vector2(40.0, 37.0), Vector2(37.0, 37.0), Vector2(36.0, 36.0),
			Vector2(32.0, 36.5), Vector2(30.0, 36.5), Vector2(28.0, 36.8),
			Vector2(27.0, 37.5), Vector2(26.2, 38.5), Vector2(26.5, 39.5),
		],
		# Persia / Mesopotamia
		[
			Vector2(42.0, 38.5), Vector2(48.0, 38.0), Vector2(52.0, 37.0),
			Vector2(57.0, 37.0), Vector2(59.0, 35.0), Vector2(59.0, 30.0),
			Vector2(57.0, 26.5), Vector2(55.0, 26.0), Vector2(52.0, 26.5),
			Vector2(51.0, 29.0), Vector2(49.0, 30.0), Vector2(47.0, 30.0),
			Vector2(45.0, 30.0), Vector2(43.0, 31.0), Vector2(42.0, 33.0),
			Vector2(41.0, 36.0),
		],
		# Egypt / Nile
		[
			Vector2(28.0, 31.8), Vector2(32.0, 31.8), Vector2(33.0, 31.0),
			Vector2(33.0, 24.0), Vector2(34.0, 22.0), Vector2(31.0, 22.0),
			Vector2(31.0, 26.0), Vector2(29.0, 29.0), Vector2(28.0, 31.0),
		],
		# North Africa coastal band
		[
			Vector2(-8.0, 36.0), Vector2(-3.0, 36.0), Vector2( 2.0, 37.0),
			Vector2( 5.0, 37.0), Vector2( 8.0, 37.2), Vector2(11.0, 36.7),
			Vector2(14.0, 34.0), Vector2(20.0, 32.0), Vector2(25.0, 31.5),
			Vector2(29.0, 31.2), Vector2(29.0, 28.0), Vector2(25.0, 23.0),
			Vector2(20.0, 22.0), Vector2(15.0, 22.0), Vector2(10.0, 22.0),
			Vector2( 5.0, 22.0), Vector2(-3.0, 22.0), Vector2(-8.0, 25.0),
			Vector2(-9.0, 30.0),
		],
		# Arabian peninsula
		[
			Vector2(33.0, 28.0), Vector2(38.0, 28.0), Vector2(42.0, 27.0),
			Vector2(48.0, 25.0), Vector2(54.0, 25.0), Vector2(58.0, 23.0),
			Vector2(58.0, 18.0), Vector2(54.0, 15.0), Vector2(48.0, 16.0),
			Vector2(42.0, 15.0), Vector2(38.0, 16.0), Vector2(34.0, 22.0),
		],
	]


# --- Regions -----------------------------------------------------------------

static func latlon_regions() -> Dictionary:
	return {
		# --- Italy ----------------------------------------------------------
		"etruria": [
			Vector2(10.0, 44.0), Vector2(11.2, 44.4), Vector2(12.2, 44.2),
			Vector2(12.7, 43.4), Vector2(12.8, 42.6), Vector2(11.8, 42.2),
			Vector2(10.8, 42.4), Vector2(10.2, 42.9), Vector2(10.0, 43.6),
		],
		"latium": [
			Vector2(11.8, 42.2), Vector2(12.8, 42.6), Vector2(14.0, 42.4),
			Vector2(14.2, 41.6), Vector2(13.4, 41.0), Vector2(12.4, 41.0),
			Vector2(11.8, 41.5),
		],
		"campania": [
			Vector2(12.4, 41.0), Vector2(13.4, 41.0), Vector2(14.2, 41.6),
			Vector2(16.5, 41.1), Vector2(18.4, 40.4), Vector2(17.8, 40.0),
			Vector2(17.0, 39.8), Vector2(16.4, 38.6), Vector2(15.6, 38.2),
			Vector2(14.2, 38.4), Vector2(13.0, 39.0), Vector2(12.4, 40.0),
		],
		"sicily": [
			Vector2(12.7, 37.9), Vector2(13.8, 38.3), Vector2(15.1, 38.3),
			Vector2(15.6, 37.5), Vector2(14.8, 36.8), Vector2(13.2, 36.8),
			Vector2(12.6, 37.3),
		],

		# --- Gaul ----------------------------------------------------------
		"gallia_belgica": [
			Vector2( 2.0, 51.0), Vector2( 5.0, 51.0), Vector2( 7.0, 50.5),
			Vector2( 8.0, 49.0), Vector2( 6.0, 48.0), Vector2( 3.5, 48.3),
			Vector2( 2.0, 48.8),
		],
		"gallia_celtica": [
			Vector2(-4.0, 48.0), Vector2(-1.5, 49.0), Vector2( 2.0, 48.8),
			Vector2( 3.5, 48.3), Vector2( 6.0, 48.0), Vector2( 7.0, 46.0),
			Vector2( 5.0, 45.0), Vector2( 2.0, 45.0), Vector2(-1.0, 45.0),
			Vector2(-1.5, 45.5), Vector2(-1.5, 47.0),
		],
		"massalia": [
			Vector2( 3.0, 45.0), Vector2( 5.0, 45.0), Vector2( 7.0, 45.8),
			Vector2( 7.2, 44.4), Vector2( 6.0, 43.4), Vector2( 3.8, 43.1),
			Vector2( 3.0, 43.5),
		],

		# --- Greek Balkans --------------------------------------------------
		"macedon": [
			Vector2(20.0, 41.0), Vector2(21.6, 41.3), Vector2(23.0, 42.0),
			Vector2(24.0, 41.5), Vector2(24.5, 40.5), Vector2(23.0, 40.0),
			Vector2(21.0, 40.2), Vector2(19.8, 40.5),
		],
		"thrace": [
			Vector2(23.0, 42.0), Vector2(27.0, 42.0), Vector2(28.5, 41.0),
			Vector2(27.0, 40.5), Vector2(25.0, 40.2), Vector2(24.0, 40.8),
			Vector2(23.5, 41.3),
		],
		"attica": [
			Vector2(23.0, 38.8), Vector2(23.6, 38.6), Vector2(24.1, 38.4),
			Vector2(24.0, 37.9), Vector2(23.4, 37.7), Vector2(22.9, 38.0),
			Vector2(22.8, 38.4),
		],
		"corinthia": [
			Vector2(22.0, 38.1), Vector2(22.9, 38.0), Vector2(23.0, 37.8),
			Vector2(22.5, 37.6), Vector2(22.0, 37.8),
		],
		"argolis": [
			Vector2(22.5, 37.6), Vector2(23.0, 37.8), Vector2(23.4, 37.7),
			Vector2(23.4, 37.2), Vector2(22.7, 37.0), Vector2(22.5, 37.3),
		],
		"laconia": [
			Vector2(22.0, 37.3), Vector2(22.7, 37.0), Vector2(22.8, 36.7),
			Vector2(21.9, 36.7), Vector2(21.8, 37.0),
		],

		# --- Anatolia / Persia ---------------------------------------------
		"ionia": [
			Vector2(26.0, 39.5), Vector2(26.9, 39.5), Vector2(27.8, 39.5),
			Vector2(28.0, 38.5), Vector2(28.0, 37.5), Vector2(27.2, 37.3),
			Vector2(26.5, 37.4), Vector2(26.0, 38.5),
		],
		"lydia": [
			Vector2(27.8, 39.5), Vector2(30.0, 39.5), Vector2(32.0, 39.5),
			Vector2(32.0, 38.2), Vector2(32.0, 37.3), Vector2(30.0, 37.4),
			Vector2(28.0, 37.5), Vector2(28.0, 38.5),
		],
		"media": [
			Vector2(43.0, 38.5), Vector2(46.0, 38.2), Vector2(50.0, 37.5),
			Vector2(50.0, 36.0), Vector2(50.0, 34.5), Vector2(46.0, 34.5),
			Vector2(43.0, 34.5),
		],
		"persis": [
			Vector2(50.0, 32.0), Vector2(53.0, 32.0), Vector2(57.0, 32.0),
			Vector2(59.0, 30.0), Vector2(57.0, 26.8), Vector2(54.0, 26.0),
			Vector2(52.0, 26.5), Vector2(50.0, 28.5),
		],

		# --- Egypt / North Africa ------------------------------------------
		"lower_egypt": [
			Vector2(29.5, 31.8), Vector2(31.2, 31.9), Vector2(32.5, 31.8),
			Vector2(32.3, 30.5), Vector2(31.8, 29.5), Vector2(30.0, 29.7),
			Vector2(28.5, 30.8),
		],
		"upper_egypt": [
			Vector2(30.0, 29.7), Vector2(31.8, 29.5), Vector2(32.3, 27.0),
			Vector2(33.0, 24.0), Vector2(34.0, 22.0), Vector2(32.8, 22.0),
			Vector2(31.5, 22.0), Vector2(31.0, 25.0), Vector2(29.5, 27.5),
		],
		"africa_proconsularis": [
			Vector2( 7.5, 37.0), Vector2( 9.5, 37.0), Vector2(11.0, 36.7),
			Vector2(12.0, 34.5), Vector2(10.0, 33.2), Vector2( 7.5, 33.5),
			Vector2( 6.5, 34.5), Vector2( 6.5, 36.3),
		],
		"libya_coast": [
			Vector2(13.0, 33.2), Vector2(16.0, 32.5), Vector2(20.0, 32.0),
			Vector2(25.0, 31.5), Vector2(25.0, 27.5), Vector2(20.0, 27.0),
			Vector2(16.0, 28.0), Vector2(13.0, 28.8),
		],

		# --- Seas ----------------------------------------------------------
		"aegean_sea": [
			Vector2(23.5, 40.0), Vector2(25.5, 40.0), Vector2(26.5, 40.0),
			Vector2(27.0, 38.5), Vector2(27.0, 37.5), Vector2(25.5, 36.8),
			Vector2(24.0, 37.2), Vector2(23.5, 38.2),
		],
		"ionian_sea": [
			Vector2(16.8, 40.0), Vector2(18.4, 40.0), Vector2(19.8, 40.0),
			Vector2(20.0, 38.5), Vector2(19.5, 37.2), Vector2(17.8, 36.5),
			Vector2(16.5, 37.0), Vector2(16.8, 38.5),
		],
		"tyrrhenian_sea": [
			Vector2(10.0, 42.8), Vector2(12.0, 43.0), Vector2(13.5, 42.5),
			Vector2(13.5, 40.5), Vector2(12.5, 39.2), Vector2(10.8, 40.0),
			Vector2(10.0, 41.5),
		],
		"black_sea_coast": [
			Vector2(28.0, 45.5), Vector2(34.0, 45.6), Vector2(40.0, 45.5),
			Vector2(41.0, 42.5), Vector2(36.0, 42.3), Vector2(30.0, 41.8),
			Vector2(28.5, 42.0),
		],
	}


## Regions that are sea provinces (no population, used for fleet movement).
static func sea_region_ids() -> Array:
	return ["aegean_sea", "ionian_sea", "tyrrhenian_sea", "black_sea_coast"]


static func is_sea_region(region_id: String) -> bool:
	return region_id in sea_region_ids()


# --- Normalised polygons (convenience) --------------------------------------

static func norm_landmasses() -> Array:
	var out: Array = []
	for poly in latlon_landmasses():
		out.append(latlon_poly_to_norm(poly))
	return out


static func norm_regions() -> Dictionary:
	var out: Dictionary = {}
	var src: Dictionary = latlon_regions()
	for rid in src.keys():
		out[rid] = latlon_poly_to_norm(src[rid])
	return out


# --- Axis-aligned bounding box ----------------------------------------------

static func poly_bbox(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var r: Rect2 = Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


# --- Stable integer index for a kingdom id (for shader palette alpha) -------

## Stable integer index in [0, 255] for a kingdom id. The bake script
## bakes this into the palette alpha channel; the shader reads it back
## for kingdom-border detection. 0 = unclaimed land, 255 = sea.
static func kingdom_index(id: String) -> int:
	match id:
		"__sea__":         return 255
		"athens":          return 1
		"sparta":          return 2
		"corinth":         return 3
		"macedon":         return 4
		"persia":          return 5
		"egypt":           return 6
		"carthage":        return 7
		"rome":            return 8
		"etruscan_league": return 9
		_:                 return 0
