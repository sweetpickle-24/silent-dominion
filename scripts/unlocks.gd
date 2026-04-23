extends Node
## §D4 Autoloaded as `Unlocks`.
##
## The game exposes a lot of machinery (vault, memoirs, library,
## roster) but the early-game player has no reason to visit any of
## them. Surfacing every object at the same time flattens the first
## hour into "read these seven manuals". `Unlocks` fades each object
## in the moment the player first has something worth reading there.
##
## Gate rules (kept intentionally cheap to check):
##   - Memoirs: first Memoirs.pattern_added. No patterns, no archive.
##   - Vault:   first OwnedEntity of kind BANKING_HOUSE OR first
##              BankingHouse registered — either entry point into the
##              Finance system qualifies.
##   - Library: first Fingerprints.level_for(op_id) >= LEVEL_SIGNAL
##              (i.e. the player has at least one confirmed signal).
##   - Roster:  first coordinator promoted (Org layer == COORDINATOR).
##
## Nothing in the simulation *reads* from this autoload — it only
## drives visual dimming on the table scene. Systems fire their own
## signals exactly as before; `Unlocks` listens and re-emits one
## unified `surface_unlocked(id)`.
##
## Save integration: the set of already-surfaced objects is persisted
## so a reload doesn't re-dim things the player has already seen.

signal surface_unlocked(id: StringName)
signal welcome_card_due(id: StringName)

const ID_MEMOIRS:  StringName = &"memoirs"
const ID_VAULT:    StringName = &"vault"
const ID_LIBRARY:  StringName = &"library"
const ID_ROSTER:   StringName = &"roster"

const ALL_IDS: Array[StringName] = [ID_MEMOIRS, ID_VAULT, ID_LIBRARY, ID_ROSTER]

# id -> true once surfaced. Missing/false means dim.
var _surfaced: Dictionary = {}
# id -> true once the welcome card has been shown at least once.
var _welcome_shown: Dictionary = {}


func _ready() -> void:
	_wire_memoirs()
	_wire_vault()
	_wire_library()
	_wire_roster()


# --- Public API --------------------------------------------------------------

func is_surfaced(id: StringName) -> bool:
	return bool(_surfaced.get(id, false))


func all_surfaced() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ALL_IDS:
		if is_surfaced(id):
			out.append(id)
	return out


## Welcome-card flag. Consumed by the first-open handler on each view
## so the card appears exactly once per surface_unlock.
func should_show_welcome(id: StringName) -> bool:
	return is_surfaced(id) and not bool(_welcome_shown.get(id, false))


func mark_welcome_shown(id: StringName) -> void:
	_welcome_shown[id] = true


## §E1 Save round-trip.
func snapshot() -> Dictionary:
	return {
		"surfaced":      _surfaced.duplicate(),
		"welcome_shown": _welcome_shown.duplicate(),
	}


func restore(d: Dictionary) -> void:
	_surfaced.clear()
	_welcome_shown.clear()
	var s: Variant = d.get("surfaced", {})
	if s is Dictionary:
		for k in (s as Dictionary).keys():
			_surfaced[StringName(String(k))] = bool((s as Dictionary)[k])
	var w: Variant = d.get("welcome_shown", {})
	if w is Dictionary:
		for k in (w as Dictionary).keys():
			_welcome_shown[StringName(String(k))] = bool((w as Dictionary)[k])


# --- Wiring ------------------------------------------------------------------

func _wire_memoirs() -> void:
	if Memoirs == null:
		return
	Memoirs.pattern_added.connect(func(_id: StringName) -> void:
		_surface(ID_MEMOIRS))


func _wire_vault() -> void:
	# Either a banking-house entity being founded, or a BankingHouse
	# appearing in FinanceManager, qualifies. We listen to both.
	if Entities != null:
		Entities.entity_added.connect(_on_entity_added_for_vault)
	if Finance != null:
		Finance.house_added.connect(func(_h: BankingHouse) -> void:
			_surface(ID_VAULT))


func _on_entity_added_for_vault(entity_id: StringName) -> void:
	var e: OwnedEntity = Entities.get_entity(entity_id)
	if e == null:
		return
	if e.kind == OwnedEntity.Kind.BANKING_HOUSE:
		_surface(ID_VAULT)


func _wire_library() -> void:
	if Fingerprints == null:
		return
	# The first "mechanism"-level match (something the player has
	# actually identified, not just noticed) is the fingerprint
	# library becoming useful. Below that it's just noise.
	Fingerprints.op_level_changed.connect(func(_op_id: String, level: int) -> void:
		if level >= Fingerprints.LEVEL_MECHANISM:
			_surface(ID_LIBRARY))


func _wire_roster() -> void:
	if Org == null:
		return
	Org.member_added.connect(func(m: OrgMember) -> void:
		if m != null and m.layer == OrgMember.Layer.COORDINATOR:
			_surface(ID_ROSTER))
	Org.member_updated.connect(func(m: OrgMember) -> void:
		if m != null and m.layer == OrgMember.Layer.COORDINATOR:
			_surface(ID_ROSTER))


# --- Internal ----------------------------------------------------------------

func _surface(id: StringName) -> void:
	if is_surfaced(id):
		return
	_surfaced[id] = true
	surface_unlocked.emit(id)
	welcome_card_due.emit(id)
