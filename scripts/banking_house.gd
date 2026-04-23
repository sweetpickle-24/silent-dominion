class_name BankingHouse
extends Resource
## One financial relationship the player can draw on (§16.1).
##
## The player does not hold silver in abstract — they hold arrangements
## with specific banking houses, merchant consortiums, and wealthy
## individuals who can produce funds in specific places. Three attributes
## shape any such relationship:
##
##   - capacity   — how much can be produced this season before strain.
##   - discretion — how well the house hides the source/destination.
##   - reach      — which kingdoms the house can move money to or from.
##
## Houses mature over years of careful use. Pushed too hard, they grow
## curious about their patron (intelligence risk, §16.4). Ignored too
## long, the relationship atrophies (§16.2).

@export var id: StringName = &""
@export var display_name: String = ""

## The kingdom this house calls home. Always in its own reach.
@export var home_kingdom: String = ""

## A short period-appropriate flavour line shown in the Vault view.
## Seeded at creation; not dynamic.
@export var house_kind: String = ""              # "merchant consortium", "temple treasury", ...

## Current spendable silver capacity, 0..max_capacity. Consumed by every
## silver-denominated funded operation in proportion to the amount moved.
@export var capacity: int = 40

## Soft ceiling on silver capacity. Grows slowly with tenure; pulled down
## when a relationship is overdrawn. Hard capped at 100.
@export var max_capacity: int = 50

## Gold capacity — a separately tracked reserve (§16 / docs §32.4).
## Gold moves slower but is denser: one point of gold capacity funds
## substantially more silver-equivalent value than one point of silver
## capacity. Houses that specialise in gold (temple treasuries) open
## with a non-zero gold pool; merchant consortiums start at 0.
@export var gold_capacity: int = 0
@export var gold_max_capacity: int = 0

## Rate at which capacity refills each month in-game, as a % of
## max_capacity. Chosen so a healthy house refills a spent chunk
## over ~3-4 months without player action.
@export_range(0, 100) var monthly_regen_pct: int = 25

## How well a transaction routed through this house conceals the
## player. 0..100. Decays slightly each time we push a big one.
@export_range(0, 100) var discretion: int = 45

## Kingdoms this house can transact in. Always includes home_kingdom.
## Grows over time or when the player links houses together (§16.1).
@export var reach: Array[String] = []

## Months this relationship has been in service. Used for slow growth
## of max_capacity and discretion.
@export var maturity_months: int = 0

## How "curious" the house has become about their patron. 0..100.
## Rises faster with large, frequent, or cross-border transactions.
## Once it crosses the suspicion threshold, every transaction halves
## in discretion until rotated out or serviced.
@export_range(0, 100) var curiosity: int = 0

## Number of overdrawn / cancelled funding attempts. Tracked for
## audit-style decisions later.
@export var overdraw_count: int = 0

## A house that has been turned by a rival society (§16.4). Every
## transaction it executes is also visible to the enemy. Currently
## set by an action; future hook for rivals doing it themselves.
@export var compromised: bool = false

## Terminal state. A lost house cannot be drawn on; kept in the
## registry so the Vault can show its tombstone for a while.
@export var dissolved: bool = false
@export var dissolved_reason: StringName = &""


const CURIOSITY_SUSPICION_THRESHOLD: int = 60


func is_suspicious() -> bool:
	return curiosity >= CURIOSITY_SUSPICION_THRESHOLD


func is_usable() -> bool:
	return not dissolved and not compromised


func effective_discretion() -> int:
	if compromised:
		return 0
	if is_suspicious():
		@warning_ignore("integer_division")
		return discretion / 2
	return discretion


func capacity_band() -> StringName:
	return _band_for(capacity, max_capacity)


func capacity_band_label() -> String:
	return _band_label(capacity_band())


## Qualitative band for the gold reserve. Mirrors `capacity_band` but
## reads the gold pool. Houses with no gold reserve report &"none".
func gold_capacity_band() -> StringName:
	if dissolved:                 return &"closed"
	if gold_max_capacity <= 0:    return &"none"
	return _band_for(gold_capacity, gold_max_capacity)


func gold_capacity_band_label() -> String:
	var b: StringName = gold_capacity_band()
	if b == &"none":
		return "No gold"
	return _band_label(b)


func _band_for(current: int, ceiling: int) -> StringName:
	if dissolved:                         return &"closed"
	if current <= 0:                      return &"tapped_out"
	if current * 4 < ceiling:             return &"strained"
	if current * 2 < ceiling:             return &"cautious"
	return &"ample"


func _band_label(b: StringName) -> String:
	match b:
		&"closed":     return "Shuttered"
		&"tapped_out": return "Tapped out"
		&"strained":   return "Strained"
		&"cautious":   return "Cautious"
		&"ample":      return "Ample"
	return "Unknown"


## Capacity remaining for the given currency. Currencies: &"silver", &"gold".
## Unknown currencies fall back to silver for legacy callers.
func capacity_for(currency: StringName) -> int:
	match currency:
		&"gold":   return gold_capacity
	return capacity


## Soft ceiling for the given currency.
func max_capacity_for(currency: StringName) -> int:
	match currency:
		&"gold":   return gold_max_capacity
	return max_capacity


func spend_capacity(currency: StringName, amount: int) -> void:
	match currency:
		&"gold":
			gold_capacity = maxi(0, gold_capacity - amount)
		_:
			capacity = maxi(0, capacity - amount)


func refund_capacity(currency: StringName, amount: int) -> void:
	match currency:
		&"gold":
			gold_capacity = mini(gold_max_capacity, gold_capacity + amount)
		_:
			capacity = mini(max_capacity, capacity + amount)


func discretion_band() -> StringName:
	var d: int = effective_discretion()
	if compromised: return &"compromised"
	if is_suspicious(): return &"suspicious"
	if d >= 75: return &"invisible"
	if d >= 55: return &"discreet"
	if d >= 35: return &"ordinary"
	return &"loose"


func discretion_band_label() -> String:
	match discretion_band():
		&"compromised": return "Compromised"
		&"suspicious":  return "Curious"
		&"invisible":   return "Invisible"
		&"discreet":    return "Discreet"
		&"ordinary":    return "Ordinary"
		&"loose":       return "Loose"
	return "Unknown"


# --- Serialisation -----------------------------------------------------------

static func from_dict(d: Dictionary) -> BankingHouse:
	var h: BankingHouse = BankingHouse.new()
	h.id                = StringName(String(d.get("id", "")))
	h.display_name      = String(d.get("display_name", ""))
	h.home_kingdom      = String(d.get("home_kingdom", ""))
	h.house_kind        = String(d.get("house_kind", ""))
	h.capacity          = int(d.get("capacity", 40))
	h.max_capacity      = int(d.get("max_capacity", 50))
	h.gold_capacity     = int(d.get("gold_capacity", 0))
	h.gold_max_capacity = int(d.get("gold_max_capacity", 0))
	h.monthly_regen_pct = int(d.get("monthly_regen_pct", 25))
	h.discretion        = int(d.get("discretion", 45))

	var r: Array = d.get("reach", [])
	h.reach = []
	for v in r:
		h.reach.append(String(v))
	if not h.reach.has(h.home_kingdom) and h.home_kingdom != "":
		h.reach.append(h.home_kingdom)

	h.maturity_months   = int(d.get("maturity_months", 0))
	h.curiosity         = int(d.get("curiosity", 0))
	h.overdraw_count    = int(d.get("overdraw_count", 0))
	h.compromised       = bool(d.get("compromised", false))
	h.dissolved         = bool(d.get("dissolved", false))
	h.dissolved_reason  = StringName(String(d.get("dissolved_reason", "")))
	return h


func to_dict() -> Dictionary:
	return {
		"id":                String(id),
		"display_name":      display_name,
		"home_kingdom":      home_kingdom,
		"house_kind":        house_kind,
		"capacity":          capacity,
		"max_capacity":      max_capacity,
		"gold_capacity":     gold_capacity,
		"gold_max_capacity": gold_max_capacity,
		"monthly_regen_pct": monthly_regen_pct,
		"discretion":        discretion,
		"reach":             reach.duplicate(),
		"maturity_months":   maturity_months,
		"curiosity":         curiosity,
		"overdraw_count":    overdraw_count,
		"compromised":       compromised,
		"dissolved":         dissolved,
		"dissolved_reason":  String(dissolved_reason),
	}
