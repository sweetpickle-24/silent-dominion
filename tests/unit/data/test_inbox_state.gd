extends GutTest


func _make_letter(id: StringName, tier: StringName = &"active", is_read: bool = false, action_ref: StringName = &"") -> Letter:
	var l := Letter.new()
	l.id = id
	l.immortal_id = &"player"
	l.subject = "Subject %s" % id
	l.body = "Body"
	l.day_received = 10
	l.tier = tier
	l.is_read = is_read
	l.action_ref = action_ref
	return l


func test_get_active_letters():
	var state := InboxState.new()
	state.letters.append(_make_letter(&"l1", &"active"))
	state.letters.append(_make_letter(&"l2", &"archive"))
	state.letters.append(_make_letter(&"l3", &"active"))
	assert_eq(state.get_active_letters().size(), 2)


func test_get_archived_letters():
	var state := InboxState.new()
	state.letters.append(_make_letter(&"l1", &"active"))
	state.letters.append(_make_letter(&"l2", &"archive"))
	assert_eq(state.get_archived_letters().size(), 1)


func test_get_unread_count():
	var state := InboxState.new()
	state.letters.append(_make_letter(&"l1", &"active", false))
	state.letters.append(_make_letter(&"l2", &"active", true))
	state.letters.append(_make_letter(&"l3", &"active", false))
	assert_eq(state.get_unread_count(), 2)


func test_find_letter():
	var state := InboxState.new()
	state.letters.append(_make_letter(&"l1"))
	state.letters.append(_make_letter(&"l2"))
	assert_not_null(state.find_letter(&"l1"))
	assert_null(state.find_letter(&"nonexistent"))


func test_letters_for_action():
	var state := InboxState.new()
	state.letters.append(_make_letter(&"l1", &"active", false, &"scheme_1"))
	state.letters.append(_make_letter(&"l2", &"active", false, &"scheme_2"))
	state.letters.append(_make_letter(&"l3", &"active", false, &"scheme_1"))
	assert_eq(state.letters_for_action(&"scheme_1").size(), 2)
	assert_eq(state.letters_for_action(&"scheme_2").size(), 1)
