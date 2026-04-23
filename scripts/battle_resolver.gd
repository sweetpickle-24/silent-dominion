extends Node
## Autoloaded as `Battles`. Resolves autonomous engagements between
## warring kingdoms (§9.1, §31.2).
##
## Every month each warring pair is rolled for a battle. Rolls are
## modulated by how long the war has run, how supplied the armies are,
## and a soft seasonality band (winter campaigns are rarer). When a
## battle fires:
##   * both sides take casualties and morale damage,
##   * the loser also loses supply and loyalty,
##   * the outcome is published as a public event,
##   * if one army is broken, the war ends in a dictated peace.
##
## Outcome skill blends size, quality, morale, supply, and a small RNG
## noise so no matchup is deterministic. Commanders are left as a hook
## for later — trait-weighted commander bonuses land when we wire
## commander appointments (§24 + §27).

signal battle_resolved(result: Dictionary)

# Base monthly probability a warring pair rolls a battle. Scales up
# with war duration so long wars feel grindingly active, not static.
const BATTLE_BASE_CHANCE:      float = 0.22
const BATTLE_PER_WAR_MONTH:    float = 0.015
const BATTLE_CHANCE_CAP:       float = 0.65

# Winter months in the classical campaign calendar. Lower the odds
# rather than forbid battles outright — rare winter campaigns happen.
const WINTER_MULTIPLIER: float = 0.35

# A side whose supply is threadbare skips the field.
const SUPPLY_SKIP_THRESHOLD: int = 18

# Casualty tuning. Winner losses are a fraction of loser losses; both
# scale with how decisive the result was.
const BASE_CASUALTY_RATE:        float = 0.12
const DECISIVE_MULTIPLIER:       float = 1.8
const WINNER_LOSS_RATIO:         float = 0.45

const MORALE_WIN_BUMP:   int = 8
const MORALE_LOSS_DROP:  int = 12
const MORALE_CRUSHED:    int = 22

const SUPPLY_BATTLE_DRAIN: int = 6
const LOYALTY_LOSS_DROP:   int = 3

const ROUT_FRACTION: float = 0.15   # size < ceiling * ROUT_FRACTION = crushed


var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	DevLogger.write("Battles: ready")
	_rng.randomize()
	GameClock.month_passed.connect(_on_month_passed)


# --- Monthly pass ------------------------------------------------------------

func _on_month_passed(_y: int, m: int) -> void:
	if not WorldData.is_loaded():
		return
	# Out-of-season attrition (§B7). Before we roll battles, every
	# warring kingdom whose home provinces are out of campaign season
	# takes a supply / morale hit — a classical winter stand-down in the
	# Northern / Temperate kingdoms, which is exactly what the climate
	# data is supposed to buy us.
	for k in WorldData.kingdoms.values():
		var km: Kingdom = k
		if km == null:
			continue
		var army: Army = Armies.get_army(km.id)
		if army == null or army.size <= 0:
			continue
		if _kingdom_in_campaign_season(km, m):
			continue
		army.supply = clampi(army.supply - 3, 0, 100)
		army.morale = clampi(army.morale - 1, 0, 100)

	var seen: Dictionary = {}
	for pair in Relations.warring_pairs():
		if pair.size() != 2:
			continue
		var a_id: String = String(pair[0])
		var b_id: String = String(pair[1])
		var key: String = _pair_key(a_id, b_id)
		if seen.has(key):
			continue
		seen[key] = true
		_maybe_fight(a_id, b_id, m)


func _maybe_fight(a_id: String, b_id: String, month: int) -> void:
	var army_a: Army = Armies.get_army(a_id)
	var army_b: Army = Armies.get_army(b_id)
	if army_a == null or army_b == null:
		return
	if army_a.size <= 0 or army_b.size <= 0:
		_resolve_forfeit_if_any(a_id, b_id, army_a, army_b)
		return
	if army_a.supply < SUPPLY_SKIP_THRESHOLD or army_b.supply < SUPPLY_SKIP_THRESHOLD:
		return

	var war_months: int = _war_months_for(a_id, b_id)
	var chance: float = clampf(
		BATTLE_BASE_CHANCE + BATTLE_PER_WAR_MONTH * float(maxi(0, war_months - 1)),
		0.0, BATTLE_CHANCE_CAP,
	)
	# Climate-driven seasonality. If either side is out of campaign
	# season in their own ground, the chance of a set-piece battle
	# collapses toward zero — the ancient pattern of waiting out
	# winter in camp instead of sending men into the snow.
	var k_a: Kingdom = WorldData.get_kingdom(a_id)
	var k_b: Kingdom = WorldData.get_kingdom(b_id)
	var a_in: bool = _kingdom_in_campaign_season(k_a, month)
	var b_in: bool = _kingdom_in_campaign_season(k_b, month)
	if not (a_in and b_in):
		chance *= WINTER_MULTIPLIER
	if _rng.randf() > chance:
		return

	_resolve_battle(a_id, b_id, army_a, army_b)


## True if *any* province owned by the kingdom is currently in campaign
## season. Empty / unknown kingdoms are treated as permanently in season
## so we don't accidentally freeze a simulation on bad data.
func _kingdom_in_campaign_season(k: Kingdom, month: int) -> bool:
	if k == null:
		return true
	for pid in k.owned_provinces:
		var p: Province = WorldData.get_province(pid)
		if p == null:
			continue
		if p.campaign_season(month):
			return true
	return false


# --- Resolution --------------------------------------------------------------

func _resolve_battle(a_id: String, b_id: String, army_a: Army, army_b: Army) -> void:
	var score_a: float = _battle_score(army_a)
	var score_b: float = _battle_score(army_b)
	score_a *= _rng.randf_range(0.85, 1.15)
	score_b *= _rng.randf_range(0.85, 1.15)

	var winner_id: String
	var winner: Army
	var loser_id: String
	var loser: Army
	var margin: float
	if score_a >= score_b:
		winner_id = a_id; winner = army_a
		loser_id  = b_id; loser  = army_b
		margin = score_a / maxf(0.1, score_b)
	else:
		winner_id = b_id; winner = army_b
		loser_id  = a_id; loser  = army_a
		margin = score_b / maxf(0.1, score_a)

	var decisive: bool = margin >= 1.6

	# Casualties.
	var loser_loss_rate: float = BASE_CASUALTY_RATE * (DECISIVE_MULTIPLIER if decisive else 1.0)
	var loser_loss: int = maxi(1, int(round(float(loser.size) * loser_loss_rate)))
	var winner_loss: int = maxi(1, int(round(float(loser_loss) * WINNER_LOSS_RATIO)))
	loser.size  = maxi(0, loser.size - loser_loss)
	winner.size = maxi(0, winner.size - winner_loss)

	# Morale / supply / loyalty.
	winner.morale = clampi(winner.morale + MORALE_WIN_BUMP, 0, 100)
	var loser_morale_drop: int = MORALE_CRUSHED if decisive else MORALE_LOSS_DROP
	loser.morale = clampi(loser.morale - loser_morale_drop, 0, 100)

	@warning_ignore("integer_division")
	var winner_supply_drain: int = SUPPLY_BATTLE_DRAIN / 2
	winner.supply = clampi(winner.supply - winner_supply_drain, 0, 100)
	loser.supply  = clampi(loser.supply  - SUPPLY_BATTLE_DRAIN, 0, 100)
	loser.loyalty = clampi(loser.loyalty - LOYALTY_LOSS_DROP, 0, 100)

	# Publish and broadcast.
	_publish_battle(winner_id, loser_id, winner_loss, loser_loss, decisive)
	var result: Dictionary = {
		"winner":       winner_id,
		"loser":        loser_id,
		"winner_loss":  winner_loss,
		"loser_loss":   loser_loss,
		"decisive":     decisive,
	}
	battle_resolved.emit(result)

	# Routs end the war — a crown without an army in the field sues.
	if _is_crushed(loser) or _is_crushed(winner):
		_end_war_by_rout(winner_id, loser_id)


func _battle_score(a: Army) -> float:
	# Size is the dominant term, but quality/morale/supply all chip in.
	var size_f: float    = maxf(0.0, float(a.size))
	var quality_f: float = clampf(float(a.quality) / 60.0, 0.25, 1.75)
	var morale_f: float  = clampf(float(a.morale)  / 60.0, 0.30, 1.70)
	var supply_f: float  = clampf(float(a.supply)  / 60.0, 0.40, 1.40)
	var loyalty_f: float = clampf(float(a.loyalty) / 60.0, 0.50, 1.30)
	return size_f * quality_f * morale_f * supply_f * loyalty_f


func _is_crushed(a: Army) -> bool:
	if a.size <= 0:
		return true
	if a.size_ceiling <= 0:
		return a.size < 2
	return float(a.size) / float(a.size_ceiling) < ROUT_FRACTION


func _resolve_forfeit_if_any(a_id: String, b_id: String, army_a: Army, army_b: Army) -> void:
	# One side already has no field force — the other side wins by default.
	if army_a.size > 0 and army_b.size <= 0:
		_end_war_by_rout(a_id, b_id)
	elif army_b.size > 0 and army_a.size <= 0:
		_end_war_by_rout(b_id, a_id)


func _end_war_by_rout(winner_id: String, loser_id: String) -> void:
	var winner_k: Kingdom = WorldData.get_kingdom(winner_id)
	var loser_k: Kingdom  = WorldData.get_kingdom(loser_id)
	if winner_k == null or loser_k == null:
		return
	Relations.set_peace(winner_id, loser_id)
	EventBus.public_event.emit({
		"kind":       &"war_outcome",
		"kingdom_id": winner_id,
		"headline":   "%s ends the war with %s" % [winner_k.kingdom_name, loser_k.kingdom_name],
		"body":       "Word from the frontier: %s has carried the field against %s. The standards of %s are no longer over a fighting army, only a camp. Terms have been dictated — the details, as always, matter less than the shape of them." % [
			winner_k.kingdom_name, loser_k.kingdom_name, loser_k.kingdom_name,
		],
	})


func _publish_battle(winner_id: String, loser_id: String, winner_loss: int, loser_loss: int, decisive: bool) -> void:
	var w: Kingdom = WorldData.get_kingdom(winner_id)
	var l: Kingdom = WorldData.get_kingdom(loser_id)
	if w == null or l == null:
		return
	var headline: String
	var body: String
	if decisive:
		headline = "%s routs %s in the field" % [w.kingdom_name, l.kingdom_name]
		body = "A pitched battle on the %s frontier. The lines of %s broke before the afternoon and did not re-form. The loser's army is a day of bad news from a rout; the winner's has taken the day cheaply." % [
			w.kingdom_name, l.kingdom_name,
		]
	else:
		headline = "A bloody field between %s and %s" % [w.kingdom_name, l.kingdom_name]
		body = "The armies of %s and %s met this month. The day went to %s, but only just. The dead are counted on both sides; the living will need the winter to forget." % [
			w.kingdom_name, l.kingdom_name, w.kingdom_name,
		]
	EventBus.public_event.emit({
		"kind":       &"battle",
		"kingdom_id": w.id,
		"headline":   headline,
		"body":       body,
		"winner":     winner_id,
		"loser":      loser_id,
		"winner_loss": winner_loss,
		"loser_loss":  loser_loss,
		"decisive":    decisive,
	})


# --- Helpers -----------------------------------------------------------------

func _pair_key(a_id: String, b_id: String) -> String:
	if a_id < b_id:
		return "%s|%s" % [a_id, b_id]
	return "%s|%s" % [b_id, a_id]


func _war_months_for(a_id: String, b_id: String) -> int:
	return Relations.war_months_between(a_id, b_id)
