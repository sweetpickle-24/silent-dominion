extends Node
## Autoloaded as `Beats`. Scripted first-session narrative arc per §28.1.
##
## The game deliberately does not explain its systems — it presents a
## situation and lets the player discover the mechanic. This script is
## the situation generator. Each beat fires once, gated by time or a
## growth milestone, and drops a letter / event into the world.
##
## Beats are persistent. `_fired` is serialised so a player reloading
## mid-campaign doesn't receive the intro letter a second time.

var fired: Dictionary = {} # StringName beat_id -> true
var start_year: int = 0
var start_month: int = 0
var _primed: bool = false

# Timed beats keyed by (year_offset, month_offset). Month-granularity is
# enough — the narrative moments don't need to fire on a specific day.
const TIMED_BEATS: Array[Dictionary] = [
	{"id": &"intro_letter",       "year_off": 0,  "month_off": 0},
	{"id": &"week_courtship",     "year_off": 0,  "month_off": 0, "day_off": 7},
	{"id": &"month_surprise",     "year_off": 0,  "month_off": 1},
	{"id": &"month3_neighbour",   "year_off": 0,  "month_off": 3},
	{"id": &"year1_money",        "year_off": 1,  "month_off": 0},
	{"id": &"year3_contradiction","year_off": 3,  "month_off": 0},
	{"id": &"year5_mortality",    "year_off": 5,  "month_off": 0},
]


func _ready() -> void:
	# Run beat checks on every tick so reloads catch missed beats.
	GameClock.day_passed.connect(_on_day_passed)


# --- Tick -----------------------------------------------------------------

func _on_day_passed(y: int, m: int, d: int) -> void:
	_check_at(y, m, d)


## Force a beat sweep at the current clock — called by table.gd the
## moment the session enters the in_game state so the opening letter
## arrives on day 1 rather than waiting for the first day to tick.
func check_now() -> void:
	_check_at(GameClock.year, GameClock.month, GameClock.day)


func _check_at(y: int, m: int, d: int) -> void:
	if not Session.in_game:
		return
	if not _primed:
		start_year = y
		start_month = m
		_primed = true
	for beat in TIMED_BEATS:
		var id: StringName = beat.id
		if fired.has(id):
			continue
		if not _beat_is_due(beat, y, m, d):
			continue
		_fire_beat(id)


func _beat_is_due(beat: Dictionary, y: int, m: int, d: int) -> bool:
	var target_month: int = start_month + int(beat.get("month_off", 0))
	var target_year: int = start_year + int(beat.get("year_off", 0))
	# GameClock years are negative (BCE). Wrap month arithmetic.
	while target_month > 12:
		target_month -= 12
		target_year += 1
	var target_day: int = int(beat.get("day_off", 1))
	if y < target_year:
		return false
	if y == target_year and m < target_month:
		return false
	if y == target_year and m == target_month and d < target_day:
		return false
	return true


# --- Beat dispatch --------------------------------------------------------

func _fire_beat(id: StringName) -> void:
	match id:
		&"intro_letter":        _beat_intro_letter()
		&"week_courtship":      _beat_week_courtship()
		&"month_surprise":      _beat_month_surprise()
		&"month3_neighbour":    _beat_month3_neighbour()
		&"year1_money":         _beat_year1_money()
		&"year3_contradiction": _beat_year3_contradiction()
		&"year5_mortality":     _beat_year5_mortality()
	fired[id] = true


# --- Beats ----------------------------------------------------------------

func _beat_intro_letter() -> void:
	# Introduces the shape of the opening: who they are, where they
	# stand, what the first letter does. Pulls the most-promising
	# non-ruler actor in the starting region to name as the first
	# prospect. Falls back to a vaguer voice if no one fits.
	var anchor: Actor = _best_prospect_in_any_kingdom()
	var region_name: String = _kingdom_name_for(anchor.kingdom_id) if anchor != null else "this quarter"
	var prospect: String = anchor.display_name() if anchor != null else "a figure of the proper sort"

	var body: String = (
		"You will not know my name. You are not meant to. I write from a room a long way off, "
		+ "and the hand that carries this letter will burn it after you have read it.\n\n"
		+ "The work that will occupy your winters has already begun, though you have done nothing. "
		+ "I have been finding, for some months, the kind of person we can build something around — "
		+ "and in %s I believe I have one. I mean %s. They are not yours yet. They are barely even aware of us. "
		+ "But they are the shape we need.\n\n"
		+ "Begin with them. Watch first. Arrange an acquaintance. Let a small kindness be done for them "
		+ "through a third hand — never yours. Do not move quickly. We have all the time in the world; "
		+ "what we do not have is the chance to undo a mistake, because there are no mistakes small "
		+ "enough to be unrecorded.\n\n"
		+ "When you are ready, the table is yours. I will write again when your first work bears fruit."
	) % [region_name, prospect]

	_send(
		"Your predecessor, through a third hand",
		"A beginning",
		body,
		&"intro"
	)


func _beat_week_courtship() -> void:
	# A rival faction is circling our first host. Teaches: act early
	# or lose the prospect.
	var anchor: Actor = _best_prospect_in_any_kingdom()
	if anchor == null:
		return
	var who: String = anchor.display_name()
	var body: String = (
		"A man with a Corinthian accent has been buying %s's wine all week. Not cheaply; not quietly. "
		+ "He asks questions that do not belong in a wineshop — about %s's debts, their brother's "
		+ "marriage, their standing with the archon. I have not placed him in any house I know. "
		+ "Either he is a rival of ours, or he is acting for one.\n\n"
		+ "If we intend %s to be ours, we should not be the second hand they learn the weight of."
	) % [who, who, who]
	_send(
		"Your watcher in the quarter",
		"Someone else is asking after %s" % who,
		body,
		&"intel"
	)


func _beat_month_surprise() -> void:
	# The first host exercises agency. Teaches: hosts are not
	# instruments, they are collaborators with their own reasoning.
	var anchor: Actor = _best_prospect_in_any_kingdom()
	if anchor == null:
		return
	var who: String = anchor.display_name()
	var body: String = (
		"I arranged for %s to be offered the magistracy we discussed. They turned it down. "
		+ "Not loudly — a polite 'not this season' — but without asking my counsel, and without "
		+ "waiting for what I would have said next.\n\n"
		+ "It is worth remembering that our people have their own reasons. When we ask them to move, "
		+ "we are bargaining with them. We are not giving orders."
	) % who
	_send(
		"Your go-between",
		"%s has chosen their own course" % who,
		body,
		&"intel"
	)


func _beat_month3_neighbour() -> void:
	# Opens the door to a second host in a nearby kingdom. Teaches:
	# cultivate more than one, you are fragile at size 1.
	var anchor: Actor = _best_prospect_in_any_kingdom()
	if anchor == null:
		return
	var neighbour: String = ""
	for kid in WorldData.kingdoms.keys():
		var kid_s: String = String(kid)
		if kid_s != anchor.kingdom_id:
			neighbour = kid_s
			break
	if neighbour.is_empty():
		return
	var nname: String = _kingdom_name_for(neighbour)
	var body: String = (
		"There is a second figure worth cultivating, in %s. The circumstances are different — "
		+ "they are younger than %s, more ambitious, and their rise is not yet secured — "
		+ "but the shape of what we would do there is clearer than the shape of what we are doing here.\n\n"
		+ "I raise this not as urgency but as reminder. A network built on one name rests on that name. "
		+ "A network built on two begins to look like a network."
	) % [nname, anchor.display_name()]
	_send(
		"Your correspondent at the harbour",
		"An opportunity in %s" % nname,
		body,
		&"intel"
	)


func _beat_year1_money() -> void:
	# A financial request appears. Teaches: network funding vs purse,
	# discretion cost. If Finance has at least one house, route the
	# narrative through it.
	var houses: Array[BankingHouse] = Finance.active_houses()
	var via: String = "the merchant we keep on retainer"
	if houses.size() > 0:
		via = houses[0].display_name
	var body: String = (
		"A small matter has come up that will be best handled through silver. Two hundred coin, "
		+ "through %s, to an intermediary you will never need to meet — a carter in the east port "
		+ "with a door we want kept half-open.\n\n"
		+ "This is the first proper moving of money our young network will do. How we do it "
		+ "matters more than the doing. Direct payments leave the brightest traces. Payments "
		+ "that move through two hands are slower, a little more costly, and almost never remembered. "
		+ "Choose accordingly."
	) % via
	_send(
		"Your man of affairs",
		"Two hundred silver, for the east port",
		body,
		&"action"
	)


func _beat_year3_contradiction() -> void:
	# Introduces source integrity. Uses the highest-tenure operative
	# if there is one, otherwise generalises.
	var seasoned: OrgMember = null
	for m in Org.all_members():
		if m.burned:
			continue
		if m.tenure_days >= 90 and (seasoned == null or m.tenure_days > seasoned.tenure_days):
			seasoned = m
	var who: String = seasoned.display_name if seasoned != null else "one of our sources"

	var body: String = (
		"Two letters reached me this week that cannot both be true.\n\n"
		+ "%s writes that the archon in their city is failing — that he has not held court in a month, "
		+ "that his chancellor is running affairs in his name. The public news, by different hands, "
		+ "says the archon held an audience with a foreign envoy yesterday and rode out the same "
		+ "afternoon to inspect the garrison.\n\n"
		+ "One of these accounts is wrong. It may be innocent — a stale report, a confusion of dates. "
		+ "It may not. The tools to learn which are in your hands: cross-reference against the public "
		+ "record, audit the source, or send a second pair of eyes over the same ground.\n\n"
		+ "Do not act on either account until you know which one is lying."
	) % who
	_send(
		"Your archivist",
		"Two reports that cannot both stand",
		body,
		&"intel"
	)


func _beat_year5_mortality() -> void:
	# Succession moment. Whether or not anyone has actually died, the
	# letter raises the question, because the system is about to start
	# being able to kill hosts through the normal mortality model.
	var body: String = (
		"I write while I am still able to write. I am not unwell; I am not in trouble; but I am older "
		+ "than my use to you, and I have lived long enough to have watched every network I respected "
		+ "be broken by someone mistaking a rider for a road.\n\n"
		+ "Begin, this year, to think of your hands as mortal. Cultivate the children of your coordinators "
		+ "as carefully as you cultivated their parents. Keep a second host in every city that matters. "
		+ "When a name on your roster carries work no one else can do, you do not have a network — "
		+ "you have a single point of failure that smiles."
	)
	_send(
		"Your predecessor, through a third hand",
		"On the matter of who succeeds whom",
		body,
		&"intro"
	)


# --- Helpers --------------------------------------------------------------

func _send(sender: String, subject: String, body: String, kind: StringName) -> void:
	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var letter: Letter = Letter.create(
		StringName("beat_%d" % Time.get_ticks_msec()),
		sender,
		date,
		subject,
		body,
		kind,
	)
	EventBus.letter_delivered.emit(letter)


func _kingdom_name_for(kid: String) -> String:
	var k: Kingdom = WorldData.get_kingdom(kid)
	return k.kingdom_name if k != null else kid


func _best_prospect_in_any_kingdom() -> Actor:
	# Pick an actor we'd plausibly want as a first host: non-ruler,
	# alive, with decent ambition and not extreme paranoia. Skips
	# actors who are already OrgMembers (we're the old hand here).
	var best: Actor = null
	var best_score: int = -1
	for a in Actors.all_actors():
		if not a.is_alive() or a.role == Actor.Role.RULER:
			continue
		if Org.is_actor_member(a.id):
			continue
		var score: int = a.ambition + a.intellect + (100 - a.paranoia) + a.charisma
		if score > best_score:
			best = a
			best_score = score
	return best


# --- Save / load -----------------------------------------------------------

func snapshot() -> Dictionary:
	return {
		"fired": fired.duplicate(true),
		"start_year": start_year,
		"start_month": start_month,
		"primed": _primed,
	}


func restore(d: Dictionary) -> void:
	fired.clear()
	var f: Variant = d.get("fired", {})
	if f is Dictionary:
		for k in f:
			fired[StringName(String(k))] = true
	start_year = int(d.get("start_year", 0))
	start_month = int(d.get("start_month", 0))
	_primed = bool(d.get("primed", start_year != 0 or start_month != 0))
