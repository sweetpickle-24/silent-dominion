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


func _ready() -> void:
	_seed_placeholder_letters()
	EventBus.letter_delivered.connect(add_letter)


# --- Public API ---------------------------------------------------------------

func add_letter(letter: Letter) -> void:
	letters.append(letter)
	letters_changed.emit()


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
