extends Node
## Autoloaded as `Mandates`. Directed objectives the player commits to
## (§11). Two flavours land in this first slice — Removal and
## Survival — each with its own phase logic. Adding more later is a
## matter of extending the match statements in `_on_*` handlers; the
## Mandate data shape and lifecycle are generic.
##
## The registry owns:
##   - a dictionary of Mandate resources by id
##   - phase progression driven by simulation signals
##     (action_resolved, actor_died, exposure_level, month_passed)
##   - offer / accept / defer / abandon API
##   - emergent offers driven by world conditions (a ruler whose
##     ambition crosses a threshold offers a Removal dispatch)
##   - a small flow of inbox letters around offer / phase / finish
##   - save/load

signal mandate_offered(id: StringName)
signal mandate_accepted(id: StringName)
signal mandate_completed(id: StringName)
signal mandate_failed(id: StringName)
signal mandate_phase_advanced(id: StringName, phase_index: int)

# Removal phase structure.
const REMOVAL_PHASE_IDENTIFY:   StringName = &"removal_identify"
const REMOVAL_PHASE_SHAKE:      StringName = &"removal_shake"
const REMOVAL_PHASE_FINISH:     StringName = &"removal_finish"

# Survival phase structure.
const SURVIVAL_PHASE_GO_COLD:   StringName = &"survival_go_cold"
const SURVIVAL_PHASE_OUTLAST:   StringName = &"survival_outlast"

const REMOVAL_DEADLINE_DAYS: int = 36 * 30   # ~3 years
const SURVIVAL_GO_COLD_MONTHS: int = 12
const SURVIVAL_OUTLAST_MONTHS: int = 24
const SURVIVAL_EXPOSURE_THRESHOLD: float = 15.0

# Emergent offer thresholds.
const EMERGENT_REMOVAL_AMBITION: int = 80
const EMERGENT_REMOVAL_RUTHLESSNESS: int = 70
const EMERGENT_OFFER_COOLDOWN_MONTHS: int = 6

# Active + archived mandates, id -> Mandate.
var mandates: Dictionary = {}

# Last month we offered any emergent mandate. Gates repeat offers.
var _last_emergent_month: int = -9999

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	EventBus.action_resolved.connect(_on_action_resolved)
	EventBus.actor_died.connect(_on_actor_died)
	GameClock.month_passed.connect(_on_month_passed)


# --- Public API --------------------------------------------------------------

func all_mandates() -> Array:
	return mandates.values()


func active_mandates() -> Array:
	var out: Array = []
	for m in mandates.values():
		if m.status == Mandate.Status.ACTIVE:
			out.append(m)
	return out


func offered_mandates() -> Array:
	var out: Array = []
	for m in mandates.values():
		if m.status == Mandate.Status.OFFERED:
			out.append(m)
	return out


func accept(mandate_id: StringName) -> bool:
	var m: Mandate = mandates.get(mandate_id, null)
	if m == null or m.status != Mandate.Status.OFFERED:
		return false
	m.status = Mandate.Status.ACTIVE
	m.started_abs_day = GameClock.absolute_day()
	_activate_first_phase(m)
	mandate_accepted.emit(m.id)
	_send_letter(
		"The %s, accepted" % m.headline.to_lower(),
		"You have taken up the mandate: %s\n\n%s\n\nThe first phase is %s — %s" % [
			m.headline, m.blurb,
			_phase_name(m.active_phase()), _phase_description(m.active_phase()),
		],
		&"intro",
	)
	return true


func defer(mandate_id: StringName) -> bool:
	var m: Mandate = mandates.get(mandate_id, null)
	if m == null or m.status != Mandate.Status.OFFERED:
		return false
	m.status = Mandate.Status.DEFERRED
	return true


func abandon(mandate_id: StringName) -> bool:
	var m: Mandate = mandates.get(mandate_id, null)
	if m == null or m.is_terminal():
		return false
	m.status = Mandate.Status.FAILED
	mandate_failed.emit(m.id)
	return true


# --- Offering ---------------------------------------------------------------

## Player-initiated: craft a removal mandate against an actor they
## have already identified. Returns the mandate id if created, &""
## if the target is invalid (dead, already targeted, etc).
func offer_removal_mandate(target_actor_id: StringName, emergent: bool = false) -> StringName:
	var a: Actor = Actors.get_actor(target_actor_id)
	if a == null or a.dead:
		return &""
	# Don't double-target.
	for m in mandates.values():
		if (
			m.category == Mandate.Category.REMOVAL
			and m.target_actor_id == target_actor_id
			and not m.is_terminal()
		):
			return &""

	var man: Mandate = Mandate.new()
	man.id               = StringName("removal_%s_%d" % [String(target_actor_id), GameClock.absolute_day()])
	man.category         = Mandate.Category.REMOVAL
	man.status           = Mandate.Status.OFFERED
	man.target_actor_id  = target_actor_id
	man.emergent         = emergent
	man.headline         = "Removal of %s" % a.display_name
	man.blurb            = "%s has grown into a threat the balance cannot absorb. The mandate is to end their career — by any means the organisation can bear, within a reasonable span. Removal cannot be rushed; nor can it be postponed forever." % a.display_name
	man.started_abs_day  = GameClock.absolute_day()
	man.deadline_abs_day = GameClock.absolute_day() + REMOVAL_DEADLINE_DAYS
	man.phases = [
		{
			"name": "Identify the threat",
			"description": "Observe the target twice to catalogue their reach, retainers, and routines.",
			"progress": 0, "target": 2,
			"state": "pending",
			"condition": String(REMOVAL_PHASE_IDENTIFY),
		},
		{
			"name": "Shake the pillars",
			"description": "Cultivate or bribe two of the target's peers. The removal needs someone to outlive it.",
			"progress": 0, "target": 2,
			"state": "pending",
			"condition": String(REMOVAL_PHASE_SHAKE),
		},
		{
			"name": "The removal itself",
			"description": "The target must die — by blade, by poison, by the hand of an ally turned.",
			"progress": 0, "target": 1,
			"state": "pending",
			"condition": String(REMOVAL_PHASE_FINISH),
		},
	]

	mandates[man.id] = man
	mandate_offered.emit(man.id)
	_send_offer_letter(man)
	# No accept/defer UI yet — treat the act of offering as the
	# commitment. Future work wires this through the Mandates panel.
	accept(man.id)
	return man.id


## Player-initiated survival mandate. A 3-year vow of quietness with
## exposure held below SURVIVAL_EXPOSURE_THRESHOLD throughout. Breaking
## that threshold fails the mandate immediately.
func offer_survival_mandate(note: String = "") -> StringName:
	for m in mandates.values():
		if m.category == Mandate.Category.SURVIVAL and not m.is_terminal():
			return &""
	var man: Mandate = Mandate.new()
	man.id            = StringName("survival_%d" % GameClock.absolute_day())
	man.category      = Mandate.Category.SURVIVAL
	man.status        = Mandate.Status.OFFERED
	man.emergent      = false
	man.headline      = "Go to ground"
	man.blurb         = "A vow of quietness. No burning moves, no loud silver, no new hosts cultivated brazenly. Hold exposure below a thin line for a full year, then another two for good measure. Any breach ends the mandate — you will have showed your hand." + ("\n\n" + note if note != "" else "")
	man.started_abs_day  = GameClock.absolute_day()
	man.deadline_abs_day = -1
	man.phases = [
		{
			"name": "Go cold",
			"description": "Keep exposure below the quiet threshold for twelve consecutive months.",
			"progress": 0, "target": SURVIVAL_GO_COLD_MONTHS,
			"state": "pending",
			"condition": String(SURVIVAL_PHASE_GO_COLD),
		},
		{
			"name": "Outlast the memory",
			"description": "Hold the line for another twenty-four months. The hunt has a short attention span; outwait it.",
			"progress": 0, "target": SURVIVAL_OUTLAST_MONTHS,
			"state": "pending",
			"condition": String(SURVIVAL_PHASE_OUTLAST),
		},
	]

	mandates[man.id] = man
	mandate_offered.emit(man.id)
	_send_offer_letter(man)
	accept(man.id)
	return man.id


# --- Progress: action resolved ---------------------------------------------

func _on_action_resolved(action_id: StringName, result: Dictionary) -> void:
	var success: bool = bool(result.get("success", false))
	var target_id: String = String(result.get("target_id", ""))
	if not success:
		return
	for m in mandates.values():
		if m.status != Mandate.Status.ACTIVE:
			continue
		var phase: Dictionary = m.active_phase()
		if phase.is_empty():
			continue
		var cond: String = String(phase.get("condition", ""))
		match cond:
			String(REMOVAL_PHASE_IDENTIFY):
				if action_id == &"observe" and target_id == String(m.target_actor_id):
					_bump_phase(m, 1)
			String(REMOVAL_PHASE_SHAKE):
				if action_id in [&"cultivate", &"bribe_direct", &"bribe_retainer",
						&"bribe_career", &"bribe_info", &"bribe_gift",
						&"plant_idea"]:
					if _actor_shares_kingdom(target_id, m.target_actor_id):
						_bump_phase(m, 1)


func _on_actor_died(actor_id: StringName, _was_host: bool, _cause: StringName) -> void:
	for m in mandates.values():
		if m.status != Mandate.Status.ACTIVE:
			continue
		if m.category != Mandate.Category.REMOVAL:
			continue
		if m.target_actor_id != actor_id:
			continue
		# Only the finish phase counts the death; earlier death is
		# still a win but shortcuts the mandate.
		_bump_phase(m, 999, true)


# --- Progress: monthly ------------------------------------------------------

func _on_month_passed(_y: int, _m: int) -> void:
	# Exposure-driven phases tick here.
	for m in mandates.values():
		if m.status != Mandate.Status.ACTIVE:
			continue
		var phase: Dictionary = m.active_phase()
		if phase.is_empty():
			continue
		var cond: String = String(phase.get("condition", ""))
		if cond == String(SURVIVAL_PHASE_GO_COLD) or cond == String(SURVIVAL_PHASE_OUTLAST):
			if Exposure.value <= SURVIVAL_EXPOSURE_THRESHOLD:
				_bump_phase(m, 1)
			else:
				_fail_mandate(m, "Exposure ran loud. The vow is broken.")
		# Deadline check.
		if m.deadline_abs_day >= 0 and GameClock.absolute_day() >= m.deadline_abs_day:
			_fail_mandate(m, "The window has closed.")
	_maybe_offer_emergent()


func _maybe_offer_emergent() -> void:
	var now_month: int = GameClock.year * 12 + GameClock.month
	if now_month - _last_emergent_month < EMERGENT_OFFER_COOLDOWN_MONTHS:
		return
	# Walk actors and find one whose traits cross the emergent
	# threshold and who isn't already targeted.
	var candidates: Array[Actor] = []
	for a in Actors.all_actors():
		if a.dead:
			continue
		if (
			a.ambition >= EMERGENT_REMOVAL_AMBITION
			and a.ruthlessness >= EMERGENT_REMOVAL_RUTHLESSNESS
		):
			if _already_targeted(a.id):
				continue
			# Only offer on rulers — high-ambition commoners are a
			# dime a dozen; a dangerous ambition is one holding a
			# crown.
			if a.role == Actor.Role.RULER:
				candidates.append(a)
	if candidates.is_empty():
		return
	var pick: Actor = candidates[_rng.randi_range(0, candidates.size() - 1)]
	if offer_removal_mandate(pick.id, true) != &"":
		_last_emergent_month = now_month


func _already_targeted(aid: StringName) -> bool:
	for m in mandates.values():
		if (
			m.category == Mandate.Category.REMOVAL
			and m.target_actor_id == aid
			and not m.is_terminal()
		):
			return true
	return false


# --- Phase bookkeeping ------------------------------------------------------

func _activate_first_phase(m: Mandate) -> void:
	if m.phases.is_empty():
		return
	m.current_phase = 0
	m.phases[0]["state"] = "active"


func _bump_phase(m: Mandate, amount: int, clamp_to_target: bool = false) -> void:
	var phase: Dictionary = m.active_phase()
	if phase.is_empty() or String(phase.get("state", "pending")) != "active":
		return
	var target: int = int(phase.get("target", 1))
	var progress: int = int(phase.get("progress", 0)) + amount
	if clamp_to_target or progress >= target:
		progress = target
	phase["progress"] = progress
	m.phases[m.current_phase] = phase
	if progress >= target:
		phase["state"] = "done"
		m.phases[m.current_phase] = phase
		_advance_phase(m)


func _advance_phase(m: Mandate) -> void:
	var next: int = m.current_phase + 1
	if next >= m.phases.size():
		_complete_mandate(m)
		return
	m.current_phase = next
	m.phases[next]["state"] = "active"
	mandate_phase_advanced.emit(m.id, next)
	_send_letter(
		"%s — phase advanced" % m.headline,
		"The previous phase is closed. You move to: %s — %s" % [
			_phase_name(m.active_phase()), _phase_description(m.active_phase()),
		],
		&"intel",
	)


func _complete_mandate(m: Mandate) -> void:
	m.status = Mandate.Status.COMPLETED
	mandate_completed.emit(m.id)
	_send_letter(
		"%s — completed" % m.headline,
		"The mandate is discharged. The world has shifted in the direction we asked of it.",
		&"intro",
	)


func _fail_mandate(m: Mandate, reason: String) -> void:
	m.status = Mandate.Status.FAILED
	mandate_failed.emit(m.id)
	_send_letter(
		"%s — failed" % m.headline,
		"The mandate will not be carried. %s\n\nThe world moves on with or without our intent." % reason,
		&"intel",
	)


# --- Helpers ----------------------------------------------------------------

func _actor_shares_kingdom(a_id: String, b_id: StringName) -> bool:
	var a: Actor = Actors.get_actor(StringName(a_id))
	var b: Actor = Actors.get_actor(b_id)
	if a == null or b == null:
		return false
	return a.kingdom_id == b.kingdom_id


func _phase_name(phase: Dictionary) -> String:
	return String(phase.get("name", ""))


func _phase_description(phase: Dictionary) -> String:
	return String(phase.get("description", ""))


func _send_offer_letter(m: Mandate) -> void:
	var subject: String = ("%s — urgent dispatch" % m.headline) if m.emergent else m.headline
	var body: String = "%s\n\nOpen the Mandates panel to accept or defer." % m.blurb
	_send_letter(subject, body, &"intro")


func _send_letter(subject: String, body: String, kind: StringName) -> void:
	if Inbox == null:
		return
	var letter: Letter = Letter.create(
		StringName("mandate_%d_%d" % [GameClock.absolute_day(), Inbox.letters.size()]),
		"Your chief of mandates",
		GameDate.make(GameClock.year, GameClock.month, GameClock.day),
		subject,
		body,
		kind,
	)
	Inbox.add_letter(letter)


# --- Save / load ------------------------------------------------------------

func snapshot() -> Dictionary:
	var arr: Array = []
	for m in mandates.values():
		arr.append(m.to_dict())
	return {
		"mandates":            arr,
		"_last_emergent_month": _last_emergent_month,
	}


func restore(d: Dictionary) -> void:
	mandates.clear()
	for entry in d.get("mandates", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var m: Mandate = Mandate.from_dict(entry)
		if m.id == &"":
			continue
		mandates[m.id] = m
	_last_emergent_month = int(d.get("_last_emergent_month", -9999))
