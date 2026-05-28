class_name ComposePrefill
extends RefCounted

static var target_ref: StringName = &""
static var target_kind: StringName = &""

# Treaty negotiation context (set when replying to treaty correspondence)
static var treaty_negotiation_context: Dictionary = {}  # {proposal_id, counterparty_id, mode: &"accept"|&"counter"|&"reject"}

# Reply context (generic — treaty is the first use case)
static var reply_to_letter_id: StringName = &""
static var reply_triggering_event_class: StringName = &""


static func clear() -> void:
	target_ref = &""
	target_kind = &""
	treaty_negotiation_context = {}
	reply_to_letter_id = &""
	reply_triggering_event_class = &""


static func set_treaty_proposal_context(proposal_id: StringName, counterparty_id: StringName) -> void:
	treaty_negotiation_context = {
		"proposal_id": proposal_id,
		"counterparty_id": counterparty_id,
		"mode": &"propose",
	}
	target_kind = &"treaty_proposal"


static func set_treaty_reply_context(proposal_id: StringName, counterparty_id: StringName, mode: StringName) -> void:
	treaty_negotiation_context = {
		"proposal_id": proposal_id,
		"counterparty_id": counterparty_id,
		"mode": mode,  # &"accept" | &"counter" | &"reject"
	}
	target_kind = &"treaty_reply"
