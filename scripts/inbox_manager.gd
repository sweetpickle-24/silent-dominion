extends Node
## Global inbox. Autoloaded as `Inbox`.
##
## Holds every letter the player has received. Other systems push letters
## in via `add_letter()`; the table/letter UI pulls via `get_*` helpers
## and listens to the `letters_changed` signal for visual updates.
##
## The top of the stack is conceptually the newest unread letter, falling
## back to the newest read letter once everything has been opened.

signal letters_changed
signal letter_read(letter: Letter)

var letters: Array[Letter] = []

# Index: actor_id -> Array[Letter] in insertion order. Rebuilt on save-
# load. Kept in sync on add_letter(). Lets the dossier fetch a name's
# recent letters in O(1).
var _by_actor: Dictionary = {}


func _ready() -> void:
	DevLogger.write("Inbox: ready")
	_seed_placeholder_letters()
	EventBus.letter_delivered.connect(add_letter)
	# §F2 — when a table object is unlocked by a milestone, drop a
	# one-shot factotum letter that names the object and its hotkey.
	if Unlocks != null and Unlocks.has_signal("surface_unlocked"):
		Unlocks.surface_unlocked.connect(_on_surface_unlocked)


const _UNLOCK_COPY: Dictionary = {
	&"memoirs": {
		"subject": "The drawer at your left hand",
		"hotkey":  "M",
		"body":    "The drawer you have not opened yet is the drawer where patterns live. Write one down and the Memoirs begin to compound. (M opens it.)",
	},
	&"vault":   {
		"subject": "The ledger is open",
		"hotkey":  "V",
		"body":    "Silver is moving. From here on, every coin has a route and a cost and a latency — and someone you can ask about all three. The Vault is yours. (V opens it.)",
	},
	&"library": {
		"subject": "The library, such as it is",
		"hotkey":  "F",
		"body":    "You have noticed a pattern repeat itself. A pattern noticed twice is a fingerprint. The Library will keep the count. (F opens it.)",
	},
	&"roster":  {
		"subject": "The roster, such as it is",
		"hotkey":  "O",
		"body":    "You have more than one name working for you now. The Roster shows who, where, and under how much strain. (O opens it.)",
	},
}


func _on_surface_unlocked(id: StringName) -> void:
	var copy: Variant = _UNLOCK_COPY.get(id, null)
	if copy == null:
		return
	var subject: String = String((copy as Dictionary).get("subject", ""))
	var body: String = String((copy as Dictionary).get("body", ""))
	add_letter(Letter.create(
		StringName("unlock_%s" % String(id)),
		OrgRoles.sender_line(OrgRoles.FACTOTUM),
		GameDate.today(),
		subject,
		body,
		&"intro"
	))


# --- Public API ---------------------------------------------------------------

func add_letter(letter: Letter) -> void:
	letters.append(letter)
	_index_letter(letter)
	letters_changed.emit()


## Returns every Letter whose body names the given actor (via the
## `[url=actor:<id>]` BBCode anchor), newest-first. Cheap lookup backed
## by `_by_actor`.
func letters_about(actor_id: StringName) -> Array[Letter]:
	var raw: Array = _by_actor.get(actor_id, []) as Array
	var out: Array[Letter] = []
	for i in range(raw.size() - 1, -1, -1):
		var l: Letter = raw[i]
		if l != null:
			out.append(l)
	return out


## Rebuild the actor index from `letters`. Call after a save-load
## replaces the `letters` array in bulk.
func rebuild_index() -> void:
	_by_actor.clear()
	for l in letters:
		_index_letter(l)


func _index_letter(letter: Letter) -> void:
	if letter == null:
		return
	# Parse every [url=actor:<id>] anchor in the body.
	var body: String = letter.body
	var cursor: int = 0
	while true:
		var i: int = body.find("[url=actor:", cursor)
		if i < 0:
			break
		var start: int = i + len("[url=actor:")
		var end: int = body.find("]", start)
		if end < 0:
			break
		var actor_id: StringName = StringName(body.substr(start, end - start))
		var arr: Array = _by_actor.get(actor_id, []) as Array
		if not arr.has(letter):
			arr.append(letter)
		_by_actor[actor_id] = arr
		cursor = end + 1


func get_unread() -> Array[Letter]:
	var out: Array[Letter] = []
	for l in letters:
		if not l.is_read:
			out.append(l)
	return out


func get_unread_count() -> int:
	return get_unread().size()


func has_unread() -> bool:
	return get_unread_count() > 0


## The letter presented when the player clicks the stack.
## Newest unread first; if the inbox is fully read, the newest letter overall.
func get_top_letter() -> Letter:
	for i in range(letters.size() - 1, -1, -1):
		if not letters[i].is_read:
			return letters[i]
	if letters.is_empty():
		return null
	return letters.back()


func mark_read(id: StringName) -> void:
	for l in letters:
		if l.id == id and not l.is_read:
			l.is_read = true
			letter_read.emit(l)
			letters_changed.emit()
			return


# --- Seed data ----------------------------------------------------------------
#
# Three opening letters to set the tone. These will be replaced by the
# simulation once it is producing events. Keep them short and flavourful.

## §C3 — a single turn-1 letter from the starter coordinator. No
## ghost-actor letters. The coordinator actually exists (seeded by
## OrgRegistry on world_loaded); the name in the byline is a real
## OrgMember display_name.
func _seed_placeholder_letters() -> void:
	if WorldData != null and not WorldData.is_loaded():
		WorldData.world_loaded.connect(_emit_starter_letter, CONNECT_ONE_SHOT)
		return
	_emit_starter_letter()


func _emit_starter_letter() -> void:
	# Defer one frame so OrgRegistry has finished seeding the starter
	# cell before we resolve the coordinator's name.
	call_deferred("_emit_starter_letter_now")


func _emit_starter_letter_now() -> void:
	var sender: String = OrgRoles.sender_line(OrgRoles.COORDINATOR, "athens")
	var body: String = (
		"The predecessor's papers are in order. The Athens table is yours.\n\n"
		+ "I have kept the quiet arrangements quiet through the interregnum. "
		+ "The house in the Kerameikos has a merchant on retainer — a decent "
		+ "man, cultivated into our orbit under the old hand — and a modest "
		+ "banking arrangement carried over to your name. Nothing louder than "
		+ "that. We will build at your pace, not mine.\n\n"
		+ "Write when you are settled. Until then, I hold the city."
	)
	add_letter(Letter.create(
		&"letter_starter_coord_welcome",
		sender,
		GameDate.today(),
		"The Athens table is yours",
		body,
		&"intro"
	))
