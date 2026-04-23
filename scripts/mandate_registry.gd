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

# Phase tags for the remaining categories. The registry matches
# these against world signals; the specifics are documented next to
# each case branch in `_on_action_resolved` / `_on_month_passed`.
const ELEVATION_PHASE_CULTIVATE:       StringName = &"elev_cultivate"
const ELEVATION_PHASE_SEAT:            StringName = &"elev_seat"
const IDEOLOGICAL_PHASE_SEED:          StringName = &"ideo_seed"
const IDEOLOGICAL_PHASE_ENTRENCH:      StringName = &"ideo_entrench"
const DESTAB_PHASE_INCITE:             StringName = &"destab_incite"
const DESTAB_PHASE_FRACTURE:           StringName = &"destab_fracture"
const COUNTER_PHASE_OBSERVE:           StringName = &"counter_observe"
const COUNTER_PHASE_NEUTRALISE:        StringName = &"counter_neutralise"
const TERRITORIAL_PHASE_PRETEXT:       StringName = &"terr_pretext"
const TERRITORIAL_PHASE_CEDE:          StringName = &"terr_cede"
const INSTITUTIONAL_PHASE_ENDOW:       StringName = &"inst_endow"
const INSTITUTIONAL_PHASE_ENTRENCH:    StringName = &"inst_entrench"
const SUCCESSION_PHASE_GROOM:          StringName = &"succ_groom"
const SUCCESSION_PHASE_SEAT:           StringName = &"succ_seat"
const COLLAPSE_PHASE_PROP:             StringName = &"collapse_prop"
const COLLAPSE_PHASE_HOLD:             StringName = &"collapse_hold"

const REMOVAL_DEADLINE_DAYS: int = 36 * 30   # ~3 years
const SURVIVAL_GO_COLD_MONTHS: int = 12
const SURVIVAL_OUTLAST_MONTHS: int = 24
const SURVIVAL_EXPOSURE_THRESHOLD: float = 15.0

# Generic deadline for the broader categories. Kept long: these are
# century-scale vectors and the player must be allowed to wait out
# the board.
const LONG_CATEGORY_DEADLINE_DAYS: int = 60 * 30   # ~5 years

# Emergent offer thresholds.
const EMERGENT_REMOVAL_AMBITION: int = 80
const EMERGENT_REMOVAL_RUTHLESSNESS: int = 70
const EMERGENT_OFFER_COOLDOWN_MONTHS: int = 6
const EMERGENT_IDEOLOGICAL_DEPTH: int = 70
const EMERGENT_DESTAB_RIVAL_HITS: int = 3
const EMERGENT_ELEVATION_RELATIONSHIP: int = 70

# Active + archived mandates, id -> Mandate.
var mandates: Dictionary = {}

# Last month we offered any emergent mandate. Gates repeat offers.
var _last_emergent_month: int = -9999
# Per-category last-offered month so each category respects its own
# cooldown rather than sharing a single global window.
var _last_emergent_by_category: Dictionary = {}
# Transient counters for rivals' visible-ops per kingdom, used to
# fire DESTABILISATION offers when a rival crosses the rate threshold.
var _rival_hits_by_kingdom: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	DevLogger.write("Mandates: ready")
	_rng.randomize()
	EventBus.action_resolved.connect(_on_action_resolved)
	EventBus.actor_died.connect(_on_actor_died)
	GameClock.month_passed.connect(_on_month_passed)
	if Entities.has_signal("entity_added"):
		Entities.entity_added.connect(_on_entity_added)
	if Rivals.has_signal("society_acted"):
		Rivals.society_acted.connect(_on_rival_acted)


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


# --- Generic offer ----------------------------------------------------------

## Category-agnostic entry point. Dispatches to per-category template
## builders. `payload` conveys the target handle the category needs —
## one of `target_actor_id`, `target_kingdom_id`, `target_society_id`.
## Returns the id of the created mandate, or &"" if it couldn't be.
func offer(category: int, payload: Dictionary = {}, emergent: bool = false) -> StringName:
	match category:
		Mandate.Category.REMOVAL:
			return offer_removal_mandate(StringName(String(payload.get("target_actor_id", ""))), emergent)
		Mandate.Category.SURVIVAL:
			return offer_survival_mandate(String(payload.get("note", "")))
		Mandate.Category.ELEVATION:
			return _offer_templated(Mandate.Category.ELEVATION, payload, emergent)
		Mandate.Category.IDEOLOGICAL:
			return _offer_templated(Mandate.Category.IDEOLOGICAL, payload, emergent)
		Mandate.Category.DESTABILISATION:
			return _offer_templated(Mandate.Category.DESTABILISATION, payload, emergent)
		Mandate.Category.COUNTER_SOCIETY:
			return _offer_templated(Mandate.Category.COUNTER_SOCIETY, payload, emergent)
		Mandate.Category.TERRITORIAL:
			return _offer_templated(Mandate.Category.TERRITORIAL, payload, emergent)
		Mandate.Category.INSTITUTIONAL:
			return _offer_templated(Mandate.Category.INSTITUTIONAL, payload, emergent)
		Mandate.Category.SUCCESSION:
			return _offer_templated(Mandate.Category.SUCCESSION, payload, emergent)
		Mandate.Category.COLLAPSE_PREVENTION:
			return _offer_templated(Mandate.Category.COLLAPSE_PREVENTION, payload, emergent)
	return &""


## §C5 convenience entry-point used by the immortal dialogue overlay.
## A dialogue outcome that says "open a destabilisation mandate, tied
## to the Pyre" goes through here. The caller passes a category name
## (string, to survive JSON), an optional kingdom, and the immortal id
## so the mandate's offer letter can cite the proposer.
func offer_from_dialogue(category_name: String, kingdom_id: String, immortal_id: StringName) -> StringName:
	var cat: int = int(Mandate._category_from_string(category_name.to_upper()))
	var payload: Dictionary = {}
	if kingdom_id != "":
		payload["target_kingdom_id"] = kingdom_id
	var im: OtherImmortal = Immortals.get_by_id(immortal_id)
	if im != null:
		payload["target_society_id"] = String(im.society_id)
	return offer(cat, payload, true)


func _offer_templated(category: int, payload: Dictionary, emergent: bool) -> StringName:
	var tpl: Dictionary = _template_for(category, payload)
	if tpl.is_empty():
		return &""
	var man: Mandate = Mandate.new()
	man.id               = StringName("%s_%d_%d" % [
		String(tpl.get("id_prefix", "mandate")),
		GameClock.absolute_day(), _rng.randi()
	])
	man.category         = category as Mandate.Category
	man.status           = Mandate.Status.OFFERED
	man.emergent         = emergent
	man.headline         = String(tpl.get("headline", ""))
	man.blurb            = String(tpl.get("blurb", ""))
	man.target_actor_id  = StringName(String(payload.get("target_actor_id", "")))
	man.target_kingdom_id = String(payload.get("target_kingdom_id", ""))
	man.target_society_id = StringName(String(payload.get("target_society_id", "")))
	man.started_abs_day  = GameClock.absolute_day()
	man.deadline_abs_day = GameClock.absolute_day() + LONG_CATEGORY_DEADLINE_DAYS
	man.phases           = tpl.get("phases", []).duplicate(true)
	mandates[man.id] = man
	mandate_offered.emit(man.id)
	_send_offer_letter(man)
	accept(man.id)
	return man.id


func _template_for(category: int, payload: Dictionary) -> Dictionary:
	var actor: Actor = Actors.get_actor(StringName(String(payload.get("target_actor_id", ""))))
	var kingdom: Kingdom = WorldData.get_kingdom(String(payload.get("target_kingdom_id", "")))
	var society_id: String = String(payload.get("target_society_id", ""))
	var actor_name: String = actor.display_name if actor != null else "the target"
	var kingdom_name: String = kingdom.kingdom_name if kingdom != null else "the realm"

	match category:
		Mandate.Category.ELEVATION:
			return {
				"id_prefix": "elevation",
				"headline": "Elevate %s" % actor_name,
				"blurb": "A line to lift. %s has the competence and the reach; what they lack is a seat. The mandate is to put them nearer the centre of power in %s." % [actor_name, kingdom_name],
				"phases": [
					_phase("Cultivate the line", "Cultivate or bribe two of their patrons to clear the path.",
						3, ELEVATION_PHASE_CULTIVATE),
					_phase("Seat them higher", "Manoeuvre them into a named office — minister, magistrate, court position.",
						1, ELEVATION_PHASE_SEAT),
				],
			}
		Mandate.Category.IDEOLOGICAL:
			return {
				"id_prefix": "ideological",
				"headline": "Seed a doctrine in %s" % kingdom_name,
				"blurb": "An idea worth carrying. Establish a working religion or reformist line in %s and entrench it past the next ruler." % kingdom_name,
				"phases": [
					_phase("Seed the doctrine", "Spread the doctrine into the province capital twice.",
						2, IDEOLOGICAL_PHASE_SEED),
					_phase("Entrench the doctrine", "Found a monastery or academy to carry it past a single reign.",
						1, IDEOLOGICAL_PHASE_ENTRENCH),
				],
			}
		Mandate.Category.DESTABILISATION:
			return {
				"id_prefix": "destab",
				"headline": "Fracture %s" % kingdom_name,
				"blurb": "%s has grown coherent past the point we can steer. The mandate is to soften that coherence — unrest, factionalism, a quieter court." % kingdom_name,
				"phases": [
					_phase("Incite unrest", "Run three successful incite-unrest or rumour actions in %s." % kingdom_name,
						3, DESTAB_PHASE_INCITE),
					_phase("Fracture the court", "Elevate a dissident or bleed the treasury until the ruler buckles.",
						1, DESTAB_PHASE_FRACTURE),
				],
			}
		Mandate.Category.COUNTER_SOCIETY:
			var soc_label: String = society_id if society_id != "" else "the rival"
			return {
				"id_prefix": "counter",
				"headline": "Blunt %s" % soc_label,
				"blurb": "%s has shown enough hand. The mandate is to observe, catalogue, and cut off a limb — at minimum one of their operatives, identified and neutralised." % soc_label,
				"phases": [
					_phase("Catalogue them", "Observe the rival's work twice — run observe or sweep_for_rivals.",
						2, COUNTER_PHASE_OBSERVE),
					_phase("Neutralise a hand", "Neutralise a named rival operative.",
						1, COUNTER_PHASE_NEUTRALISE),
				],
			}
		Mandate.Category.TERRITORIAL:
			return {
				"id_prefix": "territorial",
				"headline": "Redraw the border of %s" % kingdom_name,
				"blurb": "A border worth moving. The mandate is to engineer a shift — pretext for war, puppet ruler, ceded province.",
				"phases": [
					_phase("Engineer a pretext", "Manufacture a casus belli in %s (incite / rumour / false-flag)." % kingdom_name,
						2, TERRITORIAL_PHASE_PRETEXT),
					_phase("See the cession", "Province must change hands — war outcome or treaty.",
						1, TERRITORIAL_PHASE_CEDE),
				],
			}
		Mandate.Category.INSTITUTIONAL:
			return {
				"id_prefix": "institutional",
				"headline": "Entrench an institution in %s" % kingdom_name,
				"blurb": "A chosen institution — banking house, academy, guild — must outlive the current ruler and bind the next. The mandate funds the endowment and the second generation.",
				"phases": [
					_phase("Endow the institution", "Found or endow two owned entities in %s." % kingdom_name,
						2, INSTITUTIONAL_PHASE_ENDOW),
					_phase("Entrench them past a succession", "Keep the entities healthy for at least twelve months after a ruler change.",
						12, INSTITUTIONAL_PHASE_ENTRENCH),
				],
			}
		Mandate.Category.SUCCESSION:
			return {
				"id_prefix": "succession",
				"headline": "Put %s on the throne of %s" % [actor_name, kingdom_name],
				"blurb": "A specific heir, a specific seat. The mandate is to clear the path and see them crowned.",
				"phases": [
					_phase("Groom the heir", "Cultivate the target twice. Their relationship must be high before the throne opens.",
						2, SUCCESSION_PHASE_GROOM),
					_phase("Seat them", "The target must become ruler of the target kingdom — by natural, arranged, or violent succession.",
						1, SUCCESSION_PHASE_SEAT),
				],
			}
		Mandate.Category.COLLAPSE_PREVENTION:
			return {
				"id_prefix": "collapse",
				"headline": "Hold %s together" % kingdom_name,
				"blurb": "%s is running out of runway. The mandate is to keep the kingdom alive long enough to matter — stabilise its treasury, reduce unrest, preserve the ruler." % kingdom_name,
				"phases": [
					_phase("Prop the crown", "Three successful cultivate / bribe actions targeting the ruler or their ministers.",
						3, COLLAPSE_PHASE_PROP),
					_phase("Hold the line", "Keep the treasury out of BROKE/INDEBTED for twelve months.",
						12, COLLAPSE_PHASE_HOLD),
				],
			}
	return {}


func _phase(name: String, description: String, target: int, condition: StringName) -> Dictionary:
	return {
		"name": name,
		"description": description,
		"progress": 0, "target": target,
		"state": "pending",
		"condition": String(condition),
	}


# --- Offering ---------------------------------------------------------------

## Player-initiated: craft a removal mandate against an actor they
## have already identified. Returns the mandate id if created, &""
## if the target is invalid (dead, already targeted, etc).
func offer_removal_mandate(target_actor_id: StringName, emergent: bool = false) -> StringName:
	var a: Actor = Actors.get_actor(target_actor_id)
	if a == null or not a.is_alive():
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
			String(ELEVATION_PHASE_CULTIVATE):
				if action_id in [&"cultivate", &"bribe_direct", &"bribe_gift"]:
					if _actor_shares_kingdom(target_id, m.target_actor_id):
						_bump_phase(m, 1)
			String(ELEVATION_PHASE_SEAT):
				if action_id == &"plant_idea" and target_id == String(m.target_actor_id):
					_bump_phase(m, 1)
			String(IDEOLOGICAL_PHASE_SEED):
				if action_id in [&"plant_idea", &"seed_rumour"]:
					var tk: String = _kingdom_of_actor(target_id)
					if tk == m.target_kingdom_id:
						_bump_phase(m, 1)
			String(DESTAB_PHASE_INCITE):
				if action_id in [&"seed_rumour", &"fan_border", &"host_agitate", &"bribe_retainer"]:
					var tk2: String = _kingdom_of_actor(target_id)
					if tk2 == m.target_kingdom_id:
						_bump_phase(m, 1)
			String(DESTAB_PHASE_FRACTURE):
				if action_id in [&"bribe_direct", &"quiet_plot"]:
					if _kingdom_of_actor(target_id) == m.target_kingdom_id:
						_bump_phase(m, 1)
			String(COUNTER_PHASE_OBSERVE):
				if action_id in [&"observe", &"sweep_for_rivals"]:
					_bump_phase(m, 1)
			String(COUNTER_PHASE_NEUTRALISE):
				if action_id in [&"neutralize_rival_operative", &"quiet_plot"]:
					_bump_phase(m, 1)
			String(TERRITORIAL_PHASE_PRETEXT):
				if action_id in [&"seed_rumour", &"fan_border", &"host_agitate", &"false_flag_operation"]:
					if _kingdom_of_actor(target_id) == m.target_kingdom_id:
						_bump_phase(m, 1)
			String(SUCCESSION_PHASE_GROOM):
				if action_id in [&"cultivate", &"bribe_direct"] and target_id == String(m.target_actor_id):
					_bump_phase(m, 1)
			String(COLLAPSE_PHASE_PROP):
				if action_id in [&"cultivate", &"bribe_direct", &"bribe_retainer"]:
					if _kingdom_of_actor(target_id) == m.target_kingdom_id:
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
		match cond:
			String(SURVIVAL_PHASE_GO_COLD), String(SURVIVAL_PHASE_OUTLAST):
				if Exposure.value <= SURVIVAL_EXPOSURE_THRESHOLD:
					_bump_phase(m, 1)
				else:
					_fail_mandate(m, "Exposure ran loud. The vow is broken.")
			String(INSTITUTIONAL_PHASE_ENTRENCH):
				if _entities_healthy_in(m.target_kingdom_id):
					_bump_phase(m, 1)
			String(COLLAPSE_PHASE_HOLD):
				if _treasury_solvent(m.target_kingdom_id):
					_bump_phase(m, 1)
				else:
					# Streak breaks on an INDEBTED/BROKE month — reset.
					phase["progress"] = 0
					m.phases[m.current_phase] = phase
			String(TERRITORIAL_PHASE_CEDE):
				if _province_changed_hands(m.target_kingdom_id):
					_bump_phase(m, 999, true)
			String(SUCCESSION_PHASE_SEAT):
				if _actor_is_ruler(m.target_actor_id, m.target_kingdom_id):
					_bump_phase(m, 999, true)
		# Deadline check.
		if m.deadline_abs_day >= 0 and GameClock.absolute_day() >= m.deadline_abs_day:
			_fail_mandate(m, "The window has closed.")
	_maybe_offer_emergent()


func _on_rival_acted(_society_id: StringName, op: Dictionary) -> void:
	var kid: String = String(op.get("kingdom_id", ""))
	if kid == "":
		return
	_rival_hits_by_kingdom[kid] = int(_rival_hits_by_kingdom.get(kid, 0)) + 1


func _on_entity_added(id: StringName) -> void:
	var e: OwnedEntity = Entities.get_entity(id)
	if e == null:
		return
	for m in mandates.values():
		if m.status != Mandate.Status.ACTIVE:
			continue
		var phase: Dictionary = m.active_phase()
		if phase.is_empty():
			continue
		var cond: String = String(phase.get("condition", ""))
		match cond:
			String(IDEOLOGICAL_PHASE_ENTRENCH):
				if e.home_kingdom == m.target_kingdom_id \
						and e.kind in [OwnedEntity.Kind.ACADEMY, OwnedEntity.Kind.MONASTERY]:
					_bump_phase(m, 1)
			String(INSTITUTIONAL_PHASE_ENDOW):
				if e.home_kingdom == m.target_kingdom_id:
					_bump_phase(m, 1)


func _entities_healthy_in(kingdom_id: String) -> bool:
	if kingdom_id == "":
		return false
	var count_ok: int = 0
	for e in Entities.active_entities():
		if e.home_kingdom != kingdom_id:
			continue
		if e.control_live() and e.corruption < OwnedEntity.CORRUPTION_LEAK_THRESHOLD:
			count_ok += 1
	return count_ok >= 2


func _treasury_solvent(kingdom_id: String) -> bool:
	var k: Kingdom = WorldData.get_kingdom(kingdom_id)
	if k == null:
		return false
	return int(k.treasury_condition) < int(Kingdom.TreasuryCondition.INDEBTED)


func _province_changed_hands(kingdom_id: String) -> bool:
	# Placeholder — BattleResolver emits actor-driven signals but not
	# a dedicated "province flipped" one yet. For now we rely on the
	# deadline to force closure; this hook lets us wire a proper
	# border-change signal in later without a mandate-registry change.
	if kingdom_id == "":
		return false
	return false


func _actor_is_ruler(actor_id: StringName, kingdom_id: String) -> bool:
	if actor_id == &"":
		return false
	var ruler: Actor = Actors.ruler_of(kingdom_id)
	return ruler != null and ruler.id == actor_id


func _maybe_offer_emergent() -> void:
	var now_month: int = GameClock.year * 12 + GameClock.month
	# One emergent per month at most — even across categories,
	# otherwise the inbox floods. Global gate stays; per-category
	# cooldown is checked per branch.
	if now_month - _last_emergent_month < EMERGENT_OFFER_COOLDOWN_MONTHS:
		return
	# Evaluate categories in a rotating-priority order. First hit wins.
	var ordered: Array = [
		Mandate.Category.REMOVAL,
		Mandate.Category.SURVIVAL,
		Mandate.Category.IDEOLOGICAL,
		Mandate.Category.DESTABILISATION,
		Mandate.Category.COUNTER_SOCIETY,
		Mandate.Category.ELEVATION,
		Mandate.Category.TERRITORIAL,
		Mandate.Category.INSTITUTIONAL,
		Mandate.Category.SUCCESSION,
		Mandate.Category.COLLAPSE_PREVENTION,
	]
	for cat in ordered:
		if not _category_cooldown_ready(cat, now_month):
			continue
		var fired: bool = false
		match cat:
			Mandate.Category.REMOVAL:            fired = _try_emergent_removal()
			Mandate.Category.SURVIVAL:           fired = _try_emergent_survival()
			Mandate.Category.IDEOLOGICAL:        fired = _try_emergent_ideological()
			Mandate.Category.DESTABILISATION:    fired = _try_emergent_destabilisation()
			Mandate.Category.COUNTER_SOCIETY:    fired = _try_emergent_counter_society()
			Mandate.Category.ELEVATION:          fired = _try_emergent_elevation()
			Mandate.Category.TERRITORIAL:        fired = _try_emergent_territorial()
			Mandate.Category.INSTITUTIONAL:      fired = _try_emergent_institutional()
			Mandate.Category.SUCCESSION:         fired = _try_emergent_succession()
			Mandate.Category.COLLAPSE_PREVENTION: fired = _try_emergent_collapse()
		if fired:
			_last_emergent_month = now_month
			_last_emergent_by_category[cat] = now_month
			return


func _category_cooldown_ready(cat: int, now_month: int) -> bool:
	var last: int = int(_last_emergent_by_category.get(cat, -9999))
	return now_month - last >= EMERGENT_OFFER_COOLDOWN_MONTHS


func _category_active(cat: int) -> bool:
	for m in mandates.values():
		if m.category == cat and not m.is_terminal():
			return true
	return false


func _try_emergent_removal() -> bool:
	var candidates: Array[Actor] = []
	for a in Actors.all_actors():
		if not a.is_alive():
			continue
		if a.role != Actor.Role.RULER:
			continue
		if a.ambition < EMERGENT_REMOVAL_AMBITION:
			continue
		if a.ruthlessness < EMERGENT_REMOVAL_RUTHLESSNESS:
			continue
		if _already_targeted(a.id):
			continue
		candidates.append(a)
	if candidates.is_empty():
		return false
	var pick: Actor = candidates[_rng.randi_range(0, candidates.size() - 1)]
	return offer_removal_mandate(pick.id, true) != &""


func _try_emergent_survival() -> bool:
	# Offer SURVIVAL when shadow awareness has reached INSTITUTIONAL
	# tier in any kingdom. One running at a time is plenty.
	if _category_active(Mandate.Category.SURVIVAL):
		return false
	for kid in Shadow.awareness_heat.keys():
		if Shadow.awareness_tier_in(String(kid)) >= Shadow.TIER_INSTITUTIONAL:
			return offer_survival_mandate("Awareness of the work has crystallised in %s. Go dark before it institutionalises further." % String(kid)) != &""
	return false


func _try_emergent_ideological() -> bool:
	# A religion whose popular depth crosses EMERGENT_IDEOLOGICAL_DEPTH
	# in its epicentre kingdom. Epicentre = kingdom of the province
	# with the highest presence share for that religion.
	for r in Religions.all_religions():
		if r.popular_depth < EMERGENT_IDEOLOGICAL_DEPTH:
			continue
		var kid: String = _epicentre_kingdom_of(r)
		if kid == "":
			continue
		if _ideological_already_targeting(kid):
			continue
		var payload: Dictionary = {
			"target_kingdom_id": kid,
		}
		if offer(Mandate.Category.IDEOLOGICAL, payload, true) != &"":
			return true
	return false


func _try_emergent_destabilisation() -> bool:
	# _rival_hits_by_kingdom is ticked by _on_rival_op_resolved when
	# that hook is wired up. We also read the cheap proxy: recent
	# rival ops from Rivals.recent_ops_in.
	for kid in WorldData.kingdoms.keys():
		var hits: int = int(_rival_hits_by_kingdom.get(kid, 0))
		if hits < EMERGENT_DESTAB_RIVAL_HITS and Rivals.recent_ops_in(String(kid), 180).size() < EMERGENT_DESTAB_RIVAL_HITS:
			continue
		if _destab_already_targeting(String(kid)):
			continue
		var payload: Dictionary = {
			"target_kingdom_id": String(kid),
		}
		if offer(Mandate.Category.DESTABILISATION, payload, true) != &"":
			_rival_hits_by_kingdom[kid] = 0
			return true
	return false


func _try_emergent_counter_society() -> bool:
	for sid in Fingerprints.society_confirmation.keys():
		var score: int = int(Fingerprints.society_confirmation.get(sid, 0))
		if score < 100:
			continue
		if _counter_already_targeting(StringName(sid)):
			continue
		var payload: Dictionary = {
			"target_society_id": StringName(sid),
		}
		if offer(Mandate.Category.COUNTER_SOCIETY, payload, true) != &"":
			return true
	return false


func _try_emergent_elevation() -> bool:
	# A cultivated actor whose relationship crosses the bar and who
	# sits in a named family — good seed for the elevation track.
	for a in Actors.all_actors():
		if not a.is_alive():
			continue
		if a.relationship < EMERGENT_ELEVATION_RELATIONSHIP:
			continue
		if a.family_id == &"":
			continue
		if a.role == Actor.Role.RULER:
			continue
		if _elevation_already_targeting(a.id):
			continue
		var payload: Dictionary = {
			"target_actor_id": String(a.id),
			"target_kingdom_id": a.kingdom_id,
		}
		if offer(Mandate.Category.ELEVATION, payload, true) != &"":
			return true
	return false


func _try_emergent_territorial() -> bool:
	# Kingdom whose average unrest tips past "restless" — a border
	# soft enough to push.
	for kid in WorldData.kingdoms.keys():
		var avg: float = _avg_unrest(String(kid))
		if avg < 40.0:
			continue
		if _territorial_already_targeting(String(kid)):
			continue
		var payload: Dictionary = { "target_kingdom_id": String(kid) }
		if offer(Mandate.Category.TERRITORIAL, payload, true) != &"":
			return true
	return false


func _try_emergent_institutional() -> bool:
	# Player owns 2+ healthy entities in a kingdom — the conditions
	# are there to entrench an institution past a succession.
	var by_kid: Dictionary = {}
	for e in Entities.active_entities():
		if not e.control_live():
			continue
		if e.corruption >= OwnedEntity.CORRUPTION_LEAK_THRESHOLD:
			continue
		var k: String = e.home_kingdom
		by_kid[k] = int(by_kid.get(k, 0)) + 1
	for kid in by_kid.keys():
		if int(by_kid[kid]) < 2:
			continue
		if _institutional_already_targeting(String(kid)):
			continue
		var payload: Dictionary = { "target_kingdom_id": String(kid) }
		if offer(Mandate.Category.INSTITUTIONAL, payload, true) != &"":
			return true
	return false


func _try_emergent_succession() -> bool:
	# Ruler is old; one of the player's cultivated actors is a
	# plausible replacement. "Plausible" = an HEIR or ADVISOR with
	# high relationship.
	for kid in WorldData.kingdoms.keys():
		var ruler: Actor = Actors.ruler_of(String(kid))
		if ruler == null:
			continue
		if ruler.age < 55:
			continue
		var heir: Actor = _best_succession_candidate_in(String(kid))
		if heir == null:
			continue
		if _succession_already_targeting(heir.id):
			continue
		var payload: Dictionary = {
			"target_actor_id": String(heir.id),
			"target_kingdom_id": String(kid),
		}
		if offer(Mandate.Category.SUCCESSION, payload, true) != &"":
			return true
	return false


func _try_emergent_collapse() -> bool:
	# A kingdom in INDEBTED or BROKE — hard to recover but pivotal.
	for kid in WorldData.kingdoms.keys():
		var k: Kingdom = WorldData.get_kingdom(String(kid))
		if k == null:
			continue
		if int(k.treasury_condition) < int(Kingdom.TreasuryCondition.INDEBTED):
			continue
		if _collapse_already_targeting(String(kid)):
			continue
		var payload: Dictionary = { "target_kingdom_id": String(kid) }
		if offer(Mandate.Category.COLLAPSE_PREVENTION, payload, true) != &"":
			return true
	return false


# --- Emergent helpers --------------------------------------------------------

func _epicentre_kingdom_of(r: Religion) -> String:
	var best_share: int = 0
	var best_pid: String = ""
	for pid in r.presence.keys():
		var share: int = int(r.presence[pid])
		if share > best_share:
			best_share = share
			best_pid = String(pid)
	if best_pid == "":
		return ""
	var p: Province = WorldData.get_province(best_pid)
	return p.owning_kingdom if p != null else ""


func _avg_unrest(kid: String) -> float:
	var provs: Array = WorldData.get_provinces_of(kid)
	if provs.is_empty():
		return 0.0
	var sum: int = 0
	for p in provs:
		sum += int(p.unrest)
	return float(sum) / float(provs.size())


func _best_succession_candidate_in(kid: String) -> Actor:
	var best: Actor = null
	for a in Actors.all_actors():
		if not a.is_alive() or a.kingdom_id != kid:
			continue
		if a.role != Actor.Role.HEIR and a.role != Actor.Role.ADVISOR:
			continue
		if a.relationship < EMERGENT_ELEVATION_RELATIONSHIP:
			continue
		if best == null or a.relationship > best.relationship:
			best = a
	return best


func _ideological_already_targeting(kid: String) -> bool:
	return _category_targeting_kingdom(Mandate.Category.IDEOLOGICAL, kid)


func _destab_already_targeting(kid: String) -> bool:
	return _category_targeting_kingdom(Mandate.Category.DESTABILISATION, kid)


func _territorial_already_targeting(kid: String) -> bool:
	return _category_targeting_kingdom(Mandate.Category.TERRITORIAL, kid)


func _institutional_already_targeting(kid: String) -> bool:
	return _category_targeting_kingdom(Mandate.Category.INSTITUTIONAL, kid)


func _collapse_already_targeting(kid: String) -> bool:
	return _category_targeting_kingdom(Mandate.Category.COLLAPSE_PREVENTION, kid)


func _elevation_already_targeting(aid: StringName) -> bool:
	for m in mandates.values():
		if m.category == Mandate.Category.ELEVATION and m.target_actor_id == aid and not m.is_terminal():
			return true
	return false


func _succession_already_targeting(aid: StringName) -> bool:
	for m in mandates.values():
		if m.category == Mandate.Category.SUCCESSION and m.target_actor_id == aid and not m.is_terminal():
			return true
	return false


func _counter_already_targeting(sid: StringName) -> bool:
	for m in mandates.values():
		if m.category == Mandate.Category.COUNTER_SOCIETY and m.target_society_id == sid and not m.is_terminal():
			return true
	return false


func _category_targeting_kingdom(cat: int, kid: String) -> bool:
	for m in mandates.values():
		if m.category == cat and m.target_kingdom_id == kid and not m.is_terminal():
			return true
	return false


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


func _kingdom_of_actor(a_id: String) -> String:
	var a: Actor = Actors.get_actor(StringName(a_id))
	return a.kingdom_id if a != null else ""


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
		OrgRoles.sender_line(OrgRoles.CHIEF_OF_MANDATES),
		GameDate.today(),
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
		"mandates":                  arr,
		"_last_emergent_month":      _last_emergent_month,
		"_last_emergent_by_category": _last_emergent_by_category.duplicate(),
		"_rival_hits_by_kingdom":    _rival_hits_by_kingdom.duplicate(),
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
	var le_raw: Variant = d.get("_last_emergent_by_category", {})
	_last_emergent_by_category = (le_raw as Dictionary).duplicate() if le_raw is Dictionary else {}
	var rh_raw: Variant = d.get("_rival_hits_by_kingdom", {})
	_rival_hits_by_kingdom = (rh_raw as Dictionary).duplicate() if rh_raw is Dictionary else {}
