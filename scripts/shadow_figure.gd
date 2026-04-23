extends Node
## Autoloaded as `Shadow`. The player's legend per §10.
##
## Tracks three pieces of state:
##   - A global `legend` score, 0-100, accumulated from exposure and
##     from loud public actions. Drives the era-appropriate epithet.
##   - Per-kingdom `awareness` tier 0-3 (none / cultural / institutional /
##     personal). Rises with local activity, decays slowly.
##   - A small roster of `hunters` — actors who have made catching the
##     shadow figure their life's work. Emerge from high-paranoia,
##     high-intellect populations in high-awareness kingdoms.
##
## Other systems read from here:
##   - Exposure tail multipliers in high-awareness kingdoms (future).
##   - Hunter presence generates a small monthly exposure trickle.
##   - UI shows the legend gauge + per-kingdom awareness + the
##     era-appropriate epithet.

signal legend_changed(value: int)
signal awareness_changed(kingdom_id: String, tier: int)
signal hunter_emerged(hunter: Dictionary)
signal hunter_resolved(actor_id: String)

const TIER_NONE: int           = 0
const TIER_CULTURAL: int       = 1
const TIER_INSTITUTIONAL: int  = 2
const TIER_PERSONAL: int       = 3

# Awareness thresholds expressed in the hidden "heat" score each
# kingdom accumulates. We tier from heat: 0 / 25 / 55 / 85+.
const TIER_THRESHOLDS: Array[int] = [0, 25, 55, 85]

var legend: int = 0
var awareness_heat: Dictionary = {}  # String kingdom_id -> int 0..100
# hunter_id (String actor_id) -> Dictionary {actor_id, kingdom_id, intensity}
var hunters: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	EventBus.public_event.connect(_on_public_event)
	EventBus.action_resolved.connect(_on_action_resolved)
	GameClock.month_passed.connect(_on_month_passed)


# --- Public: queries ------------------------------------------------------

func awareness_tier_in(kingdom_id: String) -> int:
	var heat: int = int(awareness_heat.get(kingdom_id, 0))
	for i in range(TIER_THRESHOLDS.size() - 1, -1, -1):
		if heat >= TIER_THRESHOLDS[i]:
			return i
	return TIER_NONE


func awareness_heat_in(kingdom_id: String) -> int:
	return int(awareness_heat.get(kingdom_id, 0))


## The current era-appropriate epithet for the shadow figure. The era
## is inferred from the game clock's year since a dedicated Eras
## module will land in Phase 6. For now we map by year bucket.
func epithet() -> String:
	if legend < 15:
		return ""  # not yet named
	var year: int = GameClock.year
	# Classical → Late Antique → Early Medieval → High Medieval → Renaissance → Early Modern → Modern
	if year < -100:
		return "the Daimon of the Quarter"
	if year < 300:
		return "the Unseen Hand"
	if year < 800:
		return "the Shadow at the Council"
	if year < 1300:
		return "the Hidden Prince"
	if year < 1600:
		return "the Hierophant in Absence"
	if year < 1800:
		return "the Sovereign Nobody Names"
	return "the Conspirator-Who-Has-No-Name"


func is_hunter(actor_id: String) -> bool:
	return hunters.has(actor_id)


func hunters_in(kingdom_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h in hunters.values():
		if String(h.get("kingdom_id", "")) == kingdom_id:
			out.append(h)
	return out


func all_hunters() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h in hunters.values():
		out.append(h)
	return out


# --- Public: mutators -----------------------------------------------------

func add_legend(amount: int, _reason: String = "") -> void:
	if amount == 0:
		return
	legend = clampi(legend + amount, 0, 100)
	legend_changed.emit(legend)


## Lift awareness heat in a kingdom. Reasons exist to help future
## callers profile what drives legend most cheaply.
func bump_awareness(kingdom_id: String, amount: int, _reason: String = "") -> void:
	if kingdom_id.is_empty() or amount == 0:
		return
	var prev_tier: int = awareness_tier_in(kingdom_id)
	var heat: int = awareness_heat_in(kingdom_id)
	awareness_heat[kingdom_id] = clampi(heat + amount, 0, 100)
	var next_tier: int = awareness_tier_in(kingdom_id)
	if next_tier != prev_tier:
		awareness_changed.emit(kingdom_id, next_tier)


func quiet_in(kingdom_id: String, amount: int) -> void:
	if kingdom_id.is_empty() or amount <= 0:
		return
	var prev_tier: int = awareness_tier_in(kingdom_id)
	var heat: int = awareness_heat_in(kingdom_id)
	awareness_heat[kingdom_id] = maxi(0, heat - amount)
	var next_tier: int = awareness_tier_in(kingdom_id)
	if next_tier != prev_tier:
		awareness_changed.emit(kingdom_id, next_tier)


## Remove a hunter completely (discredited, redirected, or dead).
## Does a small legend and awareness bump because the act is public.
## §B16: historian hunters cannot be resolved this way — they are
## cross-generational archival pursuers. Use `resolve_historian` or
## `destroy_archive_for_historian` for them.
func resolve_hunter(actor_id: String, loud: bool = false) -> bool:
	if not hunters.has(actor_id):
		return false
	var h: Dictionary = hunters[actor_id]
	if bool(h.get("historian", false)):
		# Historians shrug off discredit and quiet-the-legend. An
		# archive does not care what its subject is called.
		return false
	hunters.erase(actor_id)
	hunter_resolved.emit(actor_id)
	if loud:
		bump_awareness(String(h.get("kingdom_id", "")), 8, "hunter_resolved_loud")
		add_legend(2, "hunter_resolved_loud")
	return true


## §B16 Destroy the archive that sustains a specific historian. The
## historian evaporates; the kingdom's institutional memory takes a
## hit (awareness drops) but the loss of the archive is itself loud.
func destroy_archive_for_historian(hunter_actor_id: String) -> bool:
	if not hunters.has(hunter_actor_id):
		return false
	var h: Dictionary = hunters[hunter_actor_id]
	if not bool(h.get("historian", false)):
		return false
	var kid: String = String(h.get("kingdom_id", ""))
	hunters.erase(hunter_actor_id)
	hunter_resolved.emit(hunter_actor_id)
	# Quieter than an arrest, louder than a discreet discredit.
	quiet_in(kid, 12)
	add_legend(3, "archive_destroyed")
	return true


## §B16 Return true when at least one active hunter on `kingdom_id`
## is a historian. Callers use this to gate archive-destruction UI.
func has_historian_in(kingdom_id: String) -> bool:
	for h in hunters.values():
		if String(h.get("kingdom_id", "")) == kingdom_id and bool(h.get("historian", false)):
			return true
	return false


## §B16 First historian actor id in `kingdom_id`, or "" if none.
func first_historian_in(kingdom_id: String) -> String:
	for h in hunters.values():
		if String(h.get("kingdom_id", "")) == kingdom_id and bool(h.get("historian", false)):
			return String(h.get("actor_id", ""))
	return ""


# --- Event hooks ----------------------------------------------------------

## World-sim events that are not the player's fingerprint. Battles,
## treasury swings, famines, and the like happen whether the player
## exists or not; they must not raise the legend score.
const SKIP_KINDS: Array[StringName] = [
	&"battle", &"war_outcome", &"war_weariness", &"peace_declaration",
	&"tax_change", &"fiscal_crisis", &"fiscal_recovery",
	&"plague", &"famine", &"earthquake", &"portent", &"recovery",
	&"army_shift", &"population_collapse", &"population_boom",
]


func _on_public_event(event: Dictionary) -> void:
	# Ignore rival-authored events. Their signatures are someone
	# else's legend, not the player's.
	if event.has("rival_signature"):
		return
	var kid: String = String(event.get("kingdom_id", ""))
	if kid.is_empty():
		return
	var kind: StringName = StringName(String(event.get("kind", "")))
	if SKIP_KINDS.has(kind):
		return
	var weight: int = 0
	match kind:
		&"rumour":        weight = 3
		&"unrest":        weight = 5
		&"war":           weight = 4
		&"ruler_decree":  weight = 2
		&"dynasty":       weight = 2
		&"religion":      weight = 3
		_:                weight = 1
	bump_awareness(kid, weight, "public_event")
	# Global legend rises more slowly — about one point per loud action.
	add_legend(1 if weight >= 3 else 0, "public_event")


func _on_action_resolved(_action_id: StringName, result: Dictionary) -> void:
	# A failed high-tier action is loud. Use the summary heuristic
	# we already emit for whether the target_id is a kingdom.
	if bool(result.get("success", false)):
		return
	var tid: String = String(result.get("target_id", ""))
	if tid.is_empty():
		return
	if WorldData.get_kingdom(tid) != null:
		bump_awareness(tid, 2, "failed_action")


func _on_month_passed(_y: int, _m: int) -> void:
	_decay_awareness()
	_maybe_emerge_hunter()
	_maybe_emerge_historian()
	_hunter_heat_tick()


## Awareness heat decays by 1 per month in quiet regions. Regions
## with hunters decay half as fast — a hunter keeps the legend alive.
func _decay_awareness() -> void:
	var keys: Array = awareness_heat.keys().duplicate()
	for kid in keys:
		var kid_s: String = String(kid)
		var heat: int = int(awareness_heat[kid_s])
		if heat <= 0:
			awareness_heat.erase(kid_s)
			continue
		var decay: int = 1
		if hunters_in(kid_s).is_empty():
			decay = 1
		else:
			decay = 1 if _rng.randf() < 0.5 else 0
		var prev_tier: int = awareness_tier_in(kid_s)
		awareness_heat[kid_s] = maxi(0, heat - decay)
		var next_tier: int = awareness_tier_in(kid_s)
		if next_tier != prev_tier:
			awareness_changed.emit(kid_s, next_tier)


## A kingdom at INSTITUTIONAL or PERSONAL awareness may generate a
## hunter from its existing actor population. We bias toward high-
## intellect, high-paranoia, low-loyalty actors — exactly the kind of
## people the player tends to create through destabilisation (§10.5).
func _maybe_emerge_hunter() -> void:
	# Cap: at most 3 concurrent hunters in a campaign.
	if hunters.size() >= 3:
		return
	# §10.6 Fast-hunters modifier: allow emergence one tier earlier
	# (PATTERN instead of INSTITUTIONAL) and boost chance per month.
	var dp: DifficultyProfile = DifficultyProfile.current()
	var min_tier: int = TIER_INSTITUTIONAL
	var chance_mult: float = 1.0
	if dp.fast_hunters:
		min_tier = maxi(TIER_INSTITUTIONAL - 1, 0)
		chance_mult = 1.0 / dp.hunter_threshold_multiplier()
	for kid in awareness_heat.keys():
		var kid_s: String = String(kid)
		var tier: int = awareness_tier_in(kid_s)
		if tier < min_tier:
			continue
		var chance: float = 0.04 if tier == TIER_INSTITUTIONAL else 0.10
		chance *= chance_mult
		if _rng.randf() > minf(chance, 0.99):
			continue
		var candidate: Actor = _pick_hunter_candidate(kid_s)
		if candidate == null:
			continue
		if hunters.has(String(candidate.id)):
			continue
		var h: Dictionary = {
			"actor_id":   String(candidate.id),
			"kingdom_id": kid_s,
			"intensity":  30 + _rng.randi_range(0, 30),
			"emerged_day": GameClock.absolute_day(),
		}
		hunters[String(candidate.id)] = h
		hunter_emerged.emit(h)
		_send_hunter_letter(candidate, kid_s)
		return  # at most one emergence per month


## §B16 At INSTITUTIONAL awareness or above, a kingdom may grow a
## *historian* — not a detective on the street, but a scholar in the
## archives, working through chroniclers' ledgers decade by decade.
## Historians:
##   - emerge much more slowly than ordinary hunters;
##   - coexist with ordinary hunters (they do not use the usual cap);
##   - cannot be discredited or quieted — only an archive-destroying
##     action removes them.
func _maybe_emerge_historian() -> void:
	# One historian per kingdom at a time is plenty.
	for kid in awareness_heat.keys():
		var kid_s: String = String(kid)
		var tier: int = awareness_tier_in(kid_s)
		if tier < TIER_INSTITUTIONAL:
			continue
		if has_historian_in(kid_s):
			continue
		# 1% per month at INSTITUTIONAL, 3% at PERSONAL.
		var chance: float = 0.01 if tier == TIER_INSTITUTIONAL else 0.03
		if _rng.randf() > chance:
			continue
		var candidate: Actor = _pick_historian_candidate(kid_s)
		if candidate == null:
			continue
		if hunters.has(String(candidate.id)):
			continue
		var h: Dictionary = {
			"actor_id":    String(candidate.id),
			"kingdom_id":  kid_s,
			"intensity":   20 + _rng.randi_range(0, 20),
			"emerged_day": GameClock.absolute_day(),
			"historian":   true,
		}
		hunters[String(candidate.id)] = h
		hunter_emerged.emit(h)
		_send_historian_letter(candidate, kid_s)
		return  # at most one per month


## Historians come from a different demographic than street hunters.
## Prefer high intellect first, paranoia a distant second, and ignore
## loyalty entirely — the person in the archive does not need a
## personal grudge.
func _pick_historian_candidate(kingdom_id: String) -> Actor:
	var best: Actor = null
	var best_score: int = -1
	for a in Actors.all_actors():
		if a.kingdom_id != kingdom_id:
			continue
		if a.is_host():
			continue
		var score: int = a.intellect * 2 + a.paranoia
		if score > best_score:
			best_score = score
			best = a
	if best == null or best_score < 80:
		return null
	return best


func _pick_hunter_candidate(kingdom_id: String) -> Actor:
	var best: Actor = null
	var best_score: int = -1
	for a in Actors.all_actors():
		if a.kingdom_id != kingdom_id:
			continue
		# Already a host? skip — they are our instrument.
		if a.is_host():
			continue
		var score: int = a.intellect + a.paranoia - a.loyalty
		if score > best_score:
			best_score = score
			best = a
	if best == null or best_score < 40:
		return null
	return best


## Hunters slowly raise exposure while they are alive. They also push
## awareness up in their own kingdom: the very fact that someone is
## looking for the shadow figure becomes part of the legend.
## §B16 historians tick on a quarterly rhythm — the archive is slow.
func _hunter_heat_tick() -> void:
	if hunters.is_empty():
		return
	var street_count: int = 0
	var historian_count: int = 0
	for h in hunters.values():
		if bool(h.get("historian", false)):
			historian_count += 1
		else:
			street_count += 1
	if street_count > 0:
		Exposure.bump(0.6 * float(street_count), "hunters_active")
	# Historians only bump exposure once per quarter (every third month).
	if historian_count > 0 and (GameClock.month % 3) == 0:
		Exposure.bump(0.4 * float(historian_count), "historians_active")
	for h in hunters.values():
		if bool(h.get("historian", false)):
			# Historians add awareness heat once a quarter — they are
			# patient, not loud.
			if (GameClock.month % 3) == 0:
				bump_awareness(String(h.get("kingdom_id", "")), 1, "historian_active")
		else:
			bump_awareness(String(h.get("kingdom_id", "")), 1, "hunter_active")


## §B16 Announce a historian — a different shape of threat from the
## street hunter. The letter language leans on scholarship and
## patience rather than pursuit.
func _send_historian_letter(actor: Actor, kingdom_id: String) -> void:
	var k: Kingdom = WorldData.get_kingdom(kingdom_id)
	var region: String = k.kingdom_name if k != null else kingdom_id
	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var subject: String = "A historian is reading everything in %s" % region
	var body: String = (
		"In %s a different sort of pursuer has opened the door.\n\n"
		+ "[b]%s[/b] sits in the archives and in the rooms that archives lead to. "
		+ "They are not chasing you through markets or taverns; they are building a ledger of "
		+ "coincidences across three generations. A discredit will not dislodge them — no one is "
		+ "listening for rumour against a scholar. A quiet word in the right ear will not quiet "
		+ "them — their ear is the archive itself.\n\n"
		+ "If they become intolerable, the archive that sustains them must be destroyed. That is "
		+ "a louder instrument than we usually reach for."
	) % [region, actor.display_name()]
	var letter: Letter = Letter.create(
		"historian_%s" % String(actor.id),
		"Your watcher in the archives",
		date, subject, body, &"intel", &"high",
	)
	EventBus.letter_delivered.emit(letter)


func _send_hunter_letter(actor: Actor, kingdom_id: String) -> void:
	var k: Kingdom = WorldData.get_kingdom(kingdom_id)
	var region: String = k.kingdom_name if k != null else kingdom_id
	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var subject: String = "Someone is looking for you in %s" % region
	var body: String = (
		"In %s a figure has surfaced who is no longer asking the ordinary questions.\n\n"
		+ "[b]%s[/b] has been to the magistrates, to the archivists, to the priests. "
		+ "They are holding up a list of events from the last decade and asking why no name "
		+ "sits beneath any of them. They have started to use a word for what they think sits "
		+ "at the centre of that list. The word is not our word. It is close enough.\n\n"
		+ "They have not yet reached the truth. They are no longer in the wrong part of the room, either.\n\n"
		+ "What you do with this is yours to decide — but they are, from today, a hunter in the sense the old stories meant."
	) % [region, actor.display_name()]
	var letter: Letter = Letter.create(
		"hunter_%s" % String(actor.id),
		"Your watcher in the quarter",
		date, subject, body, &"intel", &"high",
	)
	EventBus.letter_delivered.emit(letter)


# --- Save / load ----------------------------------------------------------

func snapshot() -> Dictionary:
	var heat_out: Dictionary = {}
	for k in awareness_heat:
		heat_out[String(k)] = int(awareness_heat[k])
	return {
		"legend":          legend,
		"awareness_heat":  heat_out,
		"hunters":         hunters.duplicate(true),
	}


func restore(d: Dictionary) -> void:
	legend = int(d.get("legend", 0))
	awareness_heat.clear()
	var h: Variant = d.get("awareness_heat", {})
	if h is Dictionary:
		for k in h:
			awareness_heat[String(k)] = int(h[k])
	hunters.clear()
	var hh: Variant = d.get("hunters", {})
	if hh is Dictionary:
		for k in hh:
			hunters[String(k)] = (hh[k] as Dictionary).duplicate(true)
	legend_changed.emit(legend)
