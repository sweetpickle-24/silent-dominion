extends Node
## Autoloaded as `AmbitionDrift`. Slow monthly drift of actor ambition
## and ruler paranoia in response to the state of their kingdom.
##
## Ambition is not a fixed number. It should reflect whether the world
## is calm or falling apart around the actor. Under ruinous taxes, open
## war, or restive provinces, heirs and generals start thinking larger
## thoughts; in calm times those thoughts recede toward a natural
## baseline around 50.
##
## Rulers drift differently: their paranoia rises under the same
## conditions, because their job is to survive other people's ambition.
##
## All movement is small (±1–2 per month, clamped 0–100). No events
## are published — the changes show up downstream in WorldAI's
## assassination-attempt rolls and in the dossier trait bands.

const BASELINE: int = 50

const TICK_RUINOUS: int     = 2
const TICK_BURDENED: int    = 1
const TICK_WAR: int         = 1
const TICK_UNREST: int      = 1
const REVERT_STEP: int      = 1


func _ready() -> void:
	GameClock.month_passed.connect(_on_month_passed)


func _on_month_passed(_y: int, _m: int) -> void:
	if not WorldData.is_loaded():
		return
	for a in Actors.all_actors():
		if not a.is_alive():
			continue
		var pressure: int = _pressure_on(a)
		if a.role == Actor.Role.RULER:
			_drift_trait(a, &"paranoia", pressure)
		else:
			if a.role == Actor.Role.COMMONER:
				continue
			_drift_trait(a, &"ambition", pressure)


# --- Pressure model ----------------------------------------------------------

func _pressure_on(a: Actor) -> int:
	var k: Kingdom = WorldData.get_kingdom(a.kingdom_id)
	if k == null:
		return 0
	var pressure: int = 0
	match k.tax_level:
		Kingdom.TaxLevel.RUINOUS:  pressure += TICK_RUINOUS
		Kingdom.TaxLevel.BURDENED: pressure += TICK_BURDENED
		_: pass
	if _kingdom_is_at_war(k.id):
		pressure += TICK_WAR
	if _kingdom_has_restive_province(k):
		pressure += TICK_UNREST
	return pressure


func _kingdom_is_at_war(kingdom_id: String) -> bool:
	return not Relations.ids_in_state(kingdom_id, int(Relations.RelationState.AT_WAR)).is_empty()


func _kingdom_has_restive_province(k: Kingdom) -> bool:
	for pid in k.owned_provinces:
		var p: Province = WorldData.get_province(pid)
		if p == null or p.population <= 0:
			continue
		var band: StringName = p.unrest_band()
		if band == &"seething" or band == &"in revolt":
			return true
	return false


# --- Trait drift -------------------------------------------------------------

func _drift_trait(a: Actor, key: StringName, pressure: int) -> void:
	var current: int = int(a.get(key))
	var new_value: int = current

	if pressure > 0:
		new_value += pressure
	else:
		# Slow revert toward baseline when things are quiet.
		if current > BASELINE + REVERT_STEP:
			new_value -= REVERT_STEP
		elif current < BASELINE - REVERT_STEP:
			new_value += REVERT_STEP

	new_value = clampi(new_value, 0, 100)
	if new_value == current:
		return
	a.set(key, new_value)
