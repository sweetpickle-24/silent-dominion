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
	var expenditure: float = _monthly_expenditure(k)
	var net: float         = income - expenditure

	k.treasury_silver += net
	k.treasury_condition = _condition_for(k.treasury_silver, expenditure, net)
	_adjust_tax_level(k)

	return {
		"id":          k.id,
		"name":        k.kingdom_name,
		"income":      income,
		"expenditure": expenditure,
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
		var unrest_mult: float = float(UNREST_YIELD_MULTIPLIER.get(p.unrest_band(), 1.0))
		annual += province_total * unrest_mult
	var mult: float = float(TAX_LEVEL_MULTIPLIER.get(k.tax_level, 1.0))
	return (annual / MONTHS_PER_YEAR) * TAX_EFFICIENCY * mult


func _monthly_expenditure(k: Kingdom) -> float:
	return BASE_MONTHLY_COST + PER_PROVINCE_UPKEEP * float(k.owned_provinces.size())


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

	k.tax_level = target
	_emit_tax_change(k, old, target)


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
## state. Useful for the Ledger to show "this month: +12 / -9".
func preview(k: Kingdom) -> Dictionary:
	return {
		"income":      _monthly_income(k),
		"expenditure": _monthly_expenditure(k),
	}


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
			"burden_streak":      int(_burden_streak.get(k.id, 0)),
		})
	return out


func restore(arr: Array) -> void:
	_burden_streak.clear()
	for d in arr:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var id: String = String(d.get("id", ""))
		var k: Kingdom = WorldData.get_kingdom(id)
		if k == null:
			continue
		k.treasury_silver    = float(d.get("treasury_silver", k.treasury_silver))
		k.treasury_gold      = float(d.get("treasury_gold", k.treasury_gold))
		k.treasury_condition = int(d.get("treasury_condition", int(k.treasury_condition)))
		k.tax_level          = int(d.get("tax_level", int(k.tax_level)))
		_burden_streak[id]   = int(d.get("burden_streak", 0))
