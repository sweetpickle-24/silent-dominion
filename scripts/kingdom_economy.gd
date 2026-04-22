extends Node
## Autoloaded as `KingdomEconomy`. Runs the monthly treasury tick.
##
## Per §32.5 / §33.3 the player never manages kingdoms directly — they
## observe conditions. This module is the minimum viable simulation
## that produces those observable conditions.
##
## Each month:
##   1. Every kingdom's monthly income is summed from its owned provinces
##      (production × tax_efficiency).
##   2. A flat base cost plus a per-province upkeep is subtracted.
##   3. The resulting treasury is re-classified into the five Treasury
##      Condition bands using months-of-runway as the yardstick — that
##      way a tiny Corinth and a vast Persia both grade against their
##      own cost base instead of a world-wide silver threshold.
##
## Emits:
##   tick(month_snapshot) after the full pass, for any UI or logs
##     that want the raw numbers. The player-facing Ledger only reads
##     the qualitative condition off Kingdom itself.

signal tick(snapshot: Array)

# Very rough phase-0 tuning. Each province's production fields are in
# arbitrary units that roughly map to "silver equivalent per year"; we
# divide by 12 to get a monthly figure, then haircut by tax efficiency
# and a "only some of this reaches the crown" factor.
const TAX_EFFICIENCY: float       = 0.35   # baseline crown take (MODEST)
const MONTHS_PER_YEAR: float      = 12.0
const BASE_MONTHLY_COST: float    = 3.0    # court, diplomats, messengers
const PER_PROVINCE_UPKEEP: float  = 0.6    # garrisons, tax collectors, roads

# Per-level multipliers on TAX_EFFICIENCY. A ruinous year nearly doubles
# the crown's take; an indulgent year halves it. Rulers push the dial
# when they must, not when they wish.
const TAX_LEVEL_MULTIPLIER: Dictionary = {
	Kingdom.TaxLevel.INDULGENT: 0.55,
	Kingdom.TaxLevel.MODEST:    1.00,
	Kingdom.TaxLevel.BURDENED:  1.35,
	Kingdom.TaxLevel.RUINOUS:   1.75,
}

## Per-province multiplier on production when the province is restive.
## Quiet/uneasy/restless provinces pay in full — the friction hasn't
## reached the tax rolls yet. Seething and revolting provinces bleed.
const UNREST_YIELD_MULTIPLIER: Dictionary = {
	&"quiet":     1.00,
	&"uneasy":    1.00,
	&"restless":  0.95,
	&"seething":  0.80,
	&"in revolt": 0.30,
}

# How many months a given level can persist before the ruler is
# pressured back down. Tracked per-kingdom in _burden_streak.
const MAX_BURDENED_MONTHS: int = 12
const MAX_RUINOUS_MONTHS:  int = 4

var _burden_streak: Dictionary = {}  # kingdom_id -> months at BURDENED+

# --- War costs (§33.3 lever chain) -------------------------------------------
#
# Per §33.3 a war is supposed to produce treasury strain via military
# expenditure. Every month a kingdom is at war with at least one other
# kingdom, it pays a flat WAR_BASE_COST + a per-province scalar for
# its army footprint. The burden ramps with war length: mobilisation
# is cheap, a long war is not. Each additional active war layers a
# FRONT_MULTIPLIER on top — a two-front war is meaningfully worse
# than a one-front war, but not double, because the army can't be
# everywhere at once.
const WAR_BASE_COST:          float = 4.0
const WAR_PER_PROVINCE_COST:  float = 0.8
const WAR_RAMP_PER_MONTH:     float = 0.04   # +4% per month at war
const WAR_RAMP_CAP:           float = 1.5    # caps at +150%
const FRONT_MULTIPLIER:       float = 0.6    # additional fronts at 60% cost

var _war_streak: Dictionary = {}  # kingdom_id -> consecutive months with at least one active war

## Per-kingdom rolling history of the treasury condition, one slot per
## tick. Oldest entries drop off. Used by the Ledger to render a small
## trajectory strip so the player can read "bleeding / holding / building"
## at a glance instead of only seeing today's grade.
const HISTORY_CAPACITY: int = 12
var _history: Dictionary = {}  # kingdom_id -> Array[int]


func _ready() -> void:
	GameClock.month_passed.connect(_on_month_passed)


# --- Tick --------------------------------------------------------------------

func _on_month_passed(_y: int, _m: int) -> void:
	if not WorldData.is_loaded():
		return
	var snap: Array = []
	for k in WorldData.kingdoms.values():
		snap.append(_tick_kingdom(k))
	tick.emit(snap)


func _tick_kingdom(k: Kingdom) -> Dictionary:
	var income: float      = _monthly_income(k)
	var war_cost: float    = _monthly_war_cost(k)
	var expenditure: float = _monthly_expenditure(k) + war_cost
	var net: float         = income - expenditure

	var before_condition: int = int(k.treasury_condition)
	k.treasury_silver += net
	k.treasury_condition = _condition_for(k.treasury_silver, expenditure, net)
	_maybe_emit_treasury_transition(k, before_condition, int(k.treasury_condition))
	_adjust_tax_level(k)
	_record_history(k)

	return {
		"id":          k.id,
		"name":        k.kingdom_name,
		"income":      income,
		"expenditure": expenditure,
		"war_cost":    war_cost,
		"net":         net,
		"treasury":    k.treasury_silver,
		"condition":   int(k.treasury_condition),
		"tax_level":   int(k.tax_level),
	}


# --- Lever inputs ------------------------------------------------------------

func _monthly_income(k: Kingdom) -> float:
	var annual: float = 0.0
	for pid in k.owned_provinces:
		var p: Province = WorldData.get_province(pid)
		if p == null:
			continue
		var province_total: float = (
			p.grain_production
			+ p.silver_production
			+ p.iron_production
			+ p.timber_production
		)
		# Infrastructure lifts production once built.
		#   road_network : +8% on everything it carries
		#   harbour      : +15% on silver (coastal trade)
		if p.has_building(&"road_network"):
			province_total *= 1.08
		if p.has_building(&"harbour"):
			province_total += p.silver_production * 0.15
		var unrest_mult: float = float(UNREST_YIELD_MULTIPLIER.get(p.unrest_band(), 1.0))
		annual += province_total * unrest_mult
	var mult: float = float(TAX_LEVEL_MULTIPLIER.get(k.tax_level, 1.0))
	# A regency loses roughly a fifth of what the crown would have
	# collected to the council's own pockets and to provincial magnates
	# who sense the empty throne. Grinds on the books until a ruler
	# is installed.
	var regency_mult: float = 0.8 if k.in_regency else 1.0
	return (annual / MONTHS_PER_YEAR) * TAX_EFFICIENCY * mult * regency_mult


func _monthly_expenditure(k: Kingdom) -> float:
	return BASE_MONTHLY_COST + PER_PROVINCE_UPKEEP * float(k.owned_provinces.size())


## Monthly silver the crown bleeds for active wars. Returns 0 for
## kingdoms at peace. For kingdoms at war, it is a base mobilisation
## cost plus a per-province army-footprint scalar, times a ramp that
## climbs with how many months the kingdom has been at war, with
## additional fronts layered on at reduced cost. Mutates the per-
## kingdom war streak counter, so this must be called exactly once
## per kingdom per monthly tick.
func _monthly_war_cost(k: Kingdom) -> float:
	var fronts: int = Relations.ids_in_state(k.id, int(Relations.RelationState.AT_WAR)).size()
	if fronts <= 0:
		_war_streak.erase(k.id)
		return 0.0

	var streak: int = int(_war_streak.get(k.id, 0)) + 1
	_war_streak[k.id] = streak

	var pop_provinces: int = 0
	for pid in k.owned_provinces:
		var p: Province = WorldData.get_province(pid)
		if p != null and p.population > 0:
			pop_provinces += 1

	var base: float = WAR_BASE_COST + WAR_PER_PROVINCE_COST * float(pop_provinces)
	var ramp: float = clampf(WAR_RAMP_PER_MONTH * float(streak - 1), 0.0, WAR_RAMP_CAP)
	var front_scale: float = 1.0 + FRONT_MULTIPLIER * float(fronts - 1)
	return base * (1.0 + ramp) * front_scale


## Rulers reach for the tax lever when they must. If the treasury is
## strained or worse, they push the dial up; if it is flush and has
## been for a while at a heavy level, they ease back. Streak counters
## enforce a cap on how long a ruler can sit at painful settings before
## political pressure forces a climbdown. Any change emits a public
## event so the scroll and digest pick it up.
func _adjust_tax_level(k: Kingdom) -> void:
	var old: int = int(k.tax_level)
	var streak: int = int(_burden_streak.get(k.id, 0))
	var target: int = old

	match k.treasury_condition:
		Kingdom.TreasuryCondition.BROKE, Kingdom.TreasuryCondition.INDEBTED:
			target = int(Kingdom.TaxLevel.RUINOUS)
		Kingdom.TreasuryCondition.STRAINED:
			target = int(Kingdom.TaxLevel.BURDENED)
		Kingdom.TreasuryCondition.STABLE:
			target = int(Kingdom.TaxLevel.MODEST)
		Kingdom.TreasuryCondition.FLUSH:
			target = int(Kingdom.TaxLevel.INDULGENT) if old == int(Kingdom.TaxLevel.MODEST) else int(Kingdom.TaxLevel.MODEST)

	target = _personality_bias_tax(k, old, target)

	# Cap how long a ruler can stay at painful settings. Once the cap
	# is hit, force a step down regardless of the treasury state.
	if old == int(Kingdom.TaxLevel.RUINOUS):
		streak += 1
		if streak >= MAX_RUINOUS_MONTHS:
			target = int(Kingdom.TaxLevel.BURDENED)
			streak = 0
	elif old == int(Kingdom.TaxLevel.BURDENED):
		streak += 1
		if streak >= MAX_BURDENED_MONTHS:
			target = int(Kingdom.TaxLevel.MODEST)
			streak = 0
	else:
		streak = 0

	_burden_streak[k.id] = streak

	if target == old:
		return

	k.tax_level = target as Kingdom.TaxLevel
	_emit_tax_change(k, old, target)


## Shift the purely treasury-driven target by the reigning ruler's
## personality. Greedy and ruthless crowns push the dial one notch up;
## pious crowns won't push it to the highest painful setting without
## reason; paranoid crowns who feel their streets getting restless
## climb down sooner than the books say they should. The treasury
## still sets the base; this is only a ±1 nudge.
func _personality_bias_tax(k: Kingdom, old: int, target: int) -> int:
	var ruler: Actor = Actors.ruler_of(k.id)
	if ruler == null or not ruler.is_alive():
		return target

	var shift: int = 0

	# Pressure upward: greed + ruthlessness want more silver through.
	var greed_pressure: int = 0
	if ruler.greed >= 70:        greed_pressure += 1
	if ruler.ruthlessness >= 70: greed_pressure += 1
	if greed_pressure > 0 and target < int(Kingdom.TaxLevel.RUINOUS):
		shift += 1

	# Pressure downward: pious rulers balk at ruinous levies; paranoid
	# rulers with a restless capital feel the danger and ease back.
	var restraint: int = 0
	if ruler.piety >= 70 and target == int(Kingdom.TaxLevel.RUINOUS):
		restraint += 1
	if ruler.paranoia >= 70 and _kingdom_is_restless(k) and target >= int(Kingdom.TaxLevel.BURDENED):
		restraint += 1
	if restraint > 0:
		shift -= 1

	if shift == 0:
		return target

	var nudged: int = clampi(target + shift, int(Kingdom.TaxLevel.INDULGENT), int(Kingdom.TaxLevel.RUINOUS))

	# Don't let personality snap the dial around on its own. If the
	# biased target differs from the treasury-driven target by more
	# than one notch off `old`, hold the line.
	if abs(nudged - old) > 1:
		return target

	return nudged


func _kingdom_is_restless(k: Kingdom) -> bool:
	for pid in k.owned_provinces:
		var p: Province = WorldData.get_province(pid)
		if p == null or p.population <= 0:
			continue
		var band: StringName = p.unrest_band()
		if band == &"seething" or band == &"in revolt" or band == &"restless":
			return true
	return false


func _emit_tax_change(k: Kingdom, from_level: int, to_level: int) -> void:
	var going_up: bool = to_level > from_level
	var headline: String
	var body: String
	if going_up:
		headline = "Heavier taxes in %s" % k.kingdom_name
		body = "The crown of %s has raised its rates. The new setting is %s. Markets are already quieter than yesterday." % [
			k.kingdom_name, k.tax_level_phrase(),
		]
	else:
		headline = "%s eases the tax bench" % k.kingdom_name
		body = "Word from %s: the levies are loosened. The crown calls it relief; lenders call it something else. The new setting is %s." % [
			k.kingdom_name, k.tax_level_phrase(),
		]
	EventBus.public_event.emit({
		"kind":       &"tax_change",
		"kingdom_id": k.id,
		"headline":   headline,
		"body":       body,
	})


## Emit a public dispatch when the treasury condition crosses a line
## the player ought to see from the scroll. Specifically: slipping
## into STRAINED or worse is announced, and climbing back out of
## INDEBTED/BROKE is announced as recovery. Small drifts between
## neighbouring good bands (FLUSH <-> STABLE) stay quiet — the
## player can open the Ledger for the detail.
func _maybe_emit_treasury_transition(k: Kingdom, before: int, after: int) -> void:
	if before == after:
		return
	var getting_worse: bool = after > before
	var into_crisis: bool = after >= int(Kingdom.TreasuryCondition.STRAINED)
	var out_of_crisis: bool = (
		before >= int(Kingdom.TreasuryCondition.INDEBTED)
		and after <= int(Kingdom.TreasuryCondition.STRAINED)
	)
	if getting_worse and into_crisis:
		_emit_treasury_decline(k, before, after)
	elif not getting_worse and out_of_crisis:
		_emit_treasury_recovery(k, before, after)


func _emit_treasury_decline(k: Kingdom, _before: int, after: int) -> void:
	var headline: String
	var body: String
	match after:
		int(Kingdom.TreasuryCondition.STRAINED):
			headline = "The books are tightening in %s" % k.kingdom_name
			body = "The crown of %s has passed from sound footing to strained. The grain is still moving, the soldiers are still paid; but somewhere a ledger has been shown to someone, and the tone at court has changed." % k.kingdom_name
		int(Kingdom.TreasuryCondition.INDEBTED):
			headline = "%s runs on borrowed silver" % k.kingdom_name
			body = "The crown of %s is no longer solvent on its own income. The bankers have been seen at the palace gate and they did not come for the hospitality. Expect the crown to reach somewhere — new taxes, a sold office, or a dangerous loan." % k.kingdom_name
		int(Kingdom.TreasuryCondition.BROKE):
			headline = "A crown out of coin: %s" % k.kingdom_name
			body = "The treasury of %s is empty. Soldiers go unpaid past their date; the bread price at court has quietly risen; the envoys sent abroad this season will travel light. Someone, somewhere, is going to have to break." % k.kingdom_name
		_:
			return
	EventBus.public_event.emit({
		"kind":       &"fiscal_crisis",
		"kingdom_id": k.id,
		"headline":   headline,
		"body":       body,
	})


func _emit_treasury_recovery(k: Kingdom, _before: int, _after: int) -> void:
	EventBus.public_event.emit({
		"kind":       &"fiscal_recovery",
		"kingdom_id": k.id,
		"headline":   "%s finds its footing" % k.kingdom_name,
		"body":       "The books in %s are readable again. Soldiers paid on time, creditors quieter, the palace gates no longer watched by men in plain coats. Whatever was done — a tax, a loan, a province sold off — has bought the crown some air." % k.kingdom_name,
	})


## Re-grade the treasury based on runway (months of cover) and whether
## the kingdom is running a surplus or deficit. The thresholds here are
## deliberate and documented in §32.5.
func _condition_for(treasury: float, expenditure: float, net: float) -> Kingdom.TreasuryCondition:
	if treasury < 0.0:
		return Kingdom.TreasuryCondition.BROKE

	var runway: float = treasury / max(1.0, expenditure)
	if runway < 2.0:
		return Kingdom.TreasuryCondition.INDEBTED
	if runway < 6.0:
		return Kingdom.TreasuryCondition.STRAINED
	if runway < 24.0 or net < 0.0:
		return Kingdom.TreasuryCondition.STABLE
	return Kingdom.TreasuryCondition.FLUSH


# --- Public helpers ----------------------------------------------------------

## Snapshot the current month's flow for a kingdom without mutating
## state. Useful for the Ledger to show "this month: +12 / -9". Reads
## the war-cost contribution without advancing the streak counter.
func preview(k: Kingdom) -> Dictionary:
	var war_cost: float = _preview_war_cost(k)
	return {
		"income":      _monthly_income(k),
		"expenditure": _monthly_expenditure(k) + war_cost,
		"war_cost":    war_cost,
	}


## Non-mutating variant of `_monthly_war_cost` for UI previews. Uses
## the existing streak counter without incrementing it.
func _preview_war_cost(k: Kingdom) -> float:
	var fronts: int = Relations.ids_in_state(k.id, int(Relations.RelationState.AT_WAR)).size()
	if fronts <= 0:
		return 0.0
	var streak: int = maxi(1, int(_war_streak.get(k.id, 1)))
	var pop_provinces: int = 0
	for pid in k.owned_provinces:
		var p: Province = WorldData.get_province(pid)
		if p != null and p.population > 0:
			pop_provinces += 1
	var base: float = WAR_BASE_COST + WAR_PER_PROVINCE_COST * float(pop_provinces)
	var ramp: float = clampf(WAR_RAMP_PER_MONTH * float(streak - 1), 0.0, WAR_RAMP_CAP)
	var front_scale: float = 1.0 + FRONT_MULTIPLIER * float(fronts - 1)
	return base * (1.0 + ramp) * front_scale


## The last HISTORY_CAPACITY treasury conditions for this kingdom, oldest
## first. The most recent entry is the current grade. If the simulation
## has not ticked yet, the array only contains the seeded condition so
## callers can still draw a one-slot strip.
func history_for(kingdom_id: String) -> Array:
	var arr: Array = _history.get(kingdom_id, [])
	if arr.is_empty():
		var k: Kingdom = WorldData.get_kingdom(kingdom_id)
		if k != null:
			return [int(k.treasury_condition)]
	return arr.duplicate()


## Returns one of the following phrases describing the kingdom's
## trajectory over the last few months. Used by the Ledger detail view.
##   "bleeding"    — conditions have worsened on net
##   "holding"     — roughly flat
##   "building"    — conditions have improved on net
func trajectory_phrase(kingdom_id: String) -> String:
	var arr: Array = history_for(kingdom_id)
	if arr.size() < 2:
		return "Too soon to say which way the wind sits."
	var first: int = int(arr[0])
	var last: int = int(arr[arr.size() - 1])
	# Treasury conditions are ordered FLUSH(0) -> BROKE(4). Higher number
	# means worse — so a positive delta means the kingdom is declining.
	var delta: int = last - first
	if delta >= 2:
		return "The trend is plain: the crown has been bleeding."
	if delta == 1:
		return "The crown has slipped a step this season. Not a rout, but a drift."
	if delta == 0:
		return "The year holds its shape. Neither ruin nor windfall."
	if delta == -1:
		return "A small recovery — the ground is firmer than it was."
	return "The crown has climbed out of the hole. Whoever advised them knew what they were doing."


func _record_history(k: Kingdom) -> void:
	var arr: Array = _history.get(k.id, [])
	arr.append(int(k.treasury_condition))
	while arr.size() > HISTORY_CAPACITY:
		arr.pop_front()
	_history[k.id] = arr


# --- Save/load hooks ---------------------------------------------------------

## Collect per-kingdom treasury state. Static data (name, provinces) is
## re-seeded from JSON on every boot, so we only need to persist the
## fields that drift: treasury figures + the derived condition.
func snapshot() -> Array:
	var out: Array = []
	for k in WorldData.kingdoms.values():
		out.append({
			"id":                 k.id,
			"treasury_silver":    k.treasury_silver,
			"treasury_gold":      k.treasury_gold,
			"treasury_condition": int(k.treasury_condition),
			"tax_level":          int(k.tax_level),
			"in_regency":         k.in_regency,
			"burden_streak":      int(_burden_streak.get(k.id, 0)),
			"war_streak":         int(_war_streak.get(k.id, 0)),
			"history":            _history.get(k.id, []).duplicate(),
		})
	return out


func restore(arr: Array) -> void:
	_burden_streak.clear()
	_war_streak.clear()
	_history.clear()
	for d in arr:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var id: String = String(d.get("id", ""))
		var k: Kingdom = WorldData.get_kingdom(id)
		if k == null:
			continue
		k.treasury_silver    = float(d.get("treasury_silver", k.treasury_silver))
		k.treasury_gold      = float(d.get("treasury_gold", k.treasury_gold))
		k.treasury_condition = int(d.get("treasury_condition", int(k.treasury_condition))) as Kingdom.TreasuryCondition
		k.tax_level          = int(d.get("tax_level", int(k.tax_level))) as Kingdom.TaxLevel
		k.in_regency         = bool(d.get("in_regency", false))
		_burden_streak[id]   = int(d.get("burden_streak", 0))
		_war_streak[id]      = int(d.get("war_streak", 0))
		var hist: Array = []
		for v in d.get("history", []):
			hist.append(int(v))
		_history[id] = hist
