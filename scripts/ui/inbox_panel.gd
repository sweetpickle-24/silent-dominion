extends HSplitContainer

var _letter_list: VBoxContainer
var _filter_dropdown: OptionButton
var _detail_subject: Label
var _detail_meta: Label
var _detail_body: RichTextLabel
var _detail_actions: VBoxContainer
var _inbox_node: Node
var _immortal_registry: Node
var _event_bus: Node
var _letter_sub


func _ready() -> void:
	_inbox_node = (Engine.get_main_loop() as SceneTree).root.get_node("Main/Mechanics/Inbox")
	_immortal_registry = (Engine.get_main_loop() as SceneTree).root.get_node("ImmortalRegistry")
	_event_bus = (Engine.get_main_loop() as SceneTree).root.get_node("EventBus")

	# Left: letter list
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size.x = 300
	add_child(left)

	var list_title := Label.new()
	list_title.text = "Inbox"
	list_title.add_theme_font_size_override("font_size", 20)
	left.add_child(list_title)

	_filter_dropdown = OptionButton.new()
	_filter_dropdown.add_item("All active")
	_filter_dropdown.add_item("Unread")
	_filter_dropdown.item_selected.connect(func(_i): _refresh_list())
	left.add_child(_filter_dropdown)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	_letter_list = VBoxContainer.new()
	_letter_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_letter_list)

	# Right: detail view
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)

	_detail_subject = Label.new()
	_detail_subject.text = "Select a letter"
	_detail_subject.add_theme_font_size_override("font_size", 18)
	right.add_child(_detail_subject)

	_detail_meta = Label.new()
	_detail_meta.text = ""
	right.add_child(_detail_meta)

	_detail_body = RichTextLabel.new()
	_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_body.bbcode_enabled = false
	_detail_body.selection_enabled = true
	right.add_child(_detail_body)

	_detail_actions = VBoxContainer.new()
	right.add_child(_detail_actions)

	# Subscribe to letter arrivals for auto-refresh
	_letter_sub = _event_bus.subscribe(
		preload("res://scripts/data/events/letter_arrived_in_inbox_event.gd"),
		Callable(self, "_on_letter_arrived"),
		100, &"", EndOfTickPhases.UI,
	)

	_refresh_list()


func _exit_tree() -> void:
	if _letter_sub != null and _event_bus != null:
		_event_bus.unsubscribe(_letter_sub)


func _on_letter_arrived(_event) -> void:
	_refresh_list()


func _refresh_list() -> void:
	for child in _letter_list.get_children():
		child.queue_free()
	var letters: Array = _get_filtered_letters()
	letters.sort_custom(func(a: Letter, b: Letter) -> bool: return a.day_received > b.day_received)
	for letter: Letter in letters:
		var btn := Button.new()
		var prefix: String = "* " if not letter.is_read else "  "
		btn.text = "%s[Day %d] %s" % [prefix, letter.day_received, letter.subject]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_letter_selected.bind(letter))
		_letter_list.add_child(btn)


func _get_filtered_letters() -> Array:
	var player: ImmortalRecord = _immortal_registry.get_player()
	if player == null:
		return []
	var active: Array = _inbox_node.get_active_letters(player.id)
	if _filter_dropdown.selected == 1:
		var unread: Array = []
		for l: Letter in active:
			if not l.is_read:
				unread.append(l)
		return unread
	return active


func _on_letter_selected(letter: Letter) -> void:
	if not letter.is_read:
		_inbox_node.mark_read(letter.id)
		_refresh_list()
	_detail_subject.text = letter.subject
	var sender_name: String = _resolve_sender(letter)
	_detail_meta.text = "From: %s | Day %d | %s" % [sender_name, letter.day_received, letter.content_category]
	_detail_body.text = letter.body
	# Action affordance
	for child in _detail_actions.get_children():
		child.queue_free()
	if letter.action_ref != &"":
		var btn := Button.new()
		btn.text = "Compose action toward this subject"
		btn.pressed.connect(_navigate_compose.bind(letter))
		_detail_actions.add_child(btn)


func _navigate_compose(letter: Letter) -> void:
	# Try to find the target from the letter's action_ref
	var target: StringName = letter.action_ref
	if target != &"":
		ComposePrefill.target_ref = target
		ComposePrefill.target_kind = &"place"
	# Navigate to Compose via parent Table
	var table: Node = get_tree().root.find_child("Table", true, false)
	if table and table.has_method("_show_compose"):
		table._show_compose()


func _resolve_sender(letter: Letter) -> String:
	if letter.sender_kind == &"system":
		return "System"
	var c: CharacterRecord = _immortal_registry.get_character_record_any(letter.sender_ref)
	return c.name if c else str(letter.sender_ref)
