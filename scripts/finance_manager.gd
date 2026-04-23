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
@warning_ignore("unused_signal")
signal house_dissolved(house: BankingHouse, reason: StringName)
signal iou_added(iou: Dictionary)
signal iou_settled(iou: Dictionary)
signal ledger_changed
signal retainer_registered(retainer: Dictionary)
signal retainer_at_risk(retainer: Dictionary, reason: StringName)
signal retainer_turned(retainer: Dictionary)
## A partial/multi-hop settlement finished clearing all its hops.
## Payload is the settlement dict. See `settle_partial`.
signal settlement_started(settlement: Dictionary)
signal settlement_completed(settlement: Dictionary)

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

# Gold is denser. One gold capacity point funds this much silver-equivalent.
# Ten-to-one vs silver matches the docs' bullion-value assumption.
const SILVER_PER_GOLD_CAPACITY: int = 200

# Cross-currency settlements add latency: gold has to be weighed,
# assayed, and counted against a silver book.
const CROSS_CURRENCY_DELAY_DAYS: int = 14


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

# Pending multi-hop settlements in flight. Each entry:
#   {
#     id: String,
#     dest_kingdom: String,
#     currency: StringName,
#     option: int (RoutingOption),
#     amount: int,
#     completed_abs_day: int,
#     hops: Array[Dictionary]   # [{ house_id, amount, capacity_cost, delay_days }, ...]
#     status: "pending"|"completed",
#   }
var pending_settlements: Array[Dictionary] = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seeded: bool = false


func _ready() -> void:
	_rng.randomize()
	GameClock.month_passed.connect(_on_month_passed)
	GameClock.day_passed.connect(_on_day_passed)
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
## `currency` is &"silver" (default) or &"gold" and selects which
## capacity pool is consumed; gold uses a denser per-capacity-unit
## conversion and adds a cross-currency latency bump.
func evaluate_route(dest_kingdom: String, silver_amount: int, option: int,
		currency: StringName = &"silver") -> Dictionary:
	if silver_amount <= 0:
		return { "ok": true, "house_id": "", "capacity_cost": 0,
				 "delay_days": 0, "curiosity_bump": 0, "exposure_bump": 0.0,
				 "currency": String(currency) }

	var per_cap: int = SILVER_PER_GOLD_CAPACITY if currency == &"gold" else SILVER_PER_CAPACITY
	var mult: float = float(ROUTE_CAPACITY_MULTIPLIER.get(option, 1.0))
	var base_cost: int = int(ceil(float(silver_amount) / float(per_cap)))
	var capacity_cost: int = maxi(1, int(ceil(float(base_cost) * mult)))

	# Embedded-in-trade requires a merchant host somewhere in our roster.
	# Without one, we can't hide money inside a legitimate shipment.
	if option == RoutingOption.EMBEDDED_TRADE and not _has_merchant_host():
		return { "ok": false, "reason": "no_merchant_host" }

	var best: BankingHouse = null
	var best_score: float = -INF
	for h in active_houses():
		if not h.reach.has(dest_kingdom):
			continue
		if h.capacity_for(currency) < capacity_cost:
			continue
		# Score: prefer higher discretion, lightly penalise using a
		# curious house for a discreet move.
		var score: float = float(h.effective_discretion())
		if option >= RoutingOption.MULTI_HOP and h.is_suspicious():
			score -= 20.0
		# Small preference for less-used houses: spread the load.
		score += float(h.capacity_for(currency) - capacity_cost) * 0.1
		if score > best_score:
			best_score = score
			best = h

	if best == null:
		return { "ok": false, "reason": "no_capacity", "currency": String(currency) }

	var delay: int = int(ROUTE_DELAY_DAYS.get(option, 1))
	if currency == &"gold":
		delay += CROSS_CURRENCY_DELAY_DAYS

	return {
		"ok":             true,
		"house_id":       String(best.id),
		"capacity_cost":  capacity_cost,
		"delay_days":     delay,
		"curiosity_bump": int(ROUTE_CURIOSITY_BUMP.get(option, 0)),
		"exposure_bump":  float(ROUTE_PLAYER_EXPOSURE_BUMP.get(option, 0.0)),
		"discretion_band": best.discretion_band_label(),
		"currency":       String(currency),
	}


## Actually commit a funded move. Consumes capacity, bumps curiosity,
## contributes the player-exposure tail for a DIRECT route, and emits
## house_updated. Returns the final route dict (same shape as
## `evaluate_route` on success), plus a `committed: true` flag.
##
## Callers are expected to have already checked `Purse.can_afford`
## fallback separately. This method does NOT deduct Purse silver.
func fund(dest_kingdom: String, silver_amount: int, option: int, reason: StringName = &"",
		currency: StringName = &"silver") -> Dictionary:
	var info: Dictionary = evaluate_route(dest_kingdom, silver_amount, option, currency)
	if not bool(info.get("ok", false)):
		return info

	if String(info.get("house_id", "")) == "":
		# Zero-silver transactions are a no-op.
		info["committed"] = true
		return info

	var h: BankingHouse = get_house(StringName(info["house_id"]))
	if h == null:
		return { "ok": false, "reason": "house_missing" }

	h.spend_capacity(currency, int(info["capacity_cost"]))
	h.curiosity = clampi(h.curiosity + int(info["curiosity_bump"]), 0, 100)

	var bump: float = float(info.get("exposure_bump", 0.0))
	if bump > 0.0:
		Exposure.bump(bump, "funded_" + String(reason) if reason != &"" else "funded_op")

	# Small overdraw risk: if we pushed a big chunk of remaining
	# capacity, the house notices the burst of activity.
	if int(info["capacity_cost"]) * 2 >= h.max_capacity_for(currency):
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
	var currency: StringName = StringName(String(route.get("currency", "silver")))
	h.refund_capacity(currency, int(route.get("capacity_cost", 0)))
	h.overdraw_count += 1
	if currency == &"gold":
		h.gold_max_capacity = maxi(0, h.gold_max_capacity - OVERDRAW_CAP_PENALTY)
	else:
		h.max_capacity = maxi(10, h.max_capacity - OVERDRAW_CAP_PENALTY)
	house_updated.emit(h)
	ledger_changed.emit()


## Hawala-style settlement. When no single house can carry the full
## amount, split it across N houses that reach `dest_kingdom`. Each
## hop consumes its own capacity, the total delay equals the slowest
## hop, and the total discretion cost is the sum of the curiosity
## bumps. Returns a settlement dict with `ok`, `id`, and `hops`.
func settle_partial(dest_kingdom: String, silver_amount: int, option: int,
		currency: StringName = &"silver", reason: StringName = &"") -> Dictionary:
	if silver_amount <= 0:
		return { "ok": true, "amount": 0, "hops": [] }

	var per_cap: int = SILVER_PER_GOLD_CAPACITY if currency == &"gold" else SILVER_PER_CAPACITY
	var mult: float = float(ROUTE_CAPACITY_MULTIPLIER.get(option, 1.0))

	# Rank houses that reach the destination by free capacity, desc.
	# Prefer higher discretion as a tiebreaker.
	var reachables: Array[BankingHouse] = []
	for h in active_houses():
		if not h.reach.has(dest_kingdom):
			continue
		if h.capacity_for(currency) <= 0:
			continue
		reachables.append(h)
	if reachables.is_empty():
		return { "ok": false, "reason": "no_capacity", "currency": String(currency) }
	reachables.sort_custom(func(a: BankingHouse, b: BankingHouse) -> bool:
		var ca: int = a.capacity_for(currency)
		var cb: int = b.capacity_for(currency)
		if ca != cb:
			return ca > cb
		return a.effective_discretion() > b.effective_discretion()
	)

	var remaining: int = silver_amount
	var hops: Array[Dictionary] = []
	var max_delay: int = int(ROUTE_DELAY_DAYS.get(option, 1))
	if currency == &"gold":
		max_delay += CROSS_CURRENCY_DELAY_DAYS
	var total_curiosity: int = 0
	var total_exposure: float = 0.0

	for h in reachables:
		if remaining <= 0:
			break
		# How much silver can this house carry at this option?
		var free: int = h.capacity_for(currency)
		var max_silver_here: int = int(float(free) / mult) * per_cap
		if max_silver_here <= 0:
			continue
		var hop_amount: int = mini(remaining, max_silver_here)
		var base_cost: int = int(ceil(float(hop_amount) / float(per_cap)))
		var cap_cost: int = maxi(1, int(ceil(float(base_cost) * mult)))
		if cap_cost > free:
			cap_cost = free
		h.spend_capacity(currency, cap_cost)
		var curiosity_bump: int = int(ROUTE_CURIOSITY_BUMP.get(option, 0))
		h.curiosity = clampi(h.curiosity + curiosity_bump, 0, 100)
		total_curiosity += curiosity_bump
		total_exposure += float(ROUTE_PLAYER_EXPOSURE_BUMP.get(option, 0.0))
		hops.append({
			"house_id":      String(h.id),
			"amount":        hop_amount,
			"capacity_cost": cap_cost,
			"delay_days":    max_delay,
		})
		house_updated.emit(h)
		remaining -= hop_amount

	if remaining > 0:
		# Roll back — we promised a full transfer and can't deliver.
		for hop in hops:
			var h2: BankingHouse = get_house(StringName(hop["house_id"]))
			if h2 != null:
				h2.refund_capacity(currency, int(hop["capacity_cost"]))
				house_updated.emit(h2)
		return { "ok": false, "reason": "no_capacity", "currency": String(currency) }

	if total_exposure > 0.0:
		Exposure.bump(total_exposure, "settled_" + String(reason) if reason != &"" else "settled")

	var settlement: Dictionary = {
		"id":                "settle_%d_%d" % [GameClock.absolute_day(), pending_settlements.size()],
		"dest_kingdom":      dest_kingdom,
		"currency":          String(currency),
		"option":             option,
		"amount":             silver_amount,
		"completed_abs_day":  GameClock.absolute_day() + max_delay,
		"hops":               hops,
		"status":             "pending",
		"curiosity_total":    total_curiosity,
		"exposure_total":     total_exposure,
	}
	pending_settlements.append(settlement)
	settlement_started.emit(settlement)
	ledger_changed.emit()
	return { "ok": true, "id": settlement["id"], "hops": hops,
			 "completed_abs_day": settlement["completed_abs_day"],
			 "currency": String(currency) }


func pending_settlements_for(dest_kingdom: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in pending_settlements:
		if String(s.get("status", "")) != "pending":
			continue
		if dest_kingdom != "" and String(s.get("dest_kingdom", "")) != dest_kingdom:
			continue
		out.append(s)
	return out


func _on_day_passed(_y: int, _m: int, _d: int) -> void:
	var today: int = GameClock.absolute_day()
	for s in pending_settlements:
		if String(s.get("status", "")) != "pending":
			continue
		if int(s.get("completed_abs_day", 0)) <= today:
			s["status"] = "completed"
			settlement_completed.emit(s)
	# Prune completed older than 60 days so the array doesn't grow
	# forever. Vault UI can keep its own persistent history if needed.
	var cutoff: int = today - 60
	pending_settlements = pending_settlements.filter(func(s: Dictionary) -> bool:
		return String(s.get("status", "")) == "pending" or int(s.get("completed_abs_day", 0)) > cutoff
	)


# --- Public: IOUs ---------------------------------------------------

func open_iou(debtor_kingdom: String, amount: int, months_until_due: int, creditor_house_id: StringName = &"") -> Dictionary:
	var due_y: int = GameClock.year
	var due_m: int = GameClock.month + months_until_due
	while due_m > 12:
		due_m -= 12
		due_y += 1
	var iou: Dictionary = {
		"id":                "iou_%d" % Time.get_ticks_msec(),
		"debtor_kingdom":    debtor_kingdom,
		"creditor_house_id": String(creditor_house_id),
		"amount":            amount,
		"opened_year":       GameClock.year,
		"opened_month":      GameClock.month,
		"due_year":          due_y,
		"due_month":         due_m,
		"status":            "open",
	}
	ious.append(iou)
	iou_added.emit(iou)
	ledger_changed.emit()
	# §B9: a loan held by a specific house grows the kingdom↔house
	# debt ledger. Anonymous IOUs (no creditor) are just paper the
	# player itself holds; they don't power bank-veto.
	if String(creditor_house_id) != "":
		InstRelations.bump_debt(debtor_kingdom, String(creditor_house_id), amount)
		InstRelations.bump_dependency(debtor_kingdom, String(creditor_house_id), 5)
	return iou


## Attempt to default on `iou_id`. Before we actually write the
## default, we ask §B9 whether the creditor bank can lean on the
## kingdom's treasury. If it can, the default is refused for this
## year and the ledger stays open; callers should read the return
## value and act accordingly.
##   returns "defaulted" | "vetoed" | "not_found"
func default_iou(iou_id: String) -> String:
	for i in range(ious.size()):
		if String(ious[i].get("id", "")) != iou_id:
			continue
		var iou: Dictionary = ious[i]
		if String(iou.get("status", "")) != "open":
			return "not_found"
		var house_id: String = String(iou.get("creditor_house_id", ""))
		var debtor: String = String(iou.get("debtor_kingdom", ""))
		var amount: int = int(iou.get("amount", 0))
		if house_id != "" and InstRelations.consume_bank_veto(debtor, house_id, amount):
			return "vetoed"
		ious[i]["status"] = "defaulted"
		if house_id != "":
			InstRelations.bump_debt(debtor, house_id, -amount)
			InstRelations.bump_trust(debtor, house_id, -20)
		ledger_changed.emit()
		return "defaulted"
	return "not_found"


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
			var house_id: String = String(ious[i].get("creditor_house_id", ""))
			var debtor: String = String(ious[i].get("debtor_kingdom", ""))
			var amount: int = int(ious[i].get("amount", 0))
			if house_id != "":
				InstRelations.bump_debt(debtor, house_id, -amount)
				InstRelations.bump_trust(debtor, house_id, 5)
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


## §28.1 one starter house. Anchored to the player's starting
## coordinator in Athens. §14.3 says the financial layer takes
## generations — two seeded houses was too rich. A single Athens
## consortium is the minimum viable network at genesis; additional
## houses come from `cultivate_financier` and the F3 beats.
func _seed_starter_houses() -> void:
	if WorldData.get_kingdom("athens") == null:
		return
	# Find the starter coordinator OrgMember (seeded by Org._seed_starter_cell).
	var coord: OrgMember = null
	if Org != null:
		for m in Org.all_members():
			if m.source_actor_id == &"starter_coordinator_athens":
				coord = m
				break
	var coord_name: String = coord.display_name if coord != null else "your predecessor's hand"
	var display: String = "The House of %s" % _house_surname(coord)
	_spawn_starter_house(
		"athens",
		display,
		"merchant consortium",
		[],
		(coord.id if coord != null else &""),
		"Inherited from your predecessor, carried into your hand by %s." % coord_name,
	)


func _spawn_starter_house(kid: String, display: String, kind: String,
		extra_reach: Array[String] = [],
		founded_by_id: StringName = &"",
		narrative: String = "") -> void:
	var h: BankingHouse = BankingHouse.new()
	h.id = StringName("house_%s_%d" % [kid, Time.get_ticks_msec() + _rng.randi_range(0, 999)])
	h.display_name = display
	h.home_kingdom = kid
	h.house_kind = kind
	h.capacity = 40
	h.max_capacity = 50
	h.monthly_regen_pct = 25
	h.discretion = 45
	# Bullion-oriented houses open with a small gold reserve; pure
	# merchant consortiums do not. Temple treasuries and silver-
	# weighers handle bullion day-one.
	if kind == "silver-weighers' guild" or kind == "temple treasury":
		h.gold_max_capacity = 12
		h.gold_capacity = 10
	h.reach = [kid]
	for other in extra_reach:
		if other != kid and not h.reach.has(other):
			h.reach.append(other)
	h.maturity_months = 0
	h.curiosity = 0
	h.founded_by_id = founded_by_id
	h.narrative = narrative
	houses[h.id] = h
	house_added.emit(h)


func _house_surname(coord) -> String:
	# Prefer the coordinator's real surname / cover for provenance.
	if coord != null and coord is OrgMember and not coord.display_name.is_empty():
		# Pull a short tag from the coordinator's display name ("Theron,
		# the scribe at the Kerameikos" → "Theron").
		var tag: String = coord.display_name.split(",", false, 1)[0]
		return tag
	# Fallback for corrupted saves.
	return "Kallistratos"


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
		# Gold regenerates at half the rate of silver — bullion moves slowly.
		if h.gold_max_capacity > 0:
			@warning_ignore("integer_division")
			var g_regen: int = int(float(h.gold_max_capacity) * float(h.monthly_regen_pct) / 200.0)
			h.gold_capacity = mini(h.gold_max_capacity, h.gold_capacity + maxi(1, g_regen))

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
		"houses":              hs,
		"ious":                ious.duplicate(true),
		"retainers":           retainers.duplicate(true),
		"seeded":              _seeded,
		"pending_settlements": pending_settlements.duplicate(true),
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
	pending_settlements.clear()
	for s in d.get("pending_settlements", []):
		if s is Dictionary:
			pending_settlements.append(s)
	ledger_changed.emit()
