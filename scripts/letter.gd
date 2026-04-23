class_name Letter
extends Resource
## A single piece of correspondence delivered to the player's inbox.
##
## Letters are content-driven: the simulation will eventually generate
## these from events (agent reports, rumours, contracts, threats). For
## now, the InboxManager seeds a handful of hand-written placeholders.

## Letter kinds. Keep in sync with the badge colors in
## `letter_kind.gd` — the inbox and memoirs render a small wax dot in
## the matching shade so a player can skim incoming correspondence
## at a glance without opening each one.
##
## Only a small, finite vocabulary is used — every new Letter that the
## simulation produces must pick one.
##   - intel:    agent reports, eyes-and-ears observations, bribe receipts.
##   - action:   resolved player-issued instruments (same shape as intel
##               for now; retained separately so we can diverge later).
##   - host:     unprompted flavor letters from loyal hosts.
##   - digest:   the monthly summary from your factotum.
##   - news:     a copy of a public dispatch important enough to forward.
##   - intro:    the on-boarding welcome letter.
##   - misc:     anything unclassified. Avoid if you can.
@export var id: StringName = &""
@export var sender: String = ""
@export var date: GameDate
@export var subject: String = ""
@export_multiline var body: String = ""
@export var is_read: bool = false
@export var kind: StringName = &"misc"

# Priority tier (§10.4 auto-pause). Defaults to normal; high lets
# the time controller freeze the clock when this letter lands if
# the player has opted in. Low is pure background flavour.
#   &"low" | &"normal" | &"high"
@export var priority: StringName = &"normal"

# --- Confidence / fog-of-intel (§18) -------------------------------------
#
# How much the player should trust what is written below. 100 = first-hand
# or verified against at least one second source; lower values mean this
# is the *reporter's* claim and nothing has corroborated it yet. Surfaced
# as a band in the LetterView header and used by the cross-reference UI.
#
# Default -1 = "no band" (onboarding/flavour letters, digests, and
# anything for which "confidence" is a meaningless concept).
@export_range(-1, 100) var confidence: int = -1

# Optional free-form reporter tag — which source in the org pipeline this
# letter came from. Used by cross-reference to group letters by source.
# Empty string when the letter is not a source-driven report.
@export var reporter_id: StringName = &""


func is_high_priority() -> bool:
	return priority == &"high"


func has_confidence_band() -> bool:
	return confidence >= 0


## Bucketed confidence tier. `high` >= 75; `medium` >= 45; anything lower
## is `low`. Used by LetterView to choose the band colour and label.
func confidence_tier() -> StringName:
	if confidence < 0: return &"none"
	if confidence >= 75: return &"high"
	if confidence >= 45: return &"medium"
	return &"low"


static func create(
		p_id: StringName,
		p_sender: String,
		p_date: GameDate,
		p_subject: String,
		p_body: String,
		p_kind: StringName = &"misc",
		p_priority: StringName = &"normal",
		p_confidence: int = -1,
		p_reporter_id: StringName = &""
) -> Letter:
	var l: Letter = Letter.new()
	l.id = p_id
	l.sender = p_sender
	l.date = p_date
	l.subject = p_subject
	l.body = p_body
	l.kind = p_kind
	l.priority = p_priority
	l.confidence = p_confidence
	l.reporter_id = p_reporter_id
	return l
