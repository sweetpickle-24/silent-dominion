extends GutTest

var _first_contact: FirstContact


func before_each():
	_first_contact = FirstContact.new()
	_first_contact.name = "FirstContact"
	add_child(_first_contact)


func after_each():
	if is_instance_valid(_first_contact):
		remove_child(_first_contact)
		_first_contact.free()


func test_first_contact_event_sets_aware():
	var event := FirstContactEvent.new()
	event.detecting_immortal_id = &"player"
	event.detected_society_id = &"the_veil"
	event.detected_immortal_id = &"the_veil_founder"
	event.day = 100
	_first_contact._on_first_contact_event(event)
	var state: FirstContactState = _first_contact.get_contact_state(&"player", &"the_veil_founder")
	assert_not_null(state)
	# "player" < "the_veil_founder" alphabetically, so player is a
	assert_eq(state.stage, &"a_aware")
	assert_eq(state.first_aware_day, 100)


func test_mutual_awareness():
	# Player detects Veil
	var event1 := FirstContactEvent.new()
	event1.detecting_immortal_id = &"player"
	event1.detected_society_id = &"the_veil"
	event1.detected_immortal_id = &"the_veil_founder"
	event1.day = 100
	_first_contact._on_first_contact_event(event1)
	# Veil detects player
	var event2 := FirstContactEvent.new()
	event2.detecting_immortal_id = &"the_veil_founder"
	event2.detected_society_id = &"player_organisation"
	event2.detected_immortal_id = &"player"
	event2.day = 150
	_first_contact._on_first_contact_event(event2)
	var state: FirstContactState = _first_contact.get_contact_state(&"player", &"the_veil_founder")
	assert_eq(state.stage, &"mutual_aware")


func test_initiate_contact_with_gesture():
	# First set up awareness
	var event := FirstContactEvent.new()
	event.detecting_immortal_id = &"the_veil_founder"
	event.detected_society_id = &"player_organisation"
	event.detected_immortal_id = &"player"
	event.day = 100
	_first_contact._on_first_contact_event(event)
	# Veil initiates contact
	var state := _first_contact.initiate_contact(&"the_veil_founder", &"player", &"shared_intelligence", 200)
	assert_eq(state.stage, &"contact_initiated")
	assert_eq(state.contact_initiator_id, &"the_veil_founder")
	assert_eq(state.opening_gesture_kind, &"shared_intelligence")


func test_reciprocated_response_opens_channel():
	_first_contact.initiate_contact(&"the_veil_founder", &"player", &"shared_intelligence", 200)
	var state := _first_contact.respond_to_contact(&"the_veil_founder", &"player", &"reciprocated", 250)
	assert_eq(state.stage, &"channel_open")
	assert_eq(state.opening_gesture_response, &"reciprocated")


func test_ignored_response_stays_responded():
	_first_contact.initiate_contact(&"the_veil_founder", &"player", &"host_courtesy", 200)
	var state := _first_contact.respond_to_contact(&"the_veil_founder", &"player", &"ignored", 300)
	assert_eq(state.stage, &"contact_responded")
	assert_eq(state.opening_gesture_response, &"ignored")
