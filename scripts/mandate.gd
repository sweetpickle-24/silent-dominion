class_name Mandate
extends Resource
## A directed long-term objective (§11).
##
## Mandates are not quests. They are the player's own declared
## priorities, given shape by the simulation. Each has a category,
## a sequence of phases with success and failure conditions, and
## a target handle (actor / kingdom / society — whichever makes
## sense for the category).
##
## Concrete mandate logic — what makes a phase tick, what flips it
## to completed or failed — lives in MandateRegistry. Mandate
## itself is pure data.

enum Category {
	REMOVAL,           # remove a dangerous individual
	ELEVATION,         # lift a family or faction to power
	IDEOLOGICAL,       # seed a religion or ideology
	SURVIVAL,          # go cold, outlast the hunt
	DESTABILISATION,   # fracture a kingdom
	COUNTER_SOCIETY,   # blunt a rival's drive
}

enum Status {
	OFFERED,    # emergent dispatch sitting in the inbox, awaiting accept/defer
	ACTIVE,     # phases being worked on
	COMPLETED,  # all phases resolved successfully
	FAILED,     # blocked or expired past recovery
	DEFERRED,   # player pushed the offer away; may re-emerge
	IGNORED,    # offered but never opened; treated as rejected
}

@export var id: StringName = &""
@export var category: Category = Category.REMOVAL
@export var status: Status = Status.OFFERED

@export var headline: String = ""
@export_multiline var blurb: String = ""

## One of these will be set depending on category.
@export var target_actor_id: StringName = &""
@export var target_kingdom_id: String = ""
@export var target_society_id: StringName = &""

@export var started_abs_day: int = 0
@export var deadline_abs_day: int = -1     # -1 for open-ended

## Phases are dictionaries with keys:
##   name         - String, short heading
##   description  - String, blurb
##   progress     - int 0..target (runtime)
##   target       - int goal count (e.g. 3 observations)
##   state        - StringName, one of "pending", "active", "done", "failed"
##   condition    - StringName, internal tag MandateRegistry uses to match
##                  simulation signals against this phase
@export var phases: Array = []
@export var current_phase: int = 0

## True if the mandate was surfaced by the world rather than chosen
## by the player. Emergent mandates usually carry a sharper deadline.
@export var emergent: bool = false


func is_terminal() -> bool:
	return status == Status.COMPLETED or status == Status.FAILED or status == Status.IGNORED


func active_phase() -> Dictionary:
	if current_phase < 0 or current_phase >= phases.size():
		return {}
	return phases[current_phase]


func category_label() -> String:
	return Category.keys()[category].capitalize().replace("_", " ")


func status_label() -> String:
	return Status.keys()[status].capitalize()


# --- Serialisation -----------------------------------------------------------

static func from_dict(d: Dictionary) -> Mandate:
	var m: Mandate = Mandate.new()
	m.id                 = StringName(String(d.get("id", "")))
	m.category           = _category_from_string(String(d.get("category", "REMOVAL")))
	m.status             = _status_from_string(String(d.get("status", "OFFERED")))
	m.headline           = String(d.get("headline", ""))
	m.blurb              = String(d.get("blurb", ""))
	m.target_actor_id    = StringName(String(d.get("target_actor_id", "")))
	m.target_kingdom_id  = String(d.get("target_kingdom_id", ""))
	m.target_society_id  = StringName(String(d.get("target_society_id", "")))
	m.started_abs_day    = int(d.get("started_abs_day", 0))
	m.deadline_abs_day   = int(d.get("deadline_abs_day", -1))
	m.current_phase      = int(d.get("current_phase", 0))
	m.emergent           = bool(d.get("emergent", false))
	m.phases = []
	for entry in d.get("phases", []):
		if typeof(entry) == TYPE_DICTIONARY:
			m.phases.append(entry.duplicate(true))
	return m


func to_dict() -> Dictionary:
	return {
		"id":                 String(id),
		"category":           Category.keys()[category],
		"status":             Status.keys()[status],
		"headline":           headline,
		"blurb":              blurb,
		"target_actor_id":    String(target_actor_id),
		"target_kingdom_id":  target_kingdom_id,
		"target_society_id":  String(target_society_id),
		"started_abs_day":    started_abs_day,
		"deadline_abs_day":   deadline_abs_day,
		"current_phase":      current_phase,
		"emergent":           emergent,
		"phases":             phases.duplicate(true),
	}


static func _category_from_string(s: String) -> Category:
	match s.to_upper():
		"REMOVAL":         return Category.REMOVAL
		"ELEVATION":       return Category.ELEVATION
		"IDEOLOGICAL":     return Category.IDEOLOGICAL
		"SURVIVAL":        return Category.SURVIVAL
		"DESTABILISATION": return Category.DESTABILISATION
		"COUNTER_SOCIETY": return Category.COUNTER_SOCIETY
		_:                  return Category.REMOVAL


static func _status_from_string(s: String) -> Status:
	match s.to_upper():
		"OFFERED":   return Status.OFFERED
		"ACTIVE":    return Status.ACTIVE
		"COMPLETED": return Status.COMPLETED
		"FAILED":    return Status.FAILED
		"DEFERRED":  return Status.DEFERRED
		"IGNORED":   return Status.IGNORED
		_:            return Status.OFFERED
