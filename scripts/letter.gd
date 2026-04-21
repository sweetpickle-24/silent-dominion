class_name Letter
extends Resource
## A single piece of correspondence delivered to the player's inbox.
##
## Letters are content-driven: the simulation will eventually generate
## these from events (agent reports, rumours, contracts, threats). For
## now, the InboxManager seeds a handful of hand-written placeholders.

@export var id: StringName = &""
@export var sender: String = ""
@export var date: GameDate
@export var subject: String = ""
@export_multiline var body: String = ""
@export var is_read: bool = false


static func create(
		p_id: StringName,
		p_sender: String,
		p_date: GameDate,
		p_subject: String,
		p_body: String
) -> Letter:
	var l: Letter = Letter.new()
	l.id = p_id
	l.sender = p_sender
	l.date = p_date
	l.subject = p_subject
	l.body = p_body
	return l
