class_name CoverIdentity
extends Resource
## §F4 — Cover Identity v1 (docs/02-player/cover-identities.md).
##
## A cover identity is the face the player wears on one side of the
## table: a plausible-age, plausible-profession persona anchored to
## one or more Actors (the coordinators / hosts who can credibly
## introduce "this person" into a scene). Identities live for as long
## as their legend holds — once burned, they cannot be rehabilitated,
## only replaced.
##
## Phase-F ships the data model, a registry, one starter identity,
## and a surface on the Dossiers panel under "THIS SIDE OF THE TABLE".
## Consumption by actions (legend accrual, identity-gated ops, burn
## chains) is Phase-G work.

@export var id: StringName = &""
@export var cover_name: String = ""            # e.g. "Demetrios of Miletos"
@export var apparent_age: int = 0              # years
@export var profession: String = ""            # "itinerant trader", "priest of Hermes", etc.
@export var home_region_id: String = ""        # kingdom_id anchor (WorldData)
@export var anchor_actor_ids: Array[StringName] = []  # OrgMember source_actor_id or Actor id

# 0-100. Internal number; the UI never shows it as an integer, only
# as a qualitative band via `legend_band_phrase()`.
@export_range(0, 100) var legend_score: int = 0

# Once true, the identity is dead. No action may route through it.
@export var burned: bool = false

# Day the identity was opened (GameClock.absolute_day()). Used to
# compute "age on the circuit" in the UI.
@export var opened_day: int = 0

# Optional free-form note shown on the dossier panel.
@export var note: String = ""


## §F4 qualitative legend band. Never leak the raw integer.
func legend_band_phrase() -> String:
	if burned:
		return "burned"
	if legend_score < 10:  return "a name no one knows yet"
	if legend_score < 25:  return "a face seen once or twice"
	if legend_score < 45:  return "a face on the circuit"
	if legend_score < 70:  return "a trusted regular"
	if legend_score < 90:  return "part of the landscape"
	return "above suspicion"


func display_title() -> String:
	if cover_name.is_empty():
		return "An unnamed cover"
	if profession.is_empty():
		return cover_name
	return "%s, %s" % [cover_name, profession]


func snapshot() -> Dictionary:
	return {
		"id":                String(id),
		"cover_name":        cover_name,
		"apparent_age":      apparent_age,
		"profession":        profession,
		"home_region_id":    home_region_id,
		"anchor_actor_ids":  anchor_actor_ids.map(func(x): return String(x)),
		"legend_score":      legend_score,
		"burned":            burned,
		"opened_day":        opened_day,
		"note":              note,
	}


static func from_snapshot(d: Dictionary) -> CoverIdentity:
	var c: CoverIdentity = CoverIdentity.new()
	c.id               = StringName(String(d.get("id", "")))
	c.cover_name       = String(d.get("cover_name", ""))
	c.apparent_age     = int(d.get("apparent_age", 0))
	c.profession       = String(d.get("profession", ""))
	c.home_region_id   = String(d.get("home_region_id", ""))
	var anchors: Variant = d.get("anchor_actor_ids", [])
	c.anchor_actor_ids = []
	if anchors is Array:
		for a in anchors:
			c.anchor_actor_ids.append(StringName(String(a)))
	c.legend_score     = int(d.get("legend_score", 0))
	c.burned           = bool(d.get("burned", false))
	c.opened_day       = int(d.get("opened_day", 0))
	c.note             = String(d.get("note", ""))
	return c
