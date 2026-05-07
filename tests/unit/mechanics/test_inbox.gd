extends GutTest

var _inbox: Inbox


func before_each():
	_inbox = Inbox.new()
	_inbox.name = "Inbox"
	add_child(_inbox)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_inbox) and _inbox._tick_subscription:
		eb.unsubscribe(_inbox._tick_subscription)
	if is_instance_valid(_inbox):
		remove_child(_inbox)
		_inbox.free()


func test_add_letter():
	var l := Letter.new()
	l.id = &"test_letter"
	l.immortal_id = &"player"
	l.day_received = 5
	_inbox.add_letter(l)
	var state: InboxState = _inbox.get_inbox(&"player")
	assert_not_null(state)
	assert_eq(state.letters.size(), 1)


func test_archive_after_days():
	var l := Letter.new()
	l.id = &"old_letter"
	l.immortal_id = &"player"
	l.day_received = 0
	l.tier = &"active"
	_inbox.add_letter(l)
	# Simulate day tick past archive threshold
	var event := GameDayTickedEvent.new()
	event.day = 100
	_inbox._on_game_day_ticked(event)
	assert_eq(l.tier, &"archive", "Letter should be archived after 90 days")


func test_mark_read():
	var l := Letter.new()
	l.id = &"mark_me"
	l.immortal_id = &"player"
	_inbox.add_letter(l)
	_inbox.mark_read(&"mark_me")
	assert_true(l.is_read)


func test_next_letter_id_monotonic():
	var id1: StringName = _inbox.next_letter_id()
	var id2: StringName = _inbox.next_letter_id()
	assert_ne(id1, id2, "Letter IDs should be unique")


func test_save_load_roundtrip():
	var l := Letter.new()
	l.id = &"saved_letter"
	l.immortal_id = &"player"
	l.subject = "Saved"
	l.day_received = 10
	_inbox.add_letter(l)
	var state: Dictionary = _inbox.snapshot_state()
	_inbox.apply_state({})
	assert_eq(_inbox.get_active_letters().size(), 0)
	_inbox.apply_state(state)
	var restored: Array = _inbox.get_active_letters()
	assert_eq(restored.size(), 1)
	assert_eq(restored[0].subject, "Saved")
