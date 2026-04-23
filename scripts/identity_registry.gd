extends Node
## §F4 — Autoloaded as `Identities`.
##
## Central registry for the player's cover identities. At campaign
## start we seed exactly one identity (`ident_starter_trader`) in
## Athens, anchored to the starter coordinator. Future identities
## are added through actions that are still Phase-G work.

signal identity_added(id: StringName)
signal identity_updated(id: StringName)
signal identity_burned(id: StringName)

var identities: Dictionary = {}  # StringName id -> CoverIdentity

const STARTER_ID: StringName = &"ident_starter_trader"


func _ready() -> void:
	DevLogger.write("Identities: ready")
	if WorldData != null and not WorldData.is_loaded():
		WorldData.world_loaded.connect(_seed_starter_identity, CONNECT_ONE_SHOT)
	else:
		call_deferred("_seed_starter_identity")


func _seed_starter_identity() -> void:
	if identities.has(STARTER_ID):
		return
	var c: CoverIdentity = CoverIdentity.new()
	c.id               = STARTER_ID
	c.cover_name       = "Demetrios of Miletos"
	c.apparent_age     = 42
	c.profession       = "itinerant grain-and-oil trader"
	c.home_region_id   = "athens"
	c.anchor_actor_ids = [&"starter_coordinator_athens"]
	c.legend_score     = 22
	c.opened_day       = GameClock.absolute_day() if GameClock != null else 0
	c.note = (
		"A Miletos accent, a Chalkidic face. Carried by your coordinator "
		+ "as 'that trader out of the east' for enough seasons that the "
		+ "Kerameikos knows the name before it knows the man."
	)
	identities[STARTER_ID] = c
	identity_added.emit(STARTER_ID)


# --- Public API --------------------------------------------------------------

func get_identity(id: StringName) -> CoverIdentity:
	return identities.get(id, null)


func all_identities() -> Array[CoverIdentity]:
	var out: Array[CoverIdentity] = []
	for c in identities.values():
		out.append(c)
	out.sort_custom(func(a: CoverIdentity, b: CoverIdentity) -> bool:
		return a.cover_name < b.cover_name)
	return out


func active_identities() -> Array[CoverIdentity]:
	var out: Array[CoverIdentity] = []
	for c in all_identities():
		if not c.burned:
			out.append(c)
	return out


func burn(id: StringName) -> void:
	var c: CoverIdentity = get_identity(id)
	if c == null or c.burned:
		return
	c.burned = true
	identity_burned.emit(id)
	identity_updated.emit(id)


# --- Save / load -------------------------------------------------------------

func snapshot() -> Dictionary:
	var arr: Array = []
	for c in identities.values():
		arr.append(c.snapshot())
	return { "identities": arr }


func restore(d: Dictionary) -> void:
	identities.clear()
	var arr: Variant = d.get("identities", [])
	if arr is Array:
		for entry in arr:
			if entry is Dictionary:
				var c: CoverIdentity = CoverIdentity.from_snapshot(entry)
				if c != null and c.id != &"":
					identities[c.id] = c
