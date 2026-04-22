class_name MapGeometry
extends RefCounted
## Single source of truth for the Mediterranean/Middle East atlas.
##
## We no longer hand-author region polygons. The new pipeline is:
##
##   1. Rasterise the real Natural-Earth coastline into a land mask.
##   2. Scatter Voronoi cell seeds uniformly across land (Poisson-disc).
##   3. Each seed is assigned the *region* whose centre point is closest.
##   4. Each region is owned by one *kingdom* (or no one).
##
## All a region is, then, is a named (lat, lon) anchor point + terrain +
## starting owner. Regions cover the whole map implicitly — no grey
## holes, no hand-drawn polygons to keep in sync with reality.
##
## Historical context: starting date is 500 BCE. Achaemenid Persia
## (Darius I) is enormous; Rome is a freshly-minted republic on a tiny
## patch of Latium; Greek city-states are scattered across a hundred
## valleys; Carthage owns the sea-lanes of the western Med. Tribal
## regions outside any empire get a descriptive name and are left
## unclaimed — they still simulate, just at low fidelity per §8.1.

# --- Projection --------------------------------------------------------------
#
# Linear equirectangular. The bbox is chosen so the Mediterranean /
# Middle East sits in a 2:1 canvas with room for Gallia Belgica up
# north and the first slice of Arabia + Nubia down south.

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


# --- Bounding box ------------------------------------------------------------

static func poly_bbox(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var r: Rect2 = Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


# --- Region atlas ------------------------------------------------------------
#
# Every entry is an anchor point roughly at a historical capital or
# regional heartland. Terrain and owning_kingdom are authoritative —
# they drive the shader palette and starting politics.
#
# Format: { id: { lat, lon, name, terrain, kingdom } }
#   terrain ∈ PLAINS | FOREST | MOUNTAINS | DESERT | COASTAL | HILLS | STEPPE
#   kingdom "" = tribal / unclaimed land

static func latlon_regions() -> Dictionary:
	return {
		# --- Iberia --------------------------------------------------------
		"baetica":         {"lat": 37.40, "lon":  -4.50, "name": "Baetica",         "terrain": "HILLS",     "kingdom": "tartessos"},
		"lusitania":       {"lat": 39.50, "lon":  -8.00, "name": "Lusitania",       "terrain": "HILLS",     "kingdom": ""},
		"celtiberia":      {"lat": 41.00, "lon":  -3.00, "name": "Celtiberia",      "terrain": "MOUNTAINS", "kingdom": ""},
		"iberia_east":     {"lat": 39.30, "lon":   0.20, "name": "Iberia Orientalis","terrain": "COASTAL",  "kingdom": ""},
		"gades":           {"lat": 36.50, "lon":  -6.00, "name": "Gaditania",       "terrain": "COASTAL",   "kingdom": "carthage"},

		# --- Gaul ----------------------------------------------------------
		"gallia_aquitania":{"lat": 44.80, "lon":  -0.50, "name": "Gallia Aquitania","terrain": "FOREST",    "kingdom": ""},
		"gallia_celtica":  {"lat": 46.80, "lon":   2.50, "name": "Gallia Celtica",  "terrain": "FOREST",    "kingdom": ""},
		"gallia_belgica":  {"lat": 50.00, "lon":   4.00, "name": "Gallia Belgica",  "terrain": "FOREST",    "kingdom": ""},
		"massalia":        {"lat": 43.30, "lon":   5.40, "name": "Massalia",        "terrain": "COASTAL",   "kingdom": "massalia"},
		"narbonensis":     {"lat": 43.60, "lon":   3.20, "name": "Narbonensis",     "terrain": "HILLS",     "kingdom": ""},

		# --- Alps / Central Europe ----------------------------------------
		"raetia":          {"lat": 47.20, "lon":  10.20, "name": "Raetia",          "terrain": "MOUNTAINS", "kingdom": ""},
		"noricum":         {"lat": 47.30, "lon":  14.50, "name": "Noricum",         "terrain": "MOUNTAINS", "kingdom": ""},
		"germania":        {"lat": 50.30, "lon":  10.00, "name": "Germania Magna",  "terrain": "FOREST",    "kingdom": ""},
		"pannonia":        {"lat": 47.20, "lon":  18.00, "name": "Pannonia",        "terrain": "PLAINS",    "kingdom": ""},
		"dacia":           {"lat": 45.70, "lon":  25.00, "name": "Dacia",           "terrain": "FOREST",    "kingdom": ""},
		"sarmatia":        {"lat": 49.00, "lon":  40.00, "name": "Sarmatia",        "terrain": "STEPPE",    "kingdom": ""},
		"scythia":         {"lat": 47.50, "lon":  33.00, "name": "Scythia",         "terrain": "STEPPE",    "kingdom": ""},

		# --- Italy ---------------------------------------------------------
		"liguria":         {"lat": 44.40, "lon":   8.90, "name": "Liguria",         "terrain": "HILLS",     "kingdom": ""},
		"cisalpine_gaul":  {"lat": 45.20, "lon":   9.50, "name": "Gallia Cisalpina","terrain": "PLAINS",    "kingdom": ""},
		"venetia":         {"lat": 45.40, "lon":  12.00, "name": "Venetia",         "terrain": "PLAINS",    "kingdom": ""},
		"etruria":         {"lat": 43.10, "lon":  11.30, "name": "Etruria",         "terrain": "HILLS",     "kingdom": "etruscan_league"},
		"umbria":          {"lat": 43.10, "lon":  12.60, "name": "Umbria",          "terrain": "HILLS",     "kingdom": ""},
		"picenum":         {"lat": 43.00, "lon":  13.70, "name": "Picenum",         "terrain": "HILLS",     "kingdom": ""},
		"latium":          {"lat": 41.90, "lon":  12.50, "name": "Latium",          "terrain": "PLAINS",    "kingdom": "rome"},
		"samnium":         {"lat": 41.50, "lon":  14.50, "name": "Samnium",         "terrain": "MOUNTAINS", "kingdom": ""},
		"campania":        {"lat": 40.90, "lon":  14.20, "name": "Campania",        "terrain": "PLAINS",    "kingdom": "etruscan_league"},
		"apulia":          {"lat": 41.10, "lon":  16.50, "name": "Apulia",          "terrain": "PLAINS",    "kingdom": ""},
		"lucania":         {"lat": 40.30, "lon":  15.80, "name": "Lucania",         "terrain": "MOUNTAINS", "kingdom": ""},
		"magna_graecia":   {"lat": 40.20, "lon":  17.20, "name": "Magna Graecia",   "terrain": "COASTAL",   "kingdom": ""},
		"calabria":        {"lat": 38.80, "lon":  16.20, "name": "Calabria",        "terrain": "MOUNTAINS", "kingdom": ""},
		"sicily_west":     {"lat": 37.80, "lon":  12.80, "name": "Sicilia Poena",   "terrain": "HILLS",     "kingdom": "carthage"},
		"sicily_east":     {"lat": 37.10, "lon":  14.70, "name": "Syracusa",        "terrain": "PLAINS",    "kingdom": "syracuse"},
		"sardinia":        {"lat": 40.10, "lon":   9.10, "name": "Sardinia",        "terrain": "HILLS",     "kingdom": "carthage"},
		"corsica":         {"lat": 42.20, "lon":   9.10, "name": "Corsica",         "terrain": "MOUNTAINS", "kingdom": ""},

		# --- Balkans / Illyria --------------------------------------------
		"illyria":         {"lat": 43.50, "lon":  17.50, "name": "Illyria",         "terrain": "MOUNTAINS", "kingdom": ""},
		"epirus":          {"lat": 39.50, "lon":  20.70, "name": "Epirus",          "terrain": "MOUNTAINS", "kingdom": "molossia"},
		"macedon":         {"lat": 40.70, "lon":  22.40, "name": "Macedon",         "terrain": "MOUNTAINS", "kingdom": "macedon"},
		"thrace":          {"lat": 42.00, "lon":  26.00, "name": "Thrace",          "terrain": "PLAINS",    "kingdom": "odrysia"},

		# --- Greek mainland -----------------------------------------------
		"thessaly":        {"lat": 39.60, "lon":  22.40, "name": "Thessaly",        "terrain": "PLAINS",    "kingdom": ""},
		"aetolia":         {"lat": 38.60, "lon":  21.70, "name": "Aetolia",         "terrain": "HILLS",     "kingdom": ""},
		"phocis":          {"lat": 38.50, "lon":  22.50, "name": "Phocis",          "terrain": "MOUNTAINS", "kingdom": ""},
		"boeotia":         {"lat": 38.30, "lon":  23.30, "name": "Boeotia",         "terrain": "PLAINS",    "kingdom": "thebes"},
		"attica":          {"lat": 38.00, "lon":  23.73, "name": "Attica",          "terrain": "HILLS",     "kingdom": "athens"},
		"euboea":          {"lat": 38.55, "lon":  23.85, "name": "Euboea",          "terrain": "HILLS",     "kingdom": ""},
		"corinthia":       {"lat": 37.94, "lon":  22.94, "name": "Corinthia",       "terrain": "COASTAL",   "kingdom": "corinth"},
		"argolis":         {"lat": 37.55, "lon":  22.72, "name": "Argolis",         "terrain": "HILLS",     "kingdom": "corinth"},
		"arcadia":         {"lat": 37.58, "lon":  22.30, "name": "Arcadia",         "terrain": "MOUNTAINS", "kingdom": ""},
		"achaea":          {"lat": 38.20, "lon":  22.00, "name": "Achaea",          "terrain": "COASTAL",   "kingdom": ""},
		"laconia":         {"lat": 37.07, "lon":  22.43, "name": "Laconia",         "terrain": "MOUNTAINS", "kingdom": "sparta"},
		"messenia":        {"lat": 37.05, "lon":  21.93, "name": "Messenia",        "terrain": "HILLS",     "kingdom": "sparta"},
		"crete":           {"lat": 35.20, "lon":  24.90, "name": "Crete",           "terrain": "HILLS",     "kingdom": ""},
		"cyclades":        {"lat": 37.00, "lon":  25.40, "name": "Cyclades",        "terrain": "COASTAL",   "kingdom": ""},

		# --- Anatolia (Persian satrapies) ---------------------------------
		"bithynia":        {"lat": 40.50, "lon":  30.20, "name": "Bithynia",        "terrain": "FOREST",    "kingdom": "persia"},
		"paphlagonia":     {"lat": 41.40, "lon":  33.80, "name": "Paphlagonia",     "terrain": "MOUNTAINS", "kingdom": "persia"},
		"pontus":          {"lat": 41.00, "lon":  36.30, "name": "Pontus",          "terrain": "FOREST",    "kingdom": "persia"},
		"phrygia":         {"lat": 39.20, "lon":  31.00, "name": "Phrygia",         "terrain": "PLAINS",    "kingdom": "persia"},
		"cappadocia":      {"lat": 38.70, "lon":  34.50, "name": "Cappadocia",      "terrain": "STEPPE",    "kingdom": "persia"},
		"lydia":           {"lat": 38.50, "lon":  28.00, "name": "Lydia",           "terrain": "PLAINS",    "kingdom": "persia"},
		"ionia":           {"lat": 37.80, "lon":  27.20, "name": "Ionia",           "terrain": "COASTAL",   "kingdom": "persia"},
		"caria":           {"lat": 37.00, "lon":  28.20, "name": "Caria",           "terrain": "HILLS",     "kingdom": "persia"},
		"lycia":           {"lat": 36.40, "lon":  29.80, "name": "Lycia",           "terrain": "MOUNTAINS", "kingdom": "persia"},
		"pamphylia":       {"lat": 36.90, "lon":  31.00, "name": "Pamphylia",       "terrain": "COASTAL",   "kingdom": "persia"},
		"cilicia":         {"lat": 37.00, "lon":  34.60, "name": "Cilicia",         "terrain": "COASTAL",   "kingdom": "persia"},

		# --- Caucasus ------------------------------------------------------
		"armenia":         {"lat": 39.90, "lon":  43.50, "name": "Armenia",         "terrain": "MOUNTAINS", "kingdom": "persia"},
		"colchis":         {"lat": 42.50, "lon":  41.70, "name": "Colchis",         "terrain": "MOUNTAINS", "kingdom": "colchis"},
		"albania_caucasus":{"lat": 40.80, "lon":  46.80, "name": "Caucasian Albania","terrain": "MOUNTAINS","kingdom": ""},

		# --- Levant (Persian) ---------------------------------------------
		"syria":           {"lat": 35.50, "lon":  37.00, "name": "Syria",           "terrain": "STEPPE",    "kingdom": "persia"},
		"phoenicia":       {"lat": 33.50, "lon":  35.50, "name": "Phoenicia",       "terrain": "COASTAL",   "kingdom": "persia"},
		"judea":           {"lat": 31.80, "lon":  35.20, "name": "Judea",           "terrain": "HILLS",     "kingdom": "persia"},
		"nabatea":         {"lat": 30.30, "lon":  35.50, "name": "Nabatea",         "terrain": "DESERT",    "kingdom": "nabatea"},

		# --- Mesopotamia / Iran (Persian) ---------------------------------
		"assyria":         {"lat": 36.30, "lon":  43.10, "name": "Assyria",         "terrain": "PLAINS",    "kingdom": "persia"},
		"babylonia":       {"lat": 32.50, "lon":  44.50, "name": "Babylonia",       "terrain": "PLAINS",    "kingdom": "persia"},
		"elam":            {"lat": 32.20, "lon":  48.30, "name": "Elam",            "terrain": "PLAINS",    "kingdom": "persia"},
		"media":           {"lat": 34.80, "lon":  48.50, "name": "Media",           "terrain": "MOUNTAINS", "kingdom": "persia"},
		"persis":          {"lat": 29.90, "lon":  52.90, "name": "Persis",          "terrain": "MOUNTAINS", "kingdom": "persia"},
		"hyrcania":        {"lat": 36.50, "lon":  54.30, "name": "Hyrcania",        "terrain": "FOREST",    "kingdom": "persia"},
		"parthia":         {"lat": 35.90, "lon":  57.00, "name": "Parthia",         "terrain": "STEPPE",    "kingdom": "persia"},

		# --- Arabia --------------------------------------------------------
		"arabia_petraea":  {"lat": 29.00, "lon":  38.00, "name": "Arabia Petraea",  "terrain": "DESERT",    "kingdom": ""},
		"arabia_deserta":  {"lat": 26.00, "lon":  44.00, "name": "Arabia Deserta",  "terrain": "DESERT",    "kingdom": ""},
		"arabia_felix":    {"lat": 18.50, "lon":  46.00, "name": "Arabia Felix",    "terrain": "DESERT",    "kingdom": ""},

		# --- Egypt / Nubia ------------------------------------------------
		"lower_egypt":     {"lat": 30.50, "lon":  31.20, "name": "Lower Egypt",     "terrain": "PLAINS",    "kingdom": "egypt"},
		"middle_egypt":    {"lat": 28.10, "lon":  30.80, "name": "Middle Egypt",    "terrain": "DESERT",    "kingdom": "egypt"},
		"upper_egypt":     {"lat": 25.70, "lon":  32.60, "name": "Upper Egypt",     "terrain": "DESERT",    "kingdom": "egypt"},
		"nubia":           {"lat": 20.50, "lon":  31.00, "name": "Nubia",           "terrain": "DESERT",    "kingdom": "kush"},

		# --- North Africa -------------------------------------------------
		"cyrenaica":       {"lat": 32.80, "lon":  21.80, "name": "Cyrenaica",       "terrain": "COASTAL",   "kingdom": "cyrene"},
		"tripolitania":    {"lat": 32.90, "lon":  13.20, "name": "Tripolitania",    "terrain": "DESERT",    "kingdom": ""},
		"libya_interior":  {"lat": 26.00, "lon":  17.00, "name": "Libya Interior",  "terrain": "DESERT",    "kingdom": ""},
		"africa_proconsularis": {"lat": 36.50, "lon":  10.00, "name": "Africa Proconsularis","terrain": "COASTAL","kingdom":"carthage"},
		"numidia":         {"lat": 36.00, "lon":   6.00, "name": "Numidia",         "terrain": "HILLS",     "kingdom": ""},
		"mauretania":      {"lat": 34.00, "lon":  -2.50, "name": "Mauretania",      "terrain": "MOUNTAINS", "kingdom": ""},
		"sahara":          {"lat": 22.00, "lon":   5.00, "name": "Sahara",          "terrain": "DESERT",    "kingdom": ""},
	}


## Regions that are purely sea. These produce zero Voronoi cells — the
## sea is painted as flat water in the shader, no clickable provinces.
## Kept in this list for naming (hover-text only) and future fleet lanes.
static func sea_region_ids() -> Array:
	return []


static func is_sea_region(region_id: String) -> bool:
	return region_id in sea_region_ids()


## Returns the pixel position of each region's centre for a given bitmap.
static func region_center_px(region: Dictionary, bitmap_w: int, bitmap_h: int) -> Vector2:
	var n: Vector2 = ll_to_norm(float(region.get("lon", 0.0)), float(region.get("lat", 0.0)))
	return Vector2(n.x * float(bitmap_w), n.y * float(bitmap_h))


# --- Cities ------------------------------------------------------------------
#
# Cities are markers rendered on top of the provinces. Each one sits at
# a real historical (lat, lon) and has a tier so low zoom shows only
# the tier-1 giants (Babylon, Memphis, Persepolis) and max zoom shows
# every little polis. Districts live inside tier-1/2 cities once the
# player drills all the way in (§8.5).
#
# Format: { id: { name, lat, lon, tier, region, kingdom } }
#   tier ∈ 1 (megapolis, always visible)
#        | 2 (capital / major city, visible from regional zoom)
#        | 3 (notable polis / port, visible from province zoom)
#        | 4 (minor town, visible only at city zoom)

static func cities() -> Dictionary:
	return {
		# --- Tier 1: the ancient-world giants ------------------------------
		"babylon":     {"name": "Babylon",      "lat": 32.54, "lon": 44.42, "tier": 1, "region": "babylonia",  "kingdom": "persia"},
		"memphis":     {"name": "Memphis",      "lat": 29.85, "lon": 31.25, "tier": 1, "region": "lower_egypt","kingdom": "egypt"},
		"persepolis":  {"name": "Persepolis",   "lat": 29.93, "lon": 52.89, "tier": 1, "region": "persis",     "kingdom": "persia"},
		"susa":        {"name": "Susa",         "lat": 32.19, "lon": 48.26, "tier": 1, "region": "elam",       "kingdom": "persia"},
		"thebes_egy":  {"name": "Thebes",       "lat": 25.72, "lon": 32.60, "tier": 1, "region": "upper_egypt","kingdom": "egypt"},
		"carthage":    {"name": "Carthage",     "lat": 36.85, "lon": 10.32, "tier": 1, "region": "africa_proconsularis","kingdom":"carthage"},
		"sardis":      {"name": "Sardis",       "lat": 38.49, "lon": 28.04, "tier": 1, "region": "lydia",      "kingdom": "persia"},

		# --- Tier 2: capitals and major ports ------------------------------
		"athens":      {"name": "Athens",       "lat": 37.98, "lon": 23.73, "tier": 2, "region": "attica",     "kingdom": "athens"},
		"sparta":      {"name": "Sparta",       "lat": 37.08, "lon": 22.43, "tier": 2, "region": "laconia",    "kingdom": "sparta"},
		"corinth":     {"name": "Corinth",      "lat": 37.94, "lon": 22.94, "tier": 2, "region": "corinthia",  "kingdom": "corinth"},
		"thebes_gr":   {"name": "Thebes",       "lat": 38.32, "lon": 23.32, "tier": 2, "region": "boeotia",    "kingdom": "thebes"},
		"argos":       {"name": "Argos",        "lat": 37.64, "lon": 22.72, "tier": 2, "region": "argolis",    "kingdom": "corinth"},
		"syracuse":    {"name": "Syracusae",    "lat": 37.08, "lon": 15.29, "tier": 2, "region": "sicily_east","kingdom": "syracuse"},
		"rome":        {"name": "Rome",         "lat": 41.89, "lon": 12.48, "tier": 2, "region": "latium",     "kingdom": "rome"},
		"tyre":        {"name": "Tyre",         "lat": 33.27, "lon": 35.20, "tier": 2, "region": "phoenicia",  "kingdom": "persia"},
		"sidon":       {"name": "Sidon",        "lat": 33.56, "lon": 35.39, "tier": 2, "region": "phoenicia",  "kingdom": "persia"},
		"jerusalem":   {"name": "Jerusalem",    "lat": 31.78, "lon": 35.22, "tier": 2, "region": "judea",      "kingdom": "persia"},
		"ecbatana":    {"name": "Ecbatana",     "lat": 34.80, "lon": 48.52, "tier": 2, "region": "media",      "kingdom": "persia"},
		"miletus":     {"name": "Miletus",      "lat": 37.53, "lon": 27.28, "tier": 2, "region": "ionia",      "kingdom": "persia"},
		"ephesus":     {"name": "Ephesus",      "lat": 37.94, "lon": 27.34, "tier": 2, "region": "ionia",      "kingdom": "persia"},
		"halicarnassus":{"name": "Halicarnassus","lat":37.03, "lon": 27.43, "tier": 2, "region": "caria",      "kingdom": "persia"},
		"byzantium":   {"name": "Byzantium",    "lat": 41.01, "lon": 28.98, "tier": 2, "region": "thrace",     "kingdom": "odrysia"},
		"cyrene":      {"name": "Cyrene",       "lat": 32.82, "lon": 21.86, "tier": 2, "region": "cyrenaica",  "kingdom": "cyrene"},
		"damascus":    {"name": "Damascus",     "lat": 33.51, "lon": 36.30, "tier": 2, "region": "syria",      "kingdom": "persia"},
		"nineveh":     {"name": "Nineveh",      "lat": 36.37, "lon": 43.15, "tier": 2, "region": "assyria",    "kingdom": "persia"},
		"gades":       {"name": "Gades",        "lat": 36.53, "lon": -6.28, "tier": 2, "region": "gades",      "kingdom": "carthage"},
		"massalia":    {"name": "Massalia",     "lat": 43.30, "lon":  5.37, "tier": 2, "region": "massalia",   "kingdom": "massalia"},
		"pella":       {"name": "Pella",        "lat": 40.76, "lon": 22.52, "tier": 2, "region": "macedon",    "kingdom": "macedon"},
		"sais":        {"name": "Sais",         "lat": 30.97, "lon": 30.77, "tier": 2, "region": "lower_egypt","kingdom": "egypt"},

		# --- Tier 3: notable regional towns --------------------------------
		"tarquinii":   {"name": "Tarquinii",    "lat": 42.25, "lon": 11.76, "tier": 3, "region": "etruria",    "kingdom": "etruscan_league"},
		"capua":       {"name": "Capua",        "lat": 41.08, "lon": 14.25, "tier": 3, "region": "campania",   "kingdom": "etruscan_league"},
		"neapolis":    {"name": "Neapolis",     "lat": 40.85, "lon": 14.27, "tier": 3, "region": "campania",   "kingdom": "etruscan_league"},
		"tarentum":    {"name": "Tarentum",     "lat": 40.47, "lon": 17.23, "tier": 3, "region": "magna_graecia","kingdom":""},
		"croton":      {"name": "Croton",       "lat": 39.08, "lon": 17.13, "tier": 3, "region": "calabria",   "kingdom": ""},
		"akragas":     {"name": "Akragas",      "lat": 37.31, "lon": 13.58, "tier": 3, "region": "sicily_west","kingdom": "carthage"},
		"panormus":    {"name": "Panormus",     "lat": 38.12, "lon": 13.37, "tier": 3, "region": "sicily_west","kingdom": "carthage"},
		"naucratis":   {"name": "Naucratis",    "lat": 30.90, "lon": 30.60, "tier": 3, "region": "lower_egypt","kingdom": "egypt"},
		"pelusium":    {"name": "Pelusium",     "lat": 31.04, "lon": 32.54, "tier": 3, "region": "lower_egypt","kingdom": "egypt"},
		"volsinii":    {"name": "Volsinii",     "lat": 42.59, "lon": 11.99, "tier": 3, "region": "etruria",    "kingdom": "etruscan_league"},
		"veii":        {"name": "Veii",         "lat": 42.02, "lon": 12.40, "tier": 3, "region": "etruria",    "kingdom": "etruscan_league"},
		"gordion":     {"name": "Gordion",      "lat": 39.65, "lon": 31.99, "tier": 3, "region": "phrygia",    "kingdom": "persia"},
		"tarsus":      {"name": "Tarsus",       "lat": 36.92, "lon": 34.89, "tier": 3, "region": "cilicia",    "kingdom": "persia"},
		"antioch":     {"name": "Antigonea",    "lat": 36.20, "lon": 36.16, "tier": 3, "region": "syria",      "kingdom": "persia"},
		"heraklion":   {"name": "Knossos",      "lat": 35.30, "lon": 25.16, "tier": 3, "region": "crete",      "kingdom": ""},
		"olbia":       {"name": "Olbia Pontica","lat": 46.68, "lon": 31.91, "tier": 3, "region": "scythia",    "kingdom": ""},
		"panticapaeum":{"name": "Panticapaeum", "lat": 45.35, "lon": 36.47, "tier": 3, "region": "scythia",    "kingdom": ""},
	}


# --- Stable kingdom index (shader palette alpha) -----------------------------
#
# The baked political palette stores a 1-byte kingdom id per cell so
# the shader can do cheap kingdom-border detection without another
# texture. 0 = unclaimed, 255 = sea, 1..N = specific kingdom.

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
		"thebes":          return 10
		"syracuse":        return 11
		"massalia":        return 12
		"odrysia":         return 13
		"molossia":        return 14
		"colchis":         return 15
		"nabatea":         return 16
		"kush":            return 17
		"cyrene":          return 18
		"tartessos":       return 19
		_:                 return 0
