extends Node
## Autoloaded as `Finance`. The player's financial network (§16).
##
## The player has no gold balance. They have *access* — banking houses,
## merchant consortiums, temple treasuries that can produce silver in
## specific cities when asked. Every act of funding routes through
## those relationships; there is no single number that drains.
##
## The legacy `Purse` still exists. It represents the player's own
## emergency coin (a trunk under a floorboard) and is used as a small
## last-resort reserve. Large, routable operations prefer the network.
##
## This registry owns:
##   - The dictionary of BankingHouses and their state.
##   - Seeding at new-game time.
##   - The routing algorithm that picks the cheapest viable path.
##   - The monthly tick (capacity regen, maturity growth, curiosity decay).
##   - Save/load hooks.

signal house_added(house: BankingHouse)
signal house_updated(house: BankingHouse)
signal house_dissolved(house: BankingHouse, reason: StringName)
signal iou_added(iou: Dictionary)
signal iou_settled(iou: Dictionary)
signal ledger_changed
signal retainer_registered(retainer: Dictionary)
signal retainer_at_risk(retainer: Dictionary, reason: StringName)
signal retainer_turned(retainer: Dictionary)

# --- Routing options (§16.3) -----------------------------------------

enum RoutingOption {
	DIRECT,               # Fastest. Highest source exposure.
	SINGLE_INTERMEDIARY,  # Moderate cost, moderate discretion.
	MULTI_HOP,            # Expensive in capacity, high discretion, slow.
	EMBEDDED_TRADE,       # Best discretion. Requires merchant host. Slowest.
}

const ROUTE_LABELS: Dictionary = {
	RoutingOption.DIRECT:              "Direct payment",
	RoutingOption.SINGLE_INTERMEDIARY: "Single intermediary",
	RoutingOption.MULTI_HOP:           "Multi-hop laundering",
	RoutingOption.EMBEDDED_TRADE:      "Embedded in trade",
}

# Per-option tuning. Values chosen so DIRECT is a clear "cheap and fast
# but loud" choice and EMBEDDED_TRADE a "expensive and slow but safe".
# All integers; nothing continuous.
const ROUTE_CAPACITY_MULTIPLIER: Dictionary = {
	RoutingOption.DIRECT:              1.0,
	RoutingOption.SINGLE_INTERMEDIARY: 1.3,
	RoutingOption.MULTI_HOP:           1.8,
	RoutingOption.EMBEDDED_TRADE:      1.5,
}

const ROUTE_DELAY_DAYS: Dictionary = {
	RoutingOption.DIRECT:              1,
	RoutingOption.SINGLE_INTERMEDIARY: 8,
	RoutingOption.MULTI_HOP:           22,
	RoutingOption.EMBEDDED_TRADE:      35,
}

const ROUTE_CURIOSITY_BUMP: Dictionary = {
	RoutingOption.DIRECT:              6,
	RoutingOption.SINGLE_INTERMEDIARY: 3,
	RoutingOption.MULTI_HOP:           1,
	RoutingOption.EMBEDDED_TRADE:      0,
}

const ROUTE_PLAYER_EXPOSURE_BUMP: Dictionary = {
	RoutingOption.DIRECT:              1.2,
	RoutingOption.SINGLE_INTERMEDIARY: 0.6,
	RoutingOption.MULTI_HOP:           0.2,
	RoutingOption.EMBEDDED_TRADE:      0.0,
}

# --- Tuning ----------------------------------------------------------

const CURIOSITY_DECAY_PER_MONTH: int = 1
const MATURITY_MONTHS_FOR_GROWTH: int = 12
const MAX_CAP_GROWTH_PER_YEAR: int = 4
const DISCRETION_GROWTH_PER_YEAR: int = 2
const DISCRETION_HARD_CAP: int = 90
const MAX_CAP_HARD_CAP: int = 100
const OVERDRAW_CAP_PENALTY: int = 4   # max_capacity loss per overdraw

# Silver capacity-unit. One "capacity point" funds this much silver.
# Chosen so a starter house (capacity ~40) can bankroll ~800 silver
# of operations before needing to rest.
const SILVER_PER_CAPACITY: int = 20


# --- State -----------------------------------------------------------

# id (StringName) -> BankingHouse
var houses: Dictionary = {}

# Simple IOU log (§16 debt instrument). Each entry is a dict:
#   { id, debtor_kingdom, amount, opened_year, opened_month,
#     due_year, due_month, status: "open"|"paid"|"defaulted" }
var ious: Array[Dictionary] = []

# Retainer dependents (§17.5). Each entry:
#   { actor_id, monthly_cost, opened_year, opened_month,
#     missed_months, status: "active"|"at_risk"|"turned"|"retired" }
var retainers: Array[Dictionary] = []

# How many consecutive missed monthly payments before the dependent
# turns against us. Tuned so one bad season doesn't lose them.
const RETAINER_MISS_LIMIT: int = 3

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seeded: bool = false


func _ready() -> void:
	_rng.randomize()
	GameClock.month_passed.connect(_on_month_passed)
	# Seed once the world has finished loading — we want kingdom ids
	# to exist before we assign home_kingdoms.
	if WorldData.is_loaded():
		_maybe_seed()
	else:
		WorldData.world_loaded.connect(_maybe_seed, CONNECT_ONE_SHOT)
	print("[Finance] Ready.")


# --- Public: queries -------------------------------------------------

func all_houses() -> Array[BankingHouse]:
	var out: Array[BankingHouse] = []
	for h in houses.values():
		out.append(h)
	return out


func active_houses() -> Array[BankingHouse]:
	var out: Array[BankingHouse] = []
	for h in houses.values():
		if h.is_usable():
			out.append(h)
	return out


func get_house(id: StringName) -> BankingHouse:
	return houses.get(id, null)


## Evaluate a funding request: walk active houses, find any that can
## reach `dest_kingdom` and absorb `silver_amount` via `option`, pick
## the one with best (discretion, remaining capacity) tradeoff.
## Returns { "house_id", "capacity_cost", "delay_days",
##          "curiosity_bump", "exposure_bump", "ok" }.
## When nothing can cover it, returns { "ok": false, "reason": <string> }.
func evaluate_route(dest_kingdom: String, silver_amount: int, option: int) -> Dictionary:
	if silver_amount <= 0:
		return { "ok": true, "house_id": "", "capacity_cost": 0,
				 "delay_days": 0, "curiosity_bump": 0, "exposure_bump": 0.0 }

	var mult: float = float(ROUTE_CAPACITY_MULTIPLIER.get(option, 1.0))
	var base_cost: int = int(ceil(float(silver_amount) / float(SILVER_PER_CAPACITY)))
	var capacity_cost: int = int(ceil(float(base_cost) * mult))

	# Embedded-in-trade requires a merchant host somewhere in our roster.
	# Without one, we can't hide money inside a legitimate shipment.
	if option == RoutingOption.EMBEDDED_TRADE and not _has_merchant_host():
		return { "ok": false, "reason": "no_merchant_host" }

	var best: BankingHouse = null
	var best_score: float = -INF
	for h in active_houses():
		if not h.reach.has(dest_kingdom):
			continue
		if h.capacity < capacity_cost:
			continue
		# Score: prefer higher discretion, lightly penalise using a
		# curious house for a discreet move.
		var score: float = float(h.effective_discretion())
		if option >= RoutingOption.MULTI_HOP and h.is_suspicious():
			score -= 20.0
		# Small preference for less-used houses: spread the load.
		score += float(h.capacity - capacity_cost) * 0.1
		if score > best_score:
			best_score = score
			best = h

	if best == null:
		return { "ok": false, "reason": "no_capacity" }

	return {
		"ok":             true,
		"house_id":       String(best.id),
		"capacity_cost":  capacity_cost,
		"delay_days":     int(ROUTE_DELAY_DAYS.get(option, 1)),
		"curiosity_bump": int(ROUTE_CURIOSITY_BUMP.get(option, 0)),
		"exposure_bump":  float(ROUTE_PLAYER_EXPOSURE_BUMP.get(option, 0.0)),
		"discretion_band": best.discretion_band_label(),
	}


## Actually commit a funded move. Consumes capacity, bumps curiosity,
## contributes the player-exposure tail for a DIRECT route, and emits
## house_updated. Returns the final route dict (same shape as
## `evaluate_route` on success), plus a `committed: true` flag.
##
## Callers are expected to have already checked `Purse.can_afford`
## fallback separately. This method does NOT deduct Purse silver.
func fund(dest_kingdom: String, silver_amount: int, option: int, reason: StringName = &"") -> Dictionary:
	var info: Dictionary = evaluate_route(dest_kingdom, silver_amount, option)
	if not bool(info.get("ok", false)):
		return info

	if String(info.get("house_id", "")) == "":
		# Zero-silver transactions are a no-op.
		info["committed"] = true
		return info

	var h: BankingHouse = get_house(StringName(info["house_id"]))
	if h == null:
		return { "ok": false, "reason": "house_missing" }

	h.capacity = maxi(0, h.capacity - int(info["capacity_cost"]))
	h.curiosity = clampi(h.curiosity + int(info["curiosity_bump"]), 0, 100)

	var bump: float = float(info.get("exposure_bump", 0.0))
	if bump > 0.0:
		Exposure.bump(bump, "funded_" + String(reason) if reason != &"" else "funded_op")

	# Small overdraw risk: if we pushed a big chunk of remaining
	# capacity, the house notices the burst of activity.
	if int(info["capacity_cost"]) * 2 >= h.max_capacity:
		h.curiosity = clampi(h.curiosity + 4, 0, 100)

	# Suspicion crossing point — fire once.
	if h.is_suspicious() and h.discretion > 0:
		h.discretion = maxi(10, h.discretion - 2)

	house_updated.emit(h)
	ledger_changed.emit()
	info["committed"] = true
	info["_route_option"] = option
	return info


## Cancel / refund a route that the simulation decided not to take.
## Restores capacity but leaves curiosity alone — the house was still
## asked. Call with the dict returned by `fund`.
func refund(route: Dictionary) -> void:
	if String(route.get("house_id", "")) == "":
		return
	var h: BankingHouse = get_house(StringName(route["house_id"]))
	if h == null:
		return
	h.capacity = mini(h.max_capacity, h.capacity + int(route.get("capacity_cost", 0)))
	h.overdraw_count += 1
	h.max_capacity = maxi(10, h.max_capacity - OVERDRAW_CAP_PENALTY)
	house_updated.emit(h)
	ledger_changed.emit()


# --- Public: IOUs ---------------------------------------------------

func open_iou(debtor_kingdom: String, amount: int, months_until_due: int) -> Dictionary:
	var due_y: int = GameClock.year
	var due_m: int = GameClock.month + months_until_due
	while due_m > 12:
		due_m -= 12
		due_y += 1
	var iou: Dictionary = {
		"id":              "iou_%d" % Time.get_ticks_msec(),
		"debtor_kingdom":  debtor_kingdom,
		"amount":          amount,
		"opened_year":     GameClock.year,
		"opened_month":    GameClock.month,
		"due_year":        due_y,
		"due_month":       due_m,
		"status":          "open",
	}
	ious.append(iou)
	iou_added.emit(iou)
	ledger_changed.emit()
	return iou


func open_ious() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in ious:
		if String(d.get("status", "")) == "open":
			out.append(d)
	return out


func settle_iou(iou_id: String) -> bool:
	for i in range(ious.size()):
		if String(ious[i].get("id", "")) == iou_id:
			ious[i]["status"] = "paid"
			iou_settled.emit(ious[i])
			ledger_changed.emit()
			return true
	return false


# --- Public: retainer dependents (§17.5) -----------------------------

## Register a new ongoing-payment dependent. Called by a successful
## `bribe_retainer` resolution. Returns the entry for reference.
func register_retainer(actor_id: StringName, monthly_cost: int) -> Dictionary:
	for r in retainers:
		if String(r.get("actor_id", "")) == String(actor_id) \
				and String(r.get("status", "")) != "turned" \
				and String(r.get("status", "")) != "retired":
			# Already on our books — refresh the amount.
			r["monthly_cost"] = monthly_cost
			return r
	var entry: Dictionary = {
		"actor_id":     String(actor_id),
		"monthly_cost": monthly_cost,
		"opened_year":  GameClock.year,
		"opened_month": GameClock.month,
		"missed_months": 0,
		"status":       "active",
	}
	retainers.append(entry)
	retainer_registered.emit(entry)
	ledger_changed.emit()
	return entry


func active_retainers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in retainers:
		if String(r.get("status", "active")) == "active":
			out.append(r)
	return out


## Retire a dependent cleanly — they feel the work naturally ended.
## No turn risk from this path.
func retire_retainer(actor_id: StringName) -> bool:
	for r in retainers:
		if String(r.get("actor_id", "")) == String(actor_id) \
				and String(r.get("status", "")) == "active":
			r["status"] = "retired"
			ledger_changed.emit()
			return true
	return false


# --- Internal: seeding ----------------------------------------------

func _maybe_seed() -> void:
	if _seeded:
		return
	if not houses.is_empty():
		_seeded = true
		return
	_seed_starter_houses()
	_seeded = true


## Two starter houses. Chosen in the most plausible classical
## commercial centres for 500 BCE: a merchant consortium in Athens
## and a Phoenician-facing house in Carthage. If those kingdoms
## don't exist in the current world file, fall back to the first
## two kingdoms we find. This is not a campaign hook — it's the
## minimum viable financial network at genesis.
func _seed_starter_houses() -> void:
	var preferred: Array[String] = ["athens", "carthage", "corinth", "syracuse"]
	var chosen: Array[String] = []
	for kid in preferred:
		if WorldData.get_kingdom(kid) != null and chosen.size() < 2:
			chosen.append(kid)
	if chosen.size() < 2:
		for k in WorldData.kingdoms.keys():
			if chosen.has(String(k)):
				continue
			chosen.append(String(k))
			if chosen.size() >= 2:
				break

	if chosen.size() >= 1:
		var extra_a: Array[String] = [chosen[1]] if chosen.size() >= 2 else []
		_spawn_starter_house(chosen[0], "The House of %s" % _house_surname(chosen[0]),
			"merchant consortium", extra_a)
	if chosen.size() >= 2:
		var extra_b: Array[String] = [chosen[0]]
		_spawn_starter_house(chosen[1], "The Brothers of %s" % _house_surname(chosen[1]),
			"silver-weighers' guild", extra_b)


func _spawn_starter_house(kid: String, display: String, kind: String, extra_reach: Array[String] = []) -> void:
	var h: BankingHouse = BankingHouse.new()
	h.id = StringName("house_%s_%d" % [kid, Time.get_ticks_msec() + _rng.randi_range(0, 999)])
	h.display_name = display
	h.home_kingdom = kid
	h.house_kind = kind
	h.capacity = 40
	h.max_capacity = 50
	h.monthly_regen_pct = 25
	h.discretion = 45
	h.reach = [kid]
	# Every commercial house of standing has a partner across the sea.
	# Give the starter pair mutual coverage so the player can fund work
	# in either home from day one.
	for other in extra_reach:
		if other != kid and not h.reach.has(other):
			h.reach.append(other)
	h.maturity_months = 0
	h.curiosity = 0
	houses[h.id] = h
	house_added.emit(h)


func _house_surname(kid: String) -> String:
	match kid:
		"athens":    return "Kallistratos"
		"carthage":  return "Gisco"
		"corinth":   return "Timoleon"
		"syracuse":  return "Dionysios"
	var k: Kingdom = WorldData.get_kingdom(kid)
	return k.kingdom_name if k != null else kid.capitalize()


func _has_merchant_host() -> bool:
	for a in Actors.hosts():
		if a.role == Actor.Role.MERCHANT:
			return true
	return false


# --- Monthly tick ----------------------------------------------------

func _on_month_passed(_y: int, _m: int) -> void:
	for h in houses.values():
		if h.dissolved:
			continue
		if h.compromised:
			# A compromised house still runs; it just bleeds intel.
			# No capacity regen — the rival is milking it.
			continue

		# Capacity regen, in integer steps.
		var regen: int = int(float(h.max_capacity) * float(h.monthly_regen_pct) / 100.0)
		h.capacity = mini(h.max_capacity, h.capacity + maxi(1, regen))

		# Curiosity decays if not pushed this month.
		h.curiosity = maxi(0, h.curiosity - CURIOSITY_DECAY_PER_MONTH)

		# Maturity growth.
		h.maturity_months += 1
		if h.maturity_months % MATURITY_MONTHS_FOR_GROWTH == 0:
			h.max_capacity = mini(MAX_CAP_HARD_CAP, h.max_capacity + MAX_CAP_GROWTH_PER_YEAR)
			h.discretion   = mini(DISCRETION_HARD_CAP, h.discretion + DISCRETION_GROWTH_PER_YEAR)

		house_updated.emit(h)

	_pay_retainers()
	ledger_changed.emit()


## Service every active retainer. Each month their fee must move —
## via the bank network first, the purse second. Misses accumulate;
## after RETAINER_MISS_LIMIT missed months the dependent turns, which
## spills an intelligence leak (handled in action_runner when it
## receives the signal).
func _pay_retainers() -> void:
	for r in retainers:
		if String(r.get("status", "")) != "active":
			continue
		var amount: int = int(r.get("monthly_cost", 0))
		if amount <= 0:
			continue

		var paid: bool = false
		var actor_id: String = String(r.get("actor_id", ""))
		var a: Actor = Actors.get_actor(StringName(actor_id))
		var dest_kingdom: String = a.kingdom_id if a != null else ""

		if dest_kingdom != "":
			var route: Dictionary = fund(dest_kingdom, amount,
				RoutingOption.SINGLE_INTERMEDIARY, &"retainer")
			paid = bool(route.get("ok", false))
		if not paid and Purse.can_afford(amount):
			Purse.spend(amount)
			paid = true

		if paid:
			r["missed_months"] = 0
			continue

		r["missed_months"] = int(r.get("missed_months", 0)) + 1
		if int(r["missed_months"]) >= RETAINER_MISS_LIMIT:
			r["status"] = "turned"
			retainer_turned.emit(r)
		else:
			retainer_at_risk.emit(r, &"missed_payment")


# --- Save / load -----------------------------------------------------

func snapshot() -> Dictionary:
	var hs: Array = []
	for h in houses.values():
		hs.append(h.to_dict())
	return {
		"houses":    hs,
		"ious":      ious.duplicate(true),
		"retainers": retainers.duplicate(true),
		"seeded":    _seeded,
	}


func restore(d: Dictionary) -> void:
	houses.clear()
	ious.clear()
	retainers.clear()
	_seeded = bool(d.get("seeded", false))
	for hd in d.get("houses", []):
		if not (hd is Dictionary):
			continue
		var h: BankingHouse = BankingHouse.from_dict(hd)
		houses[h.id] = h
	for iou_d in d.get("ious", []):
		if iou_d is Dictionary:
			ious.append(iou_d)
	for r in d.get("retainers", []):
		if r is Dictionary:
			retainers.append(r)
	ledger_changed.emit()
