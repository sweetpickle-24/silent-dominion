class_name InboxState
extends Resource

@export var immortal_id: StringName = &""
@export var letters: Array[Letter] = []
@export var next_letter_seq: int = 1


func get_active_letters() -> Array[Letter]:
	var matches: Array[Letter] = []
	for letter: Letter in letters:
		if letter.tier == &"active":
			matches.append(letter)
	return matches


func get_archived_letters() -> Array[Letter]:
	var matches: Array[Letter] = []
	for letter: Letter in letters:
		if letter.tier == &"archive":
			matches.append(letter)
	return matches


func get_unread_count() -> int:
	var count: int = 0
	for letter: Letter in letters:
		if not letter.is_read:
			count += 1
	return count


func find_letter(letter_id: StringName) -> Letter:
	for letter: Letter in letters:
		if letter.id == letter_id:
			return letter
	return null


func letters_for_action(action_ref: StringName) -> Array[Letter]:
	var matches: Array[Letter] = []
	for letter: Letter in letters:
		if letter.action_ref == action_ref:
			matches.append(letter)
	return matches
