class_name Treaty
extends Node

const _LoggerScript := preload("res://scripts/core/logger.gd")
const _LOG_DEBUG: int = _LoggerScript.Level.DEBUG

var _event_bus: Node
var _logger: Node
var _time_keeper: Node
var _immortal_registry: Node

var _proposals: Dictionary = {}     # StringName proposal_id -> TreatyProposal
var _treaties: Dictionary = {}      # StringName treaty_id -> TreatyRecord
var _reputations: Dictionary = {}   # StringName immortal_id -> ReputationRecord
var _next_proposal_seq: int = 1
var _next_treaty_seq: int = 1


func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_logger = get_node("/root/Logger")
	_time_keeper = get_node("/root/TimeKeeper")
	_immortal_registry = get_node("/root/ImmortalRegistry")
	_event_bus.subscribe(
		preload("res://scripts/data/events/game_day_ticked_event.gd"),
		Callable(self, "_on_game_day_ticked"),
		300, &"", EndOfTickPhases.TREATY,
	)
	var save_system: Node = get_node("/root/SaveSystem")
	save_system.register_state_handlers(
		&"treaty_state",
		Callable(self, "snapshot_state"),
		Callable(self, "apply_state"),
	)
	_logger.info(LogChannels.TREATY, "Treaty mechanic ready")


# --- Public API ---

func propose_treaty(proposer_id: StringName, counterparty_id: StringName, primitives: Array[TreatyPrimitive], day: int = -1) -> TreatyProposal:
	if day < 0:
		day = _time_keeper.current_day
	var proposal := TreatyProposal.new()
	proposal.id = _generate_proposal_id()
	proposal.proposer_immortal_id = proposer_id
	proposal.counterparty_immortal_id = counterparty_id
	var cp_immortal: ImmortalRecord = _immortal_registry.get_immortal(counterparty_id)
	if cp_immortal != null:
		proposal.counterparty_society_id = cp_immortal.society_id
	proposal.primitives = primitives
	proposal.stage = &"negotiation"
	proposal.drafted_at_day = day
	proposal.history.append({
		"round": 1, "action": "proposed", "day": day,
		"by": proposer_id, "primitives_snapshot": _snapshot_primitives(primitives),
	})
	_proposals[proposal.id] = proposal
	var event := TreatyProposedEvent.new()
	event.proposal_id = proposal.id
	event.proposer_immortal_id = proposer_id
	event.counterparty_immortal_id = counterparty_id
	event.day = day
	_event_bus.dispatch(event)
	_logger.info(LogChannels.TREATY, "Treaty proposed", {
		"proposal_id": proposal.id, "from": proposer_id, "to": counterparty_id,
		"primitives": primitives.size(),
	})
	return proposal


func counter_propose(proposal_id: StringName, modified_primitives: Array[TreatyPrimitive], counter_proposer_id: StringName, day: int = -1) -> TreatyProposal:
	if day < 0:
		day = _time_keeper.current_day
	var proposal: TreatyProposal = _proposals.get(proposal_id, null)
	if proposal == null:
		_logger.warn(LogChannels.TREATY, "Counter-propose on unknown proposal", {"proposal_id": proposal_id})
		return null
	if proposal.stage != &"negotiation":
		_logger.warn(LogChannels.TREATY, "Counter-propose on non-negotiation proposal", {"proposal_id": proposal_id, "stage": proposal.stage})
		return null
	if proposal.current_round >= proposal.max_rounds:
		_logger.info(LogChannels.TREATY, "Max rounds reached, closing proposal", {"proposal_id": proposal_id})
		proposal.stage = &"terminated"
		proposal.terminated_at_day = day
		proposal.termination_reason = "max_rounds_reached"
		return proposal
	proposal.current_round += 1
	proposal.primitives = modified_primitives
	proposal.history.append({
		"round": proposal.current_round, "action": "counter_proposed", "day": day,
		"by": counter_proposer_id, "primitives_snapshot": _snapshot_primitives(modified_primitives),
	})
	var event := TreatyCounterProposedEvent.new()
	event.proposal_id = proposal_id
	event.counter_proposer_immortal_id = counter_proposer_id
	event.original_proposer_immortal_id = proposal.proposer_immortal_id if counter_proposer_id != proposal.proposer_immortal_id else proposal.counterparty_immortal_id
	event.round_number = proposal.current_round
	event.day = day
	_event_bus.dispatch(event)
	return proposal


func accept_proposal(proposal_id: StringName, acceptor_id: StringName, day: int = -1) -> TreatyRecord:
	if day < 0:
		day = _time_keeper.current_day
	var proposal: TreatyProposal = _proposals.get(proposal_id, null)
	if proposal == null:
		return null
	if proposal.stage != &"negotiation":
		return null
	proposal.stage = &"signed"
	proposal.signed_at_day = day
	proposal.history.append({
		"round": proposal.current_round, "action": "accepted", "day": day,
		"by": acceptor_id, "primitives_snapshot": _snapshot_primitives(proposal.primitives),
	})
	# Create active treaty
	var treaty := TreatyRecord.new()
	treaty.id = _generate_treaty_id()
	treaty.proposal_id = proposal_id
	# Alphabetical ordering of signatories
	var id_a: StringName = proposal.proposer_immortal_id
	var id_b: StringName = proposal.counterparty_immortal_id
	if String(id_b) < String(id_a):
		var tmp: StringName = id_a
		id_a = id_b
		id_b = tmp
	treaty.signatory_a_immortal_id = id_a
	treaty.signatory_b_immortal_id = id_b
	var imm_a: ImmortalRecord = _immortal_registry.get_immortal(id_a)
	var imm_b: ImmortalRecord = _immortal_registry.get_immortal(id_b)
	if imm_a != null:
		treaty.signatory_a_society_id = imm_a.society_id
	if imm_b != null:
		treaty.signatory_b_society_id = imm_b.society_id
	treaty.primitives = proposal.primitives
	treaty.signed_at_day = day
	# Check for duration primitive to set expiry
	for prim: TreatyPrimitive in proposal.primitives:
		if prim.category == &"term":
			if prim.kind == &"duration":
				var years: int = prim.parameters.get("years", 0)
				if years > 0:
					treaty.expires_at_day = day + (years * 365)
			elif prim.kind == &"perpetual_until_broken":
				treaty.expires_at_day = -1
	treaty.status = &"active"
	_treaties[treaty.id] = treaty
	# Reputation: +1 each for signing
	_update_reputation(id_a, 1, day, "treaty_signed")
	_update_reputation(id_b, 1, day, "treaty_signed")
	# Fire events
	var accepted_event := TreatyAcceptedEvent.new()
	accepted_event.proposal_id = proposal_id
	accepted_event.treaty_id = treaty.id
	accepted_event.acceptor_immortal_id = acceptor_id
	accepted_event.proposer_immortal_id = proposal.proposer_immortal_id if acceptor_id != proposal.proposer_immortal_id else proposal.counterparty_immortal_id
	accepted_event.day = day
	_event_bus.dispatch(accepted_event)
	var signed_event := TreatySignedEvent.new()
	signed_event.treaty_id = treaty.id
	signed_event.signatory_a_immortal_id = id_a
	signed_event.signatory_b_immortal_id = id_b
	signed_event.day = day
	_event_bus.dispatch(signed_event)
	_logger.info(LogChannels.TREATY, "Treaty signed", {
		"treaty_id": treaty.id, "signatories": [id_a, id_b],
	})
	return treaty


func reject_proposal(proposal_id: StringName, rejector_id: StringName, reason: String = "", day: int = -1) -> void:
	if day < 0:
		day = _time_keeper.current_day
	var proposal: TreatyProposal = _proposals.get(proposal_id, null)
	if proposal == null:
		return
	proposal.stage = &"terminated"
	proposal.terminated_at_day = day
	proposal.termination_reason = reason if reason != "" else "rejected"
	proposal.history.append({
		"round": proposal.current_round, "action": "rejected", "day": day,
		"by": rejector_id, "primitives_snapshot": _snapshot_primitives(proposal.primitives),
	})
	var event := TreatyRejectedEvent.new()
	event.proposal_id = proposal_id
	event.rejector_immortal_id = rejector_id
	event.proposer_immortal_id = proposal.proposer_immortal_id if rejector_id != proposal.proposer_immortal_id else proposal.counterparty_immortal_id
	event.reason = proposal.termination_reason
	event.day = day
	_event_bus.dispatch(event)


func get_active_treaties_for(immortal_id: StringName) -> Array[TreatyRecord]:
	var result: Array[TreatyRecord] = []
	for treaty: TreatyRecord in _treaties.values():
		if treaty.status != &"active":
			continue
		if treaty.signatory_a_immortal_id == immortal_id or treaty.signatory_b_immortal_id == immortal_id:
			result.append(treaty)
	return result


func get_all_treaties() -> Array[TreatyRecord]:
	var result: Array[TreatyRecord] = []
	for treaty: TreatyRecord in _treaties.values():
		result.append(treaty)
	return result


func get_proposal(proposal_id: StringName) -> TreatyProposal:
	return _proposals.get(proposal_id, null)


func find_treaty_violation(action_type: StringName, target_ref: StringName, immortal_id: StringName) -> Dictionary:
	for treaty: TreatyRecord in _treaties.values():
		if treaty.status != &"active":
			continue
		if treaty.signatory_a_immortal_id != immortal_id and treaty.signatory_b_immortal_id != immortal_id:
			continue
		for prim: TreatyPrimitive in treaty.primitives:
			if _primitive_violated_by(prim, action_type, target_ref, immortal_id, treaty):
				return {"treaty": treaty, "primitive": prim}
	return {}


func record_violation(treaty: TreatyRecord, violator_id: StringName, action_type: StringName, target_ref: StringName, day: int = -1) -> void:
	if day < 0:
		day = _time_keeper.current_day
	treaty.violations.append({
		"day": day, "violator_immortal_id": violator_id,
		"primitive_id": "", "evidence": action_type,
	})
	# Reputation: -10 to violator, -2 to counterparty
	_update_reputation(violator_id, -10, day, "treaty_violation")
	var counterparty_id: StringName = treaty.signatory_b_immortal_id if violator_id == treaty.signatory_a_immortal_id else treaty.signatory_a_immortal_id
	_update_reputation(counterparty_id, -2, day, "counterparty_of_violation")
	var event := TreatyViolationDetectedEvent.new()
	event.treaty_id = treaty.id
	event.violator_immortal_id = violator_id
	event.action_type = action_type
	event.target_ref = target_ref
	event.day = day
	_event_bus.dispatch(event)
	_logger.info(LogChannels.TREATY, "Treaty violation recorded", {
		"treaty_id": treaty.id, "violator": violator_id, "action": action_type,
	})


func terminate_treaty(treaty_id: StringName, terminator_id: StringName, reason: String = "", day: int = -1) -> void:
	if day < 0:
		day = _time_keeper.current_day
	var treaty: TreatyRecord = _treaties.get(treaty_id, null)
	if treaty == null or treaty.status != &"active":
		return
	if treaty.violations.size() > 0:
		treaty.status = &"violated_terminated"
	else:
		treaty.status = &"mutually_terminated"
		# Mutual termination: -1 each
		_update_reputation(treaty.signatory_a_immortal_id, -1, day, "treaty_mutually_terminated")
		_update_reputation(treaty.signatory_b_immortal_id, -1, day, "treaty_mutually_terminated")
	var event := TreatyTerminatedEvent.new()
	event.treaty_id = treaty_id
	event.terminator_immortal_id = terminator_id
	event.reason = reason
	event.day = day
	_event_bus.dispatch(event)
	_logger.info(LogChannels.TREATY, "Treaty terminated", {
		"treaty_id": treaty_id, "by": terminator_id, "reason": reason,
	})


# --- Counterparty evaluation (Part 1.6) ---

# Evaluate a treaty proposal from the perspective of the counterparty.
# Returns &"accept", &"reject", or &"counter" plus a score and rejected primitives.
func evaluate_proposal_as_counterparty(proposal: TreatyProposal, evaluator_society: SocietyCharacterRecord, evaluator_character: CharacterRecord = null) -> Dictionary:
	var total_score: float = 0.0
	var rejected_primitives: Array = []
	var wanted_primitives: Array = []  # primitives the evaluator would add
	var helpers_node: Node = get_node_or_null("/root/Helpers")
	# Check each primitive against society character
	for prim: TreatyPrimitive in proposal.primitives:
		# Forbidden move check — immediate reject
		if _primitive_matches_forbidden(prim, evaluator_society):
			return {"decision": &"reject", "score": -100, "rejected_primitives": [prim], "reason": "forbidden_move"}
		# Value alignment score
		var alignment: float = _score_primitive_alignment(prim, evaluator_society)
		total_score += alignment
		# Asymmetric benefit detection
		if prim.direction == &"from_them" or prim.direction == &"one_way":
			total_score -= 10.0  # penalize one-sided primitives against us
		if alignment < -5.0:
			rejected_primitives.append(prim)
	# Add disposition as base
	var disposition: int = evaluator_society.disposition_baseline
	var society_char_node: Node = get_node_or_null("../SocietyCharacter")
	if society_char_node != null:
		disposition = society_char_node.get_disposition(evaluator_society.society_id, proposal.proposer_immortal_id)
	total_score += disposition
	# Compound trait modifications
	if evaluator_character != null and helpers_node != null:
		if helpers_node.has_compound_trait_pattern(evaluator_character, &"dangerous_ruler"):
			total_score -= 15.0  # sees peer as future threat
		if helpers_node.has_compound_trait_pattern(evaluator_character, &"hunter"):
			# More granular evaluation — counter-proposes refinements rather than rejecting
			total_score += 5.0
		if helpers_node.has_compound_trait_pattern(evaluator_character, &"corruption_profile"):
			# Accepts disproportionate resource transfers TO them more readily
			for prim: TreatyPrimitive in proposal.primitives:
				if prim.category == &"resource" and prim.direction == &"from_them":
					total_score += 15.0
		if helpers_node.has_compound_trait_pattern(evaluator_character, &"religious_catalyst"):
			# Rejects proposals that contradict religious values harder
			for prim: TreatyPrimitive in proposal.primitives:
				if prim.kind == &"suppress_religion" or prim.kind == &"secular_mandate":
					total_score -= 20.0
		if helpers_node.has_compound_trait_pattern(evaluator_character, &"apex_predator"):
			# Would never sign restraint primitives that constrain hostile operations
			for prim: TreatyPrimitive in proposal.primitives:
				if prim.category == &"restraint":
					total_score -= 25.0
	# Decision thresholds
	if total_score > 70.0:
		return {"decision": &"accept", "score": total_score, "rejected_primitives": [], "reason": ""}
	elif total_score < 30.0:
		return {"decision": &"reject", "score": total_score, "rejected_primitives": rejected_primitives, "reason": "low_score"}
	else:
		return {"decision": &"counter", "score": total_score, "rejected_primitives": rejected_primitives, "wanted_primitives": wanted_primitives, "reason": ""}


func _primitive_matches_forbidden(prim: TreatyPrimitive, society: SocietyCharacterRecord) -> bool:
	# Check if this primitive requires the society to do something in their forbidden_moves
	for forbidden: StringName in society.forbidden_moves:
		if prim.kind == forbidden:
			return true
		# Check parameters for forbidden action types
		var prim_type: Variant = prim.parameters.get("type", &"")
		if prim_type is StringName and prim_type == forbidden:
			return true
	return false


func _score_primitive_alignment(prim: TreatyPrimitive, society: SocietyCharacterRecord) -> float:
	var score: float = 0.0
	# Score based on how well the primitive aligns with society value weights
	match prim.category:
		&"information":
			score += society.value_weights.get(&"knowledge_preservation", 0) * 0.1
			score += society.value_weights.get(&"institutional_security", 0) * 0.05
		&"resource":
			score += 5.0  # resources are generally positive
		&"operational":
			if prim.kind == &"deconflict_region":
				score += society.value_weights.get(&"institutional_security", 0) * 0.1
			elif prim.kind == &"coordinate_against":
				score += 10.0  # coordinated operations against a shared threat
		&"restraint":
			# Restraints are complex — they protect but also limit
			if prim.kind == &"no_host_recruitment":
				score += society.value_weights.get(&"institutional_security", 0) * 0.08
			elif prim.kind == &"no_surveillance_escalation":
				score += society.value_weights.get(&"institutional_security", 0) * 0.06
		&"term":
			pass  # terms don't have alignment value
	return score


func get_reputation(immortal_id: StringName) -> ReputationRecord:
	if not _reputations.has(immortal_id):
		var rep := ReputationRecord.new()
		rep.immortal_id = immortal_id
		_reputations[immortal_id] = rep
	return _reputations[immortal_id]


# --- Tick processing ---

func _on_game_day_ticked(event: GameDayTickedEvent) -> void:
	var day: int = event.day
	# Check for treaty expiry
	for treaty_id: StringName in _treaties.keys():
		var treaty: TreatyRecord = _treaties[treaty_id]
		if treaty.status != &"active":
			continue
		if treaty.expires_at_day > 0 and day >= treaty.expires_at_day:
			treaty.status = &"expired"
			# +1/year per signatory for surviving the active period
			var years_active: float = (day - treaty.signed_at_day) / 365.0
			var honour_bonus: int = maxi(1, int(years_active))
			_update_reputation(treaty.signatory_a_immortal_id, honour_bonus, day, "treaty_honoured_through_expiry")
			_update_reputation(treaty.signatory_b_immortal_id, honour_bonus, day, "treaty_honoured_through_expiry")
			var exp_event := TreatyExpiredEvent.new()
			exp_event.treaty_id = treaty_id
			exp_event.signatory_a_immortal_id = treaty.signatory_a_immortal_id
			exp_event.signatory_b_immortal_id = treaty.signatory_b_immortal_id
			exp_event.day = day
			_event_bus.dispatch(exp_event)
			_logger.info(LogChannels.TREATY, "Treaty expired", {
				"treaty_id": treaty_id, "honour_bonus": honour_bonus,
			})


# --- Reputation helpers ---

func _update_reputation(immortal_id: StringName, delta: int, day: int, reason: String) -> void:
	var rep: ReputationRecord = get_reputation(immortal_id)
	var old_score: int = rep.reputation_score
	rep.apply_delta(delta, day, reason)
	if delta > 0:
		rep.treaties_honoured += 1
	elif delta < 0 and reason == "treaty_violation":
		rep.treaties_broken += 1
	var event := ReputationShiftEvent.new()
	event.immortal_id = immortal_id
	event.delta = delta
	event.new_score = rep.reputation_score
	event.reason = reason
	event.day = day
	_event_bus.dispatch(event)


# --- Violation detection ---

func _primitive_violated_by(prim: TreatyPrimitive, action_type: StringName, target_ref: StringName, _immortal_id: StringName, _treaty: TreatyRecord) -> bool:
	if prim.category == &"restraint":
		match prim.kind:
			&"no_host_recruitment":
				# Violated if action is a cultivation type targeting a character in the other society's known hosts
				if action_type in [&"cultivate_to_host", &"cultivate", &"recruit_to_witting"]:
					return true
			&"no_surveillance_escalation":
				if action_type == &"gather_intelligence":
					return true
	if prim.category == &"operational":
		match prim.kind:
			&"deconflict_region":
				var region: StringName = prim.parameters.get("region", &"")
				if region != &"" and target_ref == region:
					return true
	return false


# --- Utilities ---

func _snapshot_primitives(primitives: Array[TreatyPrimitive]) -> Array:
	var result: Array = []
	for prim: TreatyPrimitive in primitives:
		result.append({"id": prim.id, "category": prim.category, "kind": prim.kind})
	return result


func _generate_proposal_id() -> StringName:
	var seq := _next_proposal_seq
	_next_proposal_seq += 1
	return StringName("proposal_%d" % seq)


func _generate_treaty_id() -> StringName:
	var seq := _next_treaty_seq
	_next_treaty_seq += 1
	return StringName("treaty_%d" % seq)


# --- Save/load ---

func snapshot_state() -> Dictionary:
	return {
		"proposals": _proposals.duplicate(true),
		"treaties": _treaties.duplicate(true),
		"reputations": _reputations.duplicate(true),
		"next_proposal_seq": _next_proposal_seq,
		"next_treaty_seq": _next_treaty_seq,
	}


func apply_state(state) -> void:
	if state == null or (state is Dictionary and state.is_empty()):
		return
	_proposals = state.get("proposals", {}).duplicate(true)
	_treaties = state.get("treaties", {}).duplicate(true)
	_reputations = state.get("reputations", {}).duplicate(true)
	_next_proposal_seq = state.get("next_proposal_seq", 1)
	_next_treaty_seq = state.get("next_treaty_seq", 1)
	_logger.info(LogChannels.TREATY, "Treaty state applied from load")
