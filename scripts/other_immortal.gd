class_name OtherImmortal
extends Resource
## Per §5.5. One of the (at most) five-to-nine peers in the world who
## are, like the player, deathless. Each is associated with a single
## founded society. Not every society has a living founder — some are
## posthumous, and future ticks may flip living immortals into dead
## ones (see `kill_state`).
##
## The player's *relationship* with each immortal is the interesting
## state: unknown → aware → in_contact → truce | cold | war, and
## terminally → dead | escaped. See state transitions below.
##
## Nothing about this resource is revealed to the player until the
## corresponding society reaches catalogued confirmation in the
## fingerprint library.

enum KillState {
	ALIVE,
	POSTHUMOUS,    ## founder dead; society runs on mortal inheritance
	CONTESTED,     ## founder died recently; mortal succession war
}

## Relationship state between player and this immortal.
## Represented as StringNames for save-safety.
##   &"unknown"     — player has not met them; they may have noticed us
##   &"aware"       — player has been shown they exist; no contact yet
##   &"in_contact"  — an exchange of letters is underway
##   &"truce"       — formal non-aggression, their society soft-stops acts in our regions
##   &"cold"        — contact was opened and then shut; neutral
##   &"war"         — mutual open shadow-war (their ops spike, ours louder)
##   &"dead"        — player has killed this immortal (society → posthumous)
##   &"escaped"     — player attempted to kill and failed; most dangerous state

@export var id: StringName = &""
@export var society_id: StringName = &""
@export var epithet: String = ""
@export var disposition: String = ""             # short prose hint
@export var kill_state: KillState = KillState.ALIVE
@export var relationship: StringName = &"unknown"
@export var known_by_player: bool = false

## How receptive this immortal is to opening contact when the player
## reaches out. 0-100; tuned per immortal. Low values mean they will
## refuse and the attempt leaks through third parties.
@export var openness: int = 50

## How hostile they become if contact is refused. 0-100.
@export var hostility: int = 40


func is_alive() -> bool:
	return kill_state == KillState.ALIVE


func to_dict() -> Dictionary:
	return {
		"id":              String(id),
		"society_id":      String(society_id),
		"epithet":         epithet,
		"disposition":     disposition,
		"kill_state":      int(kill_state),
		"relationship":    String(relationship),
		"known_by_player": known_by_player,
		"openness":        openness,
		"hostility":       hostility,
	}


static func from_dict(d: Dictionary) -> OtherImmortal:
	var o: OtherImmortal = OtherImmortal.new()
	o.id              = StringName(String(d.get("id", "")))
	o.society_id      = StringName(String(d.get("society_id", "")))
	o.epithet         = String(d.get("epithet", ""))
	o.disposition     = String(d.get("disposition", ""))
	o.kill_state      = int(d.get("kill_state", KillState.ALIVE)) as KillState
	o.relationship    = StringName(String(d.get("relationship", "unknown")))
	o.known_by_player = bool(d.get("known_by_player", false))
	o.openness        = int(d.get("openness", 50))
	o.hostility       = int(d.get("hostility", 40))
	return o
