extends Node
## Autoloaded as `Dynasties`. §21 — family trees, generational
## service and succession. A family is a named, tracked dynasty
## the player runs through. The registry answers three questions
## the world keeps asking:
##
##   1. Who is the current head of this family, and who takes
##      over when they die?
##   2. How has the player treated them across generations,
##      and how should that reshape the next child's traits?
##   3. Is the family on its way out — is it time to find
##      another?
##
## This is deliberately narrow scaffolding. Only actors the
## player has explicitly brought into the net (founded a family
## around, or confirmed as part of one) appear here; the ambient
## roster runs without dynastic tracking.

signal family_added(family: Family)
signal family_succession(family_id: StringName, old_head: StringName, new_head: StringName)
signal family_declined(family_id: StringName, reason: String)
signal family_child_born(family_id: StringName, parent_id: StringName, child_id: StringName)
signal family_need_raised(family_id: StringName, kind: StringName)
signal family_need_resolved(family_id: StringName, kind: StringName, protected: bool)


## family id -> Family
var families: Dictionary = {}

## Amount decline_score climbs each month while neglected.
const MONTHLY_DECLINE_DRIFT: int = 1
## Threshold at which we announce "the family is fading".
const DECLINE_WARN: int = 55
## Threshold at which the family dissolves on its own.
const DECLINE_BREAK: int = 85

## How much loyalty_culture a successful cultivate on a family
## member nudges the whole family. Small by design — only
## sustained attention compounds into generational loyalty.
const CULTIVATE_CULTURE_BUMP: int = 2

## Boost applied to culture when the player explicitly "protects
## the family in crisis" via `note_crisis_response`. Larger than
## the cultivate drip because these moments are remembered.
const PROTECT_CULTURE_BUMP: int = 18
const IGNORE_CULTURE_PENALTY: int = -14

## Cap on the trait bias applied to a newborn family member from
## the family culture. Stops us from grinding out +90 loyalty
## superchildren after a few centuries of cultivation.
const TRAIT_BIAS_CAP: int = 18

## Trait bump applied to juniors in an underdog-focused family on
## a successful domain-aligned action. Kept small so it takes a
## sustained campaign to close the gap with incumbents.
const UNDERDOG_TRAIT_BUMP: int = 1
## Per-actor ceiling on underdog-driven trait growth, to keep the
## compounding bounded.
const UNDERDOG_TRAIT_CAP: int = 85

## Odds each month that a family with no open need gets one.
## Roughly: a family raises a need ~twice a decade under normal
## play. Decline-score raises the rate — stressed families need
## the patron more often.
const NEED_BASE_CHANCE: float = 0.017
const NEED_DECLINE_SCALE: float = 0.0008   # per decline point

## Deadline window for a raised need, in days. About six months.
const NEED_DEADLINE_DAYS: int = 180

## Kinds of need drawn from §21.3. Weights are roughly balanced;
## succession / drift skew toward older families via the code path,
## not here.
const NEED_KINDS: Array[StringName] = [
	&"legal", &"blackmail", &"business", &"succession", &"status", &"drift",
]

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	EventBus.actor_died.connect(_on_actor_died)
	EventBus.action_resolved.connect(_on_action_resolved)
	GameClock.month_passed.connect(_on_month_passed)


# --- Public API --------------------------------------------------------------

## Wrap an existing actor in a brand-new family, making them its
## founding head. Idempotent — calling again with the same head
## returns the family already in place.
func found_family(
	head_actor_id: StringName,
	domain: Family.Domain,
	family_name: String = ""
) -> Family:
	var head: Actor = Actors.get_actor(head_actor_id)
	if head == null:
		return null
	if head.family_id != &"":
		return families.get(head.family_id, null)

	var fid: StringName = StringName("fam_%s_%d" % [String(head_actor_id), Time.get_ticks_msec()])
	var f: Family = Family.new()
	f.id = fid
	f.domain = domain
	f.home_kingdom = head.kingdom_id
	f.founded_year = -GameClock.year
	f.family_name = family_name if family_name != "" else _derive_family_name(head)
	f.head_id = head_actor_id
	f.members = [head_actor_id]
	f.generations_served = 1
	@warning_ignore("integer_division")
	var starting_loyalty: int = clampi(head.relationship / 2, -100, 100)
	f.loyalty_culture = starting_loyalty

	families[fid] = f
	head.family_id = fid
	family_added.emit(f)
	return f


## Mark an existing actor as a child of the given parent, joining
## the parent's family tree. Returns true on success.
func register_child(parent_id: StringName, child: Actor) -> bool:
	var parent: Actor = Actors.get_actor(parent_id)
	if parent == null or child == null:
		return false
	var fid: StringName = parent.family_id
	if fid == &"":
		return false
	var f: Family = families.get(fid, null)
	if f == null:
		return false

	child.parent_id = parent.id
	child.family_id = fid
	if not parent.children.has(child.id):
		parent.children.append(child.id)
	if not f.members.has(child.id):
		f.members.append(child.id)
	_apply_family_culture_to_actor(child, f)
	family_child_born.emit(fid, parent.id, child.id)
	return true


## Spawn a fresh next-generation member of a family — typically
## the heir-in-waiting. Role defaults to a junior version of the
## head's role (heir for rulers, merchant for merchants, etc.).
func spawn_next_gen(family_id: StringName, role_override: int = -1) -> Actor:
	var f: Family = families.get(family_id, null)
	if f == null:
		return null
	var head: Actor = Actors.get_actor(f.head_id)
	if head == null:
		return null

	var role: int = role_override if role_override >= 0 else _junior_role_for(head.role)
	var child: Actor = Actors.spawn_actor(head.kingdom_id, role, &"family_heir")
	if child == null:
		return null
	# Bring the child's age down — Actors.spawn_actor gives them
	# a working age for their role by default, but for a "next
	# generation being raised" we want them younger.
	var now_year: int = -GameClock.year
	child.birth_year = now_year - _rng.randi_range(18, 28)
	register_child(f.head_id, child)
	return child


## Call this when the player acts to shield a family through a
## crisis — a bailout, a protected heir, a legal cover-up. Moves
## the cultural loyalty needle materially. Also closes any open
## raised need on the family.
func note_crisis_response(family_id: StringName, protected: bool) -> void:
	var f: Family = families.get(family_id, null)
	if f == null:
		return
	var had_need: bool = f.has_open_need()
	var kind: StringName = f.need_kind
	if protected:
		f.loyalty_culture = clampi(f.loyalty_culture + PROTECT_CULTURE_BUMP, -100, 100)
		f.competence_bias = clampi(f.competence_bias + 2, -40, 40)
		f.decline_score = clampi(f.decline_score - 8, 0, 100)
	else:
		f.loyalty_culture = clampi(f.loyalty_culture + IGNORE_CULTURE_PENALTY, -100, 100)
		f.resentment = clampi(f.resentment + 6, -40, 40)
		f.decline_score = clampi(f.decline_score + 4, 0, 100)
	if had_need:
		_close_need(f, protected)
		family_need_resolved.emit(f.id, kind, protected)


## Record a deliberate investment in the next generation — a
## tutor hired, a foreign education paid for, an apprenticeship
## arranged. Raises the competence ceiling children can be
## spawned with later.
func invest_in_children(family_id: StringName) -> void:
	var f: Family = families.get(family_id, null)
	if f == null:
		return
	f.competence_bias = clampi(f.competence_bias + 4, -40, 40)
	f.loyalty_culture = clampi(f.loyalty_culture + 3, -100, 100)
	f.fatigue = clampi(f.fatigue - 2, -40, 40)


func family_of(actor: Actor) -> Family:
	if actor == null or actor.family_id == &"":
		return null
	return families.get(actor.family_id, null)


func all_families() -> Array[Family]:
	var out: Array[Family] = []
	for f in families.values():
		out.append(f)
	return out


# --- Lifecycle ---------------------------------------------------------------

func _on_actor_died(actor_id: StringName, _was_host: bool, _cause: StringName) -> void:
	var a: Actor = Actors.get_actor(actor_id)
	if a == null or a.family_id == &"":
		return
	var f: Family = families.get(a.family_id, null)
	if f == null:
		return

	# If it's the head dying, promote a successor.
	if f.head_id == actor_id:
		# The head's final relationship to the player colours the
		# culture the next generation inherits — a warm death is
		# remembered, a cold one becomes a family grievance.
		if a.relationship >= 40:
			f.loyalty_culture = clampi(f.loyalty_culture + 6, -100, 100)
		elif a.relationship <= -20:
			f.loyalty_culture = clampi(f.loyalty_culture - 8, -100, 100)
			f.resentment = clampi(f.resentment + 4, -40, 40)

		var successor: Actor = _pick_successor(f)
		if successor == null:
			# No living heir — the line ends here. Mark as dissolved.
			f.dissolved = true
			f.dissolved_reason = "no living heir"
			f.dissolved_year = -GameClock.year
			family_declined.emit(f.id, f.dissolved_reason)
			_announce_decline(f, "The line ends: no heir carries the name.")
			return
		var old: StringName = f.head_id
		f.head_id = successor.id
		f.generations_served += 1
		family_succession.emit(f.id, old, successor.id)
		_announce_succession(f, a, successor)


func _on_action_resolved(action_id: StringName, result: Dictionary) -> void:
	if not bool(result.get("success", false)):
		return
	var target_id: String = String(result.get("target_id", ""))
	if target_id.is_empty():
		return
	var target: Actor = Actors.get_actor(StringName(target_id))
	if target == null or target.family_id == &"":
		return
	var f: Family = families.get(target.family_id, null)
	if f == null:
		return

	match String(action_id):
		"cultivate":
			f.loyalty_culture = clampi(f.loyalty_culture + CULTIVATE_CULTURE_BUMP, -100, 100)
			f.fatigue = clampi(f.fatigue - 1, -40, 40)
		"bribe":
			# A paid transaction tells the family your purse is open
			# but not your heart — culture inches down a touch,
			# fatigue creeps up.
			f.loyalty_culture = clampi(f.loyalty_culture - 1, -100, 100)
			f.fatigue = clampi(f.fatigue + 1, -40, 40)

	if f.underdog_focus and _action_matches_domain(String(action_id), f.domain):
		_grow_underdog_juniors(f)


## Flag (or unflag) a family as following the underdog track.
func mark_underdog(family_id: StringName, enable: bool = true) -> void:
	var f: Family = families.get(family_id, null)
	if f == null:
		return
	f.underdog_focus = enable


## Does an action id plausibly exercise this family's specialisation?
## Kept deliberately coarse — the point is to reward sustained play
## inside the family's lane, not to tune micro-actions.
func _action_matches_domain(action_id: String, domain: Family.Domain) -> bool:
	match domain:
		Family.Domain.BANKING:
			return action_id in ["bribe", "bribe_retainer", "embed_banker", "settle_iou"]
		Family.Domain.MERCHANT:
			return action_id in ["bribe", "found_trading_company", "open_trade", "cultivate"]
		Family.Domain.SCHOLARLY:
			return action_id in ["cultivate", "found_academy", "spread_doctrine", "archive_research"]
		Family.Domain.MILITARY:
			return action_id in ["bribe", "cultivate", "incite_unrest", "assassinate", "rotate_roles"]
		Family.Domain.RELIGIOUS:
			return action_id in ["cultivate", "spread_doctrine", "found_monastery", "proselytise"]
		Family.Domain.COURT:
			return action_id in ["cultivate", "bribe", "spread_rumour", "false_flag_operation"]
	return false


## Bump the domain-aligned primary trait on every living non-head
## member of the family by UNDERDOG_TRAIT_BUMP, up to a cap.
func _grow_underdog_juniors(f: Family) -> void:
	var trait_name: String = f.primary_trait_for_domain()
	for mid in f.members:
		if mid == f.head_id:
			continue
		var a: Actor = Actors.get_actor(mid)
		if a == null or not a.is_alive():
			continue
		var cur: int = int(a.get(trait_name))
		if cur >= UNDERDOG_TRAIT_CAP:
			continue
		a.set(trait_name, mini(UNDERDOG_TRAIT_CAP, cur + UNDERDOG_TRAIT_BUMP))


func _on_month_passed(_y: int, _m: int) -> void:
	var today: int = GameClock.absolute_day()
	for f in families.values():
		if f.dissolved:
			continue
		_tick_family(f)
		_tick_need(f, today)


func _tick_family(f: Family) -> void:
	# Drift decline. Resentment and fatigue rot the dynasty;
	# loyalty_culture offsets the rot.
	var drift: int = MONTHLY_DECLINE_DRIFT
	@warning_ignore("integer_division")
	var res_drift: int = f.resentment / 8
	@warning_ignore("integer_division")
	var fat_drift: int = f.fatigue / 10
	@warning_ignore("integer_division")
	var loy_relief: int = f.loyalty_culture / 20
	drift += max(0, res_drift)
	drift += max(0, fat_drift)
	drift -= max(0, loy_relief)
	f.decline_score = clampi(f.decline_score + drift, 0, 100)

	# Resentment and fatigue naturally ebb (unless sustained).
	if f.resentment > 0:
		f.resentment = maxi(0, f.resentment - 1)
	if f.fatigue > 0:
		f.fatigue = maxi(0, f.fatigue - 1)

	if f.decline_score >= DECLINE_BREAK:
		f.dissolved = true
		f.dissolved_reason = "catastrophic decline"
		f.dissolved_year = -GameClock.year
		family_declined.emit(f.id, f.dissolved_reason)
		_announce_decline(f, "Scandal, neglect and ambition have finished the line.")
		return

	if f.decline_score >= DECLINE_WARN and f.decline_score - drift < DECLINE_WARN:
		_announce_decline(f, "They are fading. A replacement should be found.")


# --- Succession helpers ------------------------------------------------------

func _pick_successor(f: Family) -> Actor:
	# Prefer a living child of the late head who is old enough to
	# take the seat. Sort by age (eldest first). Fall back to any
	# living family member.
	var head: Actor = Actors.get_actor(f.head_id)
	var candidates: Array[Actor] = []
	if head != null:
		for cid in head.children:
			var c: Actor = Actors.get_actor(cid)
			if c != null and c.is_alive():
				candidates.append(c)
	if candidates.is_empty():
		for mid in f.members:
			if mid == f.head_id:
				continue
			var m: Actor = Actors.get_actor(mid)
			if m != null and m.is_alive():
				candidates.append(m)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(x, y): return x.birth_year < y.birth_year)
	return candidates[0]


func _junior_role_for(role: int) -> int:
	match role:
		int(Actor.Role.RULER):    return int(Actor.Role.HEIR)
		int(Actor.Role.MERCHANT): return int(Actor.Role.MERCHANT)
		int(Actor.Role.PRIEST):   return int(Actor.Role.PRIEST)
		int(Actor.Role.GENERAL):  return int(Actor.Role.GENERAL)
		int(Actor.Role.ADVISOR):  return int(Actor.Role.ADVISOR)
		_:                        return int(Actor.Role.COMMONER)


# --- Trait biasing -----------------------------------------------------------

## Shift an actor's fresh traits in line with the family culture
## they grew up in. Loyalty_culture tilts loyalty directly;
## competence_bias raises intellect and charisma; resentment
## drags trust down and ambition up. All clamped to TRAIT_BIAS_CAP
## so a single child never ends up a statistical freak.
func _apply_family_culture_to_actor(a: Actor, f: Family) -> void:
	@warning_ignore("integer_division")
	var loy_bias: int = clampi(f.loyalty_culture / 6, -TRAIT_BIAS_CAP, TRAIT_BIAS_CAP)
	var res_bias: int = clampi(f.resentment, -TRAIT_BIAS_CAP, TRAIT_BIAS_CAP)
	var comp_bias: int = clampi(f.competence_bias, -TRAIT_BIAS_CAP, TRAIT_BIAS_CAP)
	@warning_ignore("integer_division")
	var res_half: int = res_bias / 2
	@warning_ignore("integer_division")
	var comp_half: int = comp_bias / 2

	a.loyalty   = clampi(a.loyalty + loy_bias - res_bias, 10, 95)
	a.ambition  = clampi(a.ambition + res_half, 10, 95)
	a.intellect = clampi(a.intellect + comp_bias, 10, 95)
	a.charisma  = clampi(a.charisma + comp_half, 10, 95)
	a.paranoia  = clampi(a.paranoia + res_half, 10, 95)


# --- Needs loop (§21.3) ------------------------------------------------------

func _tick_need(f: Family, today: int) -> void:
	# Resolve by deadline first — if the player didn't answer, the
	# family reads it as indifference. Permanent grievance.
	if f.has_open_need() and today >= f.need_deadline_abs_day:
		note_crisis_response(f.id, false)
		return

	if f.has_open_need():
		return

	var roll: float = _rng.randf()
	var chance: float = NEED_BASE_CHANCE + NEED_DECLINE_SCALE * float(f.decline_score)
	# Young, warm dynasties rarely need you; strained ones need you
	# often. Cap the chance so we don't flood the inbox.
	chance = clampf(chance, 0.0, 0.08)
	if roll >= chance:
		return

	_raise_need(f)


func _raise_need(f: Family) -> void:
	var kind: StringName = _pick_need_kind_for(f)
	var pair: Array = _need_copy_for(f, kind)
	var headline: String = String(pair[0])
	var blurb: String = String(pair[1])

	f.need_kind = kind
	f.need_headline = headline
	f.need_blurb = blurb
	f.need_deadline_abs_day = GameClock.absolute_day() + NEED_DEADLINE_DAYS
	var letter_id: StringName = StringName("family_need_%s_%d" % [String(f.id), Time.get_ticks_msec()])
	f.need_letter_id = letter_id

	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var letter: Letter = Letter.create(
		letter_id,
		"%s — %s" % [f.family_name, f.domain_label()],
		date,
		headline,
		blurb,
		&"host"
	)
	EventBus.letter_delivered.emit(letter)
	family_need_raised.emit(f.id, kind)


func _close_need(f: Family, _protected: bool) -> void:
	f.need_kind = &""
	f.need_headline = ""
	f.need_blurb = ""
	f.need_deadline_abs_day = 0
	f.need_letter_id = &""


func _pick_need_kind_for(f: Family) -> StringName:
	# Slightly context-aware: older families see more succession /
	# drift, fresh ones more legal / business scrapes.
	var weights: Dictionary = {
		&"legal":      3,
		&"blackmail":  3,
		&"business":   3,
		&"status":     2,
		&"succession": 1 + f.generations_served,
		&"drift":      1 + maxi(0, f.generations_served - 1),
	}
	var total: int = 0
	for v in weights.values():
		total += int(v)
	var roll: int = _rng.randi_range(1, total)
	var acc: int = 0
	for k in weights.keys():
		acc += int(weights[k])
		if roll <= acc:
			return k
	return &"legal"


func _need_copy_for(f: Family, kind: StringName) -> Array:
	var head: Actor = Actors.get_actor(f.head_id)
	var head_name: String = head.display_name() if head != null else "the head of the house"
	match String(kind):
		"legal":
			return [
				"A member of %s is in irons" % f.family_name,
				"A magistrate in %s has taken %s's nephew into custody on a trumped charge — someone in the court wants the family weakened, quietly. They will not say it aloud, but they are asking whether the patron still stands over them.\n\nA word placed through your political host can make this vanish. Silence will be remembered." % [
					_kingdom_name_of(f.home_kingdom),
					head_name,
				],
			]
		"blackmail":
			return [
				"An approach has been made to %s" % f.family_name,
				"%s writes with great care: a stranger of good manners and questionable patrons has approached their son-in-law with an offer that is dressed as a favour. The family recognises the shape of it. They are asking you to remove the approach before it ripens." % head_name,
			]
		"business":
			return [
				"%s are bleeding silver" % f.family_name,
				"The house's %s interests are under attack — competitors have cornered their suppliers and a minor panic is building against them in the markets. A quiet loan or a word to a friendly magistrate can hold it. Without one, their standing will crack by the next harvest." % f.domain_label(),
			]
		"succession":
			return [
				"A succession quarrel inside %s" % f.family_name,
				"Two of the children are circling the same chair. Without a patron's guiding hand the house will split itself. They ask you to indicate which heir you will stand behind — and then to let the other know, firmly, that the matter is closed.",
			]
		"status":
			return [
				"%s asks for recognition" % f.family_name,
				"They have served three generations in the quiet and would like, respectfully, to be noticed — a magistracy for the eldest, a seat on a trade council, anything with a name on it. Advancement strengthens them; refusal does not lose them, but neither does it warm them.",
			]
		"drift":
			return [
				"The young of %s are listening to strangers" % f.family_name,
				"One of the younger cousins has fallen in with a philosopher whose tone the family finds alarming. They ask whether you can arrange a distraction — a tutor, a foreign post, a quiet conversation — before the drift hardens. They would rather not disinherit their own.",
			]
		_:
			return [
				"A matter at the house of %s" % f.family_name,
				"They ask for the patron's attention.",
			]


# --- Letters / announcements -------------------------------------------------

func _announce_succession(f: Family, deceased: Actor, heir: Actor) -> void:
	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var body: String = (
		"%s is gone. The house does not. %s stands in the doorway now — %s, %s. The ledgers, the contacts, the quiet understandings carry over. They will write to you directly when they are ready."
	) % [
		deceased.display_name(),
		heir.display_name(),
		f.generation_phrase(),
		f.culture_phrase(),
	]
	var letter_id: StringName = StringName("succession_%s_%d" % [String(f.id), Time.get_ticks_msec()])
	var letter: Letter = Letter.create(
		letter_id,
		"Your go-between",
		date,
		"The house continues: %s" % f.family_name,
		body,
		&"host"
	)
	EventBus.letter_delivered.emit(letter)


func _announce_decline(f: Family, line: String) -> void:
	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var body: String = (
		"The %s of %s is not what it was. %s"
	) % [f.domain_label(), f.family_name, line]
	var letter_id: StringName = StringName("decline_%s_%d" % [String(f.id), Time.get_ticks_msec()])
	var letter: Letter = Letter.create(
		letter_id,
		"Your go-between",
		date,
		"A dynasty fades: %s" % f.family_name,
		body,
		&"host"
	)
	EventBus.letter_delivered.emit(letter)


# --- Names -------------------------------------------------------------------

func _kingdom_name_of(kid: String) -> String:
	var k: Kingdom = WorldData.get_kingdom(kid)
	return k.kingdom_name if k != null else kid


func _derive_family_name(head: Actor) -> String:
	# Very light touch — use the head's given name as a surname
	# stem. Good enough for the scaffolding. The UI can display
	# "House of Philon" without us inventing a full onomasticon.
	return "House of %s" % head.given_name


# --- Save / load -------------------------------------------------------------

func snapshot() -> Dictionary:
	var out: Dictionary = {}
	var fs: Array = []
	for f in families.values():
		fs.append(f.to_dict())
	out["families"] = fs
	return out


func restore(d: Dictionary) -> void:
	families.clear()
	for fd in d.get("families", []):
		var f: Family = Family.from_dict(fd)
		if f.id == &"":
			continue
		families[f.id] = f
