class_name Kingdom
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _world_registry: Node

var _kingdoms: Dictionary = {}          # StringName id -> KingdomRecord
var _place_to_kingdom: Dictionary = {}  # StringName place_id -> StringName kingdom_id
var _tick_sub

# --- Calibration constants (placeholder, flagged for calibration pass) ---
const BASE_COLLECTION_EFFICIENCY: float = 0.7
const DISTANCE_PENALTY_PER_HOP: float = 0.05   # per province hop from capital
const MAX_DISTANCE_PENALTY: float = 0.3
const CORRUPTION_FACTOR: float = 0.1
const ARMY_MAINTENANCE_PER_SOLDIER: int = 1     # per day
const COURT_COST_BASE: int = 5                  # per day
const DEBT_SERVICE_RATE: float = 0.01           # fraction of debt paid per day of service

# Treasury condition band thresholds (ratio of derived_value to expenditure)
const BAND_FLUSH_THRESHOLD: float = 2.0
const BAND_STABLE_THRESHOLD: float = 1.0
const BAND_STRAINED_THRESHOLD: float = 0.5
const BAND_INDEBTED_THRESHOLD: float = 0.0     # net negative after debt

# Unrest dynamics — rates yield at least 1 for typical deltas
const UNREST_FROM_HIGH_TAX_PER_DAY: float = 0.1      # per tax_level point above 50
const UNREST_FROM_LOW_LEGITIMACY_PER_DAY: float = 0.05  # per legitimacy point below 50
const UNREST_DECAY_PER_DAY: float = 1.0
const UNREST_THRESHOLDS: Array = [30, 50, 70, 90]


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_world_registry = get_node("/root/WorldRegistry")
	_load_kingdoms()
	_tick_sub = _event_bus.subscribe(
		preload("res://scripts/data/events/game_day_ticked_event.gd"),
		Callable(self, "_on_game_day_ticked"),
		150, &"", EndOfTickPhases.WORLD_SHARED,
	)
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"kingdom_state",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)
	_logger.info(LogChannels.KINGDOM, "Kingdom mechanic ready", {"kingdoms": _kingdoms.size()})


func _load_kingdoms() -> void:
	var dir := DirAccess.open("res://data/kingdoms/")
	if dir == null:
		_logger.info(LogChannels.KINGDOM, "No data/kingdoms/ directory — no kingdoms loaded")
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res = ResourceLoader.load("res://data/kingdoms/" + fname)
			if res is KingdomRecord:
				_kingdoms[res.id] = res
				for place_id: StringName in res.member_place_ids:
					_place_to_kingdom[place_id] = res.id
		fname = dir.get_next()
	dir.list_dir_end()


# --- Public API ---

func get_kingdom(id: StringName) -> KingdomRecord:
	return _kingdoms.get(id, null)


func all_kingdom_ids() -> Array:
	return _kingdoms.keys()


func kingdom_count() -> int:
	return _kingdoms.size()


func kingdom_of_place(place_id: StringName) -> StringName:
	return _place_to_kingdom.get(place_id, &"")


func derived_treasury_value(kingdom_id: StringName) -> int:
	var k: KingdomRecord = _kingdoms.get(kingdom_id, null)
	if k == null:
		return 0
	var income: int = _compute_tax_income(k)
	var expenditure: int = _compute_expenditure(k)
	return income - expenditure


func derived_military_strength(kingdom_id: StringName) -> int:
	var k: KingdomRecord = _kingdoms.get(kingdom_id, null)
	if k == null:
		return 0
	var levy: int = 0
	var pop_node: Node = get_node_or_null("../Population")
	for place_id: StringName in k.member_place_ids:
		if pop_node != null:
			levy += pop_node.levy_capacity(place_id)
		else:
			# Fallback: read place.population directly (pre-Population-mechanic compat)
			var place: PlaceRecord = _world_registry.get_place(place_id)
			if place != null:
				levy += int(place.population * 0.05)
	return levy + k.standing_army


func treasury_condition_of(kingdom_id: StringName) -> StringName:
	var k: KingdomRecord = _kingdoms.get(kingdom_id, null)
	if k == null:
		return &"stable"
	return k.treasury_condition


# --- Per-day update ---

func _on_game_day_ticked(event: GameDayTickedEvent) -> void:
	for kingdom_id: StringName in _kingdoms.keys():
		_update_kingdom(kingdom_id, event.day)


func _update_kingdom(kingdom_id: StringName, day: int) -> void:
	var k: KingdomRecord = _kingdoms[kingdom_id]

	# 1. Compute derived treasury value
	var income: int = _compute_tax_income(k)
	var expenditure: int = _compute_expenditure(k)
	var net: int = income - expenditure

	# 2. Update treasury condition band
	var old_condition: StringName = k.treasury_condition
	k.treasury_condition = _compute_condition_band(net, expenditure, k.total_debt())
	if k.treasury_condition != old_condition:
		var tc_event := KingdomTreasuryConditionChangedEvent.new()
		tc_event.kingdom_id = kingdom_id
		tc_event.old_condition = old_condition
		tc_event.new_condition = k.treasury_condition
		tc_event.day = day
		_event_bus.dispatch(tc_event)

	# 3. Update unrest
	var old_unrest: int = k.unrest
	_update_unrest(k)
	_check_unrest_thresholds(kingdom_id, old_unrest, k.unrest, day)

	# 4. Accumulate tax into place accumulated_yield (places handle their own yield;
	#    kingdom just reads it). Nothing to do here — Place mechanic handles accumulation.


func _compute_tax_income(k: KingdomRecord) -> int:
	var total: int = 0
	for place_id: StringName in k.member_place_ids:
		var place: PlaceRecord = _world_registry.get_place(place_id)
		if place == null:
			continue
		var raw_yield: int = place.tax_yield_per_day
		var efficiency: float = _collection_efficiency(place, k)
		total += int(raw_yield * efficiency * k.tax_level / 40.0 * k.era_tax_efficiency_modifier)
	return total


func _collection_efficiency(place: PlaceRecord, k: KingdomRecord) -> float:
	var eff: float = BASE_COLLECTION_EFFICIENCY
	# Loyalty factor: high civic/mercantile faction = more compliant collection
	var loyalty: float = place.factional_balance.get(&"civic", 0.0) + place.factional_balance.get(&"mercantile", 0.0)
	eff *= (0.7 + loyalty * 0.6)  # loyalty 0→0.7; loyalty 0.5→1.0
	# Distance from capital (placeholder — count province hops)
	if place.id != k.capital_place_id:
		var distance_penalty: float = minf(DISTANCE_PENALTY_PER_HOP, MAX_DISTANCE_PENALTY)
		eff *= (1.0 - distance_penalty)
	# Corruption factor (placeholder)
	eff *= (1.0 - CORRUPTION_FACTOR)
	return clampf(eff, 0.0, 1.0)


func _compute_expenditure(k: KingdomRecord) -> int:
	var army_cost: int = k.standing_army * ARMY_MAINTENANCE_PER_SOLDIER
	var court_cost: int = COURT_COST_BASE
	var debt_service: int = int(k.total_debt() * DEBT_SERVICE_RATE)
	return army_cost + court_cost + debt_service


func _compute_condition_band(net_value: int, expenditure: int, total_debt: int) -> StringName:
	if expenditure <= 0:
		return &"flush" if net_value > 0 else &"stable"
	var ratio: float = float(net_value) / float(maxi(expenditure, 1))
	if total_debt > 0 and net_value < 0:
		return &"broke" if ratio < -0.5 else &"indebted"
	if ratio >= BAND_FLUSH_THRESHOLD:
		return &"flush"
	if ratio >= BAND_STABLE_THRESHOLD:
		return &"stable"
	if ratio >= BAND_STRAINED_THRESHOLD:
		return &"strained"
	if total_debt > 0:
		return &"indebted"
	return &"strained"


func _update_unrest(k: KingdomRecord) -> void:
	var delta: float = 0.0
	# High tax builds unrest
	if k.tax_level > 50:
		delta += (k.tax_level - 50) * UNREST_FROM_HIGH_TAX_PER_DAY
	# Low legitimacy builds unrest
	if k.legitimacy < 50:
		delta += (50 - k.legitimacy) * UNREST_FROM_LOW_LEGITIMACY_PER_DAY
	# Demographic pressure: migration outflow / scarcity in member places
	var pop_node: Node = get_node_or_null("../Population")
	if pop_node != null:
		var pressure: float = 0.0
		for place_id: StringName in k.member_place_ids:
			pressure += pop_node.migration_pressure(place_id)
		if k.member_place_ids.size() > 0:
			pressure /= k.member_place_ids.size()
		delta += pressure * 2.0  # demographic pressure adds to unrest
	# Natural decay
	if delta <= 0.0:
		delta = -UNREST_DECAY_PER_DAY
	k.unrest = clampi(k.unrest + int(delta), 0, 100)


func _check_unrest_thresholds(kingdom_id: StringName, old_unrest: int, new_unrest: int, day: int) -> void:
	for threshold: int in UNREST_THRESHOLDS:
		if old_unrest < threshold and new_unrest >= threshold:
			var ue := KingdomUnrestThresholdCrossedEvent.new()
			ue.kingdom_id = kingdom_id
			ue.old_unrest = old_unrest
			ue.new_unrest = new_unrest
			ue.threshold = threshold
			ue.day = day
			_event_bus.dispatch(ue)


# --- Decision application (called by RulerAI via events) ---

func apply_tax_level_change(kingdom_id: StringName, delta: int, day: int) -> void:
	var k: KingdomRecord = _kingdoms.get(kingdom_id, null)
	if k == null:
		return
	var old: int = k.tax_level
	k.tax_level = clampi(k.tax_level + delta, 0, 100)
	if k.tax_level != old:
		var te := KingdomTaxLevelChangedEvent.new()
		te.kingdom_id = kingdom_id
		te.old_level = old
		te.new_level = k.tax_level
		te.day = day
		_event_bus.dispatch(te)


func apply_debt_change(kingdom_id: StringName, creditor_id: StringName, amount: int) -> void:
	var k: KingdomRecord = _kingdoms.get(kingdom_id, null)
	if k == null:
		return
	var current: int = k.debt_by_creditor.get(creditor_id, 0)
	k.debt_by_creditor[creditor_id] = maxi(current + amount, 0)
	if k.debt_by_creditor[creditor_id] == 0:
		k.debt_by_creditor.erase(creditor_id)


func apply_army_change(kingdom_id: StringName, delta: int) -> void:
	var k: KingdomRecord = _kingdoms.get(kingdom_id, null)
	if k == null:
		return
	k.standing_army = maxi(k.standing_army + delta, 0)


func apply_faction_shift(kingdom_id: StringName, faction: StringName, delta: int) -> void:
	var k: KingdomRecord = _kingdoms.get(kingdom_id, null)
	if k == null:
		return
	match faction:
		&"military": k.faction_military = clampi(k.faction_military + delta, 0, 100)
		&"clergy": k.faction_clergy = clampi(k.faction_clergy + delta, 0, 100)
		&"merchants": k.faction_merchants = clampi(k.faction_merchants + delta, 0, 100)
		&"nobility": k.faction_nobility = clampi(k.faction_nobility + delta, 0, 100)


func apply_rivalry_tension_change(kingdom_id: StringName, other_kingdom_id: StringName, delta: int) -> void:
	var k: KingdomRecord = _kingdoms.get(kingdom_id, null)
	if k == null:
		return
	var current: int = k.rivalry_tensions.get(other_kingdom_id, 0)
	k.rivalry_tensions[other_kingdom_id] = clampi(current + delta, 0, 100)


func apply_legitimacy_change(kingdom_id: StringName, delta: int) -> void:
	var k: KingdomRecord = _kingdoms.get(kingdom_id, null)
	if k == null:
		return
	k.legitimacy = clampi(k.legitimacy + delta, 0, 100)


# --- Save/load ---

func snapshot_state() -> Dictionary:
	return {"kingdoms": _kingdoms.duplicate(true), "place_to_kingdom": _place_to_kingdom.duplicate(true)}


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_kingdoms = state.get("kingdoms", {}).duplicate(true)
	_place_to_kingdom = state.get("place_to_kingdom", {}).duplicate(true)
	_logger.info(LogChannels.KINGDOM, "Kingdom state applied from load")
