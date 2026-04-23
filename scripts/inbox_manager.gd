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
	_seed_placeholder_letters()
	EventBus.letter_delivered.connect(add_letter)


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

func _seed_placeholder_letters() -> void:
	add_letter(Letter.create(
		&"letter_rome_consuls",
		"A friend in Roma",
		GameDate.make(501, 12, 28),
		"The young Republic stumbles",
		"The kings are nine winters gone and the consuls still "
		+ "quarrel like boys over a broken wheel. Every patrician "
		+ "house carries debts it cannot name aloud.\n\n"
		+ "There is work for a patient hand here. The city does "
		+ "not yet understand what it is becoming.\n\n"
		+ "Burn this after reading.\n\n"
		+ "— the usual",
		&"intro"
	))

	add_letter(Letter.create(
		&"letter_tyre_grain",
		"Adherbal, harbourmaster of Tyrus",
		GameDate.make(500, 2, 3),
		"The grain from Kemet, and a worry",
		"The shipment cleared the mouth of the Nile on the new "
		+ "moon. Three holds of emmer, one of barley. I have "
		+ "marked the jars as you asked.\n\n"
		+ "A Persian factor asked after you by name. I told him "
		+ "I knew no such man. He smiled as if that were the "
		+ "answer he expected.\n\n"
		+ "Send word before the equinox or I sail without you.\n\n"
		+ "— A.",
		&"intro"
	))

	add_letter(Letter.create(
		&"letter_miletos_unrest",
		"Kallias, your man in Miletos",
		GameDate.make(500, 3, 12),
		"Unrest among the Ionian cities",
		"The tyrants the Persian king set over us grow fat, and "
		+ "the assemblies grow loud. Aristagoras whispers of "
		+ "revolt in every wine-house on the agora.\n\n"
		+ "If the Ionians rise, Sardis will burn, and the Great "
		+ "King will not forget. We should decide, soon, which "
		+ "side of the fire we intend to stand on.\n\n"
		+ "Awaiting your sign.\n\n"
		+ "— K.",
		&"intro"
	))
