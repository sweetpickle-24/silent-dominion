extends Node
## Global world registry. Autoloaded as `WorldData`.
##
## Loads the static starting state of the world (provinces + kingdoms)
## from JSON at startup and exposes it via dictionaries keyed by id.
## Everything else in the game should pull from here rather than
## hard-coding province or kingdom lookups.

signal world_loaded

const WORLD_FILE: String = "res://data/world_500bce.json"

var provinces: Dictionary = {}   # id (String) -> Province
var kingdoms: Dictionary = {}    # id (String) -> Kingdom

var _loaded: bool = false


func _ready() -> void:
	DevLogger.write("WorldData: ready")
	load_world(WORLD_FILE)
	# §D2 Lift city fog every month for any city that sits in a kingdom
	# where the player has a non-burned coordinator. The work lives here
	# rather than OrgRegistry because the fog is a property of the world,
	# not of the org.
	GameClock.month_passed.connect(_on_month_passed_tick_city_fog)


func _on_month_passed_tick_city_fog(_year: int, _month: int) -> void:
	for p in provinces.values():
		if p.city == null:
			continue
		if p.owning_kingdom.is_empty():
			continue
		var cov: OrgMember = Org.coverage_for(p.owning_kingdom)
		if cov == null:
			continue
		# A coordinator with higher `cover` rips through fog faster; cap
		# the step so it still takes several months on a raw posting.
		var step: int = clampi(12 + int(cov.cover) / 8, 10, 25)
		p.city.lift_fog(step, 10)


# --- Loading ------------------------------------------------------------------

func load_world(path: String) -> void:
	provinces.clear()
	kingdoms.clear()
	_loaded = false

	if not FileAccess.file_exists(path):
		push_error("WorldData: file not found at %s" % path)
		return

	var raw: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	if parsed == null or not (parsed is Dictionary):
		push_error("WorldData: failed to parse JSON at %s" % path)
		return

	var root: Dictionary = parsed

	for p_dict in root.get("provinces", []):
		if not (p_dict is Dictionary):
			continue
		var prov: Province = Province.from_dict(p_dict)
		if prov.id.is_empty():
			push_warning("WorldData: skipping province with empty id")
			continue
		if provinces.has(prov.id):
			push_warning("WorldData: duplicate province id '%s'" % prov.id)
		provinces[prov.id] = prov

	for k_dict in root.get("kingdoms", []):
		if not (k_dict is Dictionary):
			continue
		var kng: Kingdom = Kingdom.from_dict(k_dict)
		if kng.id.is_empty():
			push_warning("WorldData: skipping kingdom with empty id")
			continue
		if kingdoms.has(kng.id):
			push_warning("WorldData: duplicate kingdom id '%s'" % kng.id)
		kingdoms[kng.id] = kng

	_validate_references()

	_loaded = true
	world_loaded.emit()
	print("[WorldData] Loaded %d provinces and %d kingdoms from %s"
		% [provinces.size(), kingdoms.size(), path])


## Cross-check that every kingdom's owned_provinces exist and that every
## province's owning_kingdom (if set) matches one of the kingdoms. Bad
## references are logged but not fatal — data errors should surface early
## without blocking development.
func _validate_references() -> void:
	for k in kingdoms.values():
		for pid in k.owned_provinces:
			if not provinces.has(pid):
				push_warning("WorldData: kingdom '%s' references missing province '%s'"
					% [k.id, pid])

	for p in provinces.values():
		if p.owning_kingdom.is_empty():
			continue
		if not kingdoms.has(p.owning_kingdom):
			push_warning("WorldData: province '%s' references missing kingdom '%s'"
				% [p.id, p.owning_kingdom])


# --- Lookups ------------------------------------------------------------------

func is_loaded() -> bool:
	return _loaded


func get_province(id: String) -> Province:
	return provinces.get(id)


func get_kingdom(id: String) -> Kingdom:
	return kingdoms.get(id)


func get_provinces_of(kingdom_id: String) -> Array:
	var out: Array = []
	for p in provinces.values():
		if p.owning_kingdom == kingdom_id:
			out.append(p)
	return out


# --- Debug --------------------------------------------------------------------

func print_debug_dump() -> void:
	print("===================================================")
	print("  WorldData debug dump — 500 BCE starting state")
	print("===================================================")
	print("")
	print("Kingdoms (%d):" % kingdoms.size())
	print("---------------------------------------------------")
	for k in kingdoms.values():
		print("  %s  [%s]" % [k.kingdom_name, k.id])
		print("      treasury: %.0f silver, %.0f gold  (%s)"
			% [k.treasury_silver, k.treasury_gold, k.treasury_condition_name()])
		if k.owned_provinces.is_empty():
			print("      provinces: (none)")
		else:
			print("      provinces: %s" % ", ".join(k.owned_provinces))
		print("")

	print("Provinces (%d):" % provinces.size())
	print("---------------------------------------------------")
	for p in provinces.values():
		var owner_name: String = p.owning_kingdom if not p.owning_kingdom.is_empty() else "unclaimed"
		print("  %s  [%s]  — %s, %s — pop %dk — owner: %s"
			% [p.province_name, p.id, p.terrain_name(), p.climate_name(),
				p.population, owner_name])
		print("      grain %.1f | silver %.1f | iron %.1f | timber %.1f"
			% [p.grain_production, p.silver_production,
				p.iron_production, p.timber_production])
	print("===================================================")
