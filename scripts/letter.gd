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


static func create(
		p_id: StringName,
		p_sender: String,
		p_date: GameDate,
		p_subject: String,
		p_body: String,
		p_kind: StringName = &"misc"
) -> Letter:
	var l: Letter = Letter.new()
	l.id = p_id
	l.sender = p_sender
	l.date = p_date
	l.subject = p_subject
	l.body = p_body
	l.kind = p_kind
	return l
