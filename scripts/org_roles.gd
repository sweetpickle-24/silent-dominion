extends Node
## §C1 — OrgRoles resolver.
##
## Maps functional narrator titles ("factotum", "archivist", "paymaster",
## "go-between", "watcher", "secretary", "tutor", "chief of mandates",
## "counter-intelligence chief", "coordinator", "predecessor",
## "correspondent at the harbour", "man of affairs", "broker", "handler")
## to the best-matching real OrgMember/Actor at call time.
##
## The contract is strict:
##   * `resolve(role, region)` returns an `OrgMember`, an `Actor`, or null.
##   * `sender_line(role, region)` always returns a non-empty display string
##     suitable for `Letter.sender`. When a real record backs the role, the
##     string names that record. When none does, it returns a neutral
##     atmospheric fallback that **never uses the word "Your"**.
##
## Callers must never hardcode "Your factotum" / "Your go-between" strings
## directly. Route through `OrgRoles.sender_line(role, region)` so the
## audit grep stays clean and the player never reads about people who
## do not exist.

# ---- Role tokens -------------------------------------------------------------
# These are the canonical role names the rest of the codebase passes in.
const FACTOTUM: StringName             = &"factotum"
const ARCHIVIST: StringName            = &"archivist"
const PAYMASTER: StringName            = &"paymaster"
const GO_BETWEEN: StringName           = &"go_between"
const WATCHER: StringName              = &"watcher"
const WATCHER_ARCHIVES: StringName     = &"watcher_archives"
const SECRETARY: StringName            = &"secretary"
const TUTOR: StringName                = &"tutor"
const CHIEF_OF_MANDATES: StringName    = &"chief_of_mandates"
const COUNTER_INTEL: StringName        = &"counter_intel"
const COORDINATOR: StringName          = &"coordinator"
const COORDINATOR_AT_DEPARTURE: StringName = &"coordinator_at_departure"
const PREDECESSOR: StringName          = &"predecessor"
const CORRESPONDENT_HARBOUR: StringName = &"correspondent_harbour"
const MAN_OF_AFFAIRS: StringName       = &"man_of_affairs"
const BROKER: StringName               = &"broker"
const HANDLER: StringName              = &"handler"
const OWN_HAND: StringName             = &"own_hand"
const ROSTER: StringName               = &"roster"
const HOST: StringName                 = &"host"
const REVIEWER: StringName             = &"reviewer"
const INVESTIGATOR: StringName         = &"investigator"
const COUNTER_RUMOUR: StringName       = &"counter_rumour"
const ARSON_CHIEF: StringName          = &"arson_chief"
const FORGERY_CELL: StringName         = &"forgery_cell"
const INTERMEDIARY: StringName         = &"intermediary"
const CLOSEST_HAND: StringName         = &"closest_hand"
const ANONYMOUS_AUDIT: StringName      = &"anonymous_audit"
const UNAFFILIATED_WATCHER: StringName = &"unaffiliated_watcher"

# ---- Role -> preferred OrgMember layer --------------------------------------
# When a role is queried we look for a living OrgMember of this layer first.
# If no match, we fall through to the coverage coordinator, then to the
# atmospheric fallback.
const _ROLE_LAYER: Dictionary = {
	FACTOTUM:                OrgMember.Layer.COORDINATOR,
	ARCHIVIST:               OrgMember.Layer.LIEUTENANT,
	PAYMASTER:               OrgMember.Layer.LIEUTENANT,
	GO_BETWEEN:              OrgMember.Layer.COORDINATOR,
	WATCHER:                 OrgMember.Layer.COORDINATOR,
	WATCHER_ARCHIVES:        OrgMember.Layer.COORDINATOR,
	SECRETARY:               OrgMember.Layer.COORDINATOR,
	TUTOR:                   OrgMember.Layer.COORDINATOR,
	CHIEF_OF_MANDATES:       OrgMember.Layer.LIEUTENANT,
	COUNTER_INTEL:           OrgMember.Layer.LIEUTENANT,
	COORDINATOR:             OrgMember.Layer.COORDINATOR,
	COORDINATOR_AT_DEPARTURE: OrgMember.Layer.COORDINATOR,
	PREDECESSOR:             OrgMember.Layer.COORDINATOR,
	CORRESPONDENT_HARBOUR:   OrgMember.Layer.COORDINATOR,
	MAN_OF_AFFAIRS:          OrgMember.Layer.COORDINATOR,
	BROKER:                  OrgMember.Layer.COORDINATOR,
	HANDLER:                 OrgMember.Layer.COORDINATOR,
	REVIEWER:                OrgMember.Layer.LIEUTENANT,
	INVESTIGATOR:            OrgMember.Layer.COORDINATOR,
	COUNTER_RUMOUR:          OrgMember.Layer.LIEUTENANT,
	ARSON_CHIEF:             OrgMember.Layer.LIEUTENANT,
	FORGERY_CELL:            OrgMember.Layer.LIEUTENANT,
	INTERMEDIARY:            OrgMember.Layer.COORDINATOR,
	CLOSEST_HAND:            OrgMember.Layer.LIEUTENANT,
}

# ---- Role -> fallback byline ------------------------------------------------
# Used when the player has no living member fitting the role. The voice is
# deliberately anonymous; never "Your X".
const _ROLE_FALLBACK: Dictionary = {
	FACTOTUM:                "A hand not yet yours",
	ARCHIVIST:               "An archive-keeper, unnamed",
	PAYMASTER:               "A counting-table hand, unnamed",
	GO_BETWEEN:              "A go-between you have not yet placed",
	WATCHER:                 "A watcher in the quarter, unnamed",
	WATCHER_ARCHIVES:        "A watcher in the archives, unnamed",
	SECRETARY:               "A scribe at the desk, unnamed",
	TUTOR:                   "A tutor on retainer, unnamed",
	CHIEF_OF_MANDATES:       "The mandates desk, held by no one yet",
	COUNTER_INTEL:           "A counter-intelligence hand, unnamed",
	COORDINATOR:             "A local coordinator, unnamed",
	COORDINATOR_AT_DEPARTURE: "The last coordinator to see you leave",
	PREDECESSOR:             "A predecessor's hand, through a third party",
	CORRESPONDENT_HARBOUR:   "A correspondent at the harbour, unnamed",
	MAN_OF_AFFAIRS:          "A man of affairs on retainer",
	BROKER:                  "A broker on the quays, unnamed",
	HANDLER:                 "A handler in the field, unnamed",
	REVIEWER:                "An internal reviewer, unnamed",
	INVESTIGATOR:            "An investigator on retainer",
	COUNTER_RUMOUR:          "A counter-rumour hand, unnamed",
	ARSON_CHIEF:             "An arson hand, unnamed",
	FORGERY_CELL:            "A forgery cell, unnamed",
	INTERMEDIARY:            "An intermediary, unnamed",
	CLOSEST_HAND:            "The closest hand you can trust",
	ANONYMOUS_AUDIT:         "A second pair of eyes",
	UNAFFILIATED_WATCHER:    "An unaffiliated watcher",
	HOST:                    "A host on your books",
}

# ---- Role -> title suffix used when a real member is named ------------------
# e.g. "Theron, your factotum in Athens"
const _ROLE_TITLE: Dictionary = {
	FACTOTUM:                "your factotum",
	ARCHIVIST:               "your archivist",
	PAYMASTER:               "your paymaster",
	GO_BETWEEN:              "your go-between",
	WATCHER:                 "your watcher",
	WATCHER_ARCHIVES:        "your watcher in the archives",
	SECRETARY:               "your secretary",
	TUTOR:                   "your tutor",
	CHIEF_OF_MANDATES:       "your chief of mandates",
	COUNTER_INTEL:           "your counter-intelligence chief",
	COORDINATOR:             "your coordinator",
	COORDINATOR_AT_DEPARTURE: "your coordinator at departure",
	PREDECESSOR:             "through a third hand",
	CORRESPONDENT_HARBOUR:   "your correspondent at the harbour",
	MAN_OF_AFFAIRS:          "your man of affairs",
	BROKER:                  "your broker",
	HANDLER:                 "your handler",
	REVIEWER:                "your internal reviewer",
	INVESTIGATOR:            "your investigator",
	COUNTER_RUMOUR:          "your counter-rumour chief",
	ARSON_CHIEF:             "your arson chief",
	FORGERY_CELL:            "your forgery cell",
	INTERMEDIARY:            "your intermediary",
	CLOSEST_HAND:            "your closest hand",
}


func _ready() -> void:
	# Pure resolver. No state to seed.
	pass


## Returns the best `OrgMember` for the given role/region, else null.
## Region can be empty; when empty we search the whole org.
func resolve(role: StringName, region_id: String = "") -> Variant:
	if Org == null:
		return null
	var preferred_layer: int = int(_ROLE_LAYER.get(role, OrgMember.Layer.COORDINATOR))

	var best_match: OrgMember = null
	var best_score: int = -1
	for m in Org.all_members():
		if m.burned:
			continue
		var score: int = 0
		if m.layer == preferred_layer:
			score += 4
		if not region_id.is_empty() and m.region_id == region_id:
			score += 2
		# Prefer members with a set display_name (named narrator).
		if not m.display_name.is_empty():
			score += 1
		if score > best_score:
			best_score = score
			best_match = m
	# Only return if the match is at least layer-correct OR the region
	# matches. Otherwise the fallback reads better than a wrong voice.
	if best_match != null and best_score >= 2:
		return best_match
	return null


## Sender line for `Letter.sender`. Always non-empty.
func sender_line(role: StringName, region_id: String = "") -> String:
	var member: Variant = resolve(role, region_id)
	if member is OrgMember and member != null:
		var m: OrgMember = member
		var name_part: String = _short_name(m.display_name)
		var title_part: String = String(_ROLE_TITLE.get(role, "your hand"))
		if name_part.is_empty():
			return _fallback_for(role)
		if region_id.is_empty():
			return "%s, %s" % [name_part, title_part]
		return "%s, %s in %s" % [name_part, title_part, _region_name(region_id)]
	return _fallback_for(role)


## Short display for a role when we only want the title (no member),
## used in headers/blurbs. Does not claim ownership.
func neutral_title(role: StringName) -> String:
	return _fallback_for(role)


func _fallback_for(role: StringName) -> String:
	return String(_ROLE_FALLBACK.get(role, "A hand, unnamed"))


func _short_name(full: String) -> String:
	if full.is_empty():
		return ""
	# Members often carry "Name, of Somewhere". Keep the first segment.
	var parts: PackedStringArray = full.split(",", false, 1)
	return parts[0].strip_edges()


func _region_name(kid: String) -> String:
	if WorldData == null:
		return kid.capitalize()
	var k = WorldData.get_kingdom(kid)
	if k == null:
		return kid.capitalize()
	if k.has_method("display_name"):
		return String(k.display_name())
	return kid.capitalize()
