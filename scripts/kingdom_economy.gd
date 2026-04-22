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
const TAX_EFFICIENCY: float       = 0.35   # crown take of provincial output
const MONTHS_PER_YEAR: float      = 12.0
const BASE_MONTHLY_COST: float    = 3.0    # court, diplomats, messengers
const PER_PROVINCE_UPKEEP: float  = 0.6    # garrisons, tax collectors, roads


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

	return {
		"id":          k.id,
		"name":        k.kingdom_name,
		"income":      income,
		"expenditure": expenditure,
		"net":         net,
		"treasury":    k.treasury_silver,
		"condition":   int(k.treasury_condition),
	}


# --- Lever inputs ------------------------------------------------------------

func _monthly_income(k: Kingdom) -> float:
	var annual: float = 0.0
	for pid in k.owned_provinces:
		var p: Province = WorldData.get_province(pid)
		if p == null:
			continue
		annual += p.grain_production
		annual += p.silver_production
		annual += p.iron_production
		annual += p.timber_production
	return (annual / MONTHS_PER_YEAR) * TAX_EFFICIENCY


func _monthly_expenditure(k: Kingdom) -> float:
	return BASE_MONTHLY_COST + PER_PROVINCE_UPKEEP * float(k.owned_provinces.size())


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
		})
	return out


func restore(arr: Array) -> void:
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
