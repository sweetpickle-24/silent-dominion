extends VBoxContainer

var _action_dropdown: OptionButton
var _target_dropdown: OptionButton
var _cost_label: Label
var _seal_button: Button

var _action_defs: Array = []
var _targets: Array = []


func _ready() -> void:
	var chain: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Main/Mechanics/Chain")
	var world_reg: Node = (Engine.get_main_loop() as SceneTree).root.get_node("WorldRegistry")
	var immortal_reg: Node = (Engine.get_main_loop() as SceneTree).root.get_node("ImmortalRegistry")

	var title := Label.new()
	title.text = "Compose"
	title.add_theme_font_size_override("font_size", 22)
	add_child(title)

	# Action dropdown
	var action_row := HBoxContainer.new()
	add_child(action_row)
	var action_label := Label.new()
	action_label.text = "Action: "
	action_row.add_child(action_label)
	_action_dropdown = OptionButton.new()
	_action_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(_action_dropdown)

	# Target dropdown
	var target_row := HBoxContainer.new()
	add_child(target_row)
	var target_label := Label.new()
	target_label.text = "Target: "
	target_row.add_child(target_label)
	_target_dropdown = OptionButton.new()
	_target_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_row.add_child(_target_dropdown)

	# Cost preview
	_cost_label = Label.new()
	_cost_label.text = "Cost: ..."
	add_child(_cost_label)

	# Seal & Send
	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(spacer)

	_seal_button = Button.new()
	_seal_button.text = "Seal & Send"
	_seal_button.pressed.connect(_on_seal_pressed)
	var seal_sb := StyleBoxFlat.new()
	seal_sb.bg_color = Color("#8b3a2a")
	seal_sb.set_corner_radius_all(6)
	seal_sb.set_content_margin_all(16)
	_seal_button.add_theme_stylebox_override("normal", seal_sb)
	var seal_hover := StyleBoxFlat.new()
	seal_hover.bg_color = Color("#a64d3a")
	seal_hover.set_corner_radius_all(6)
	seal_hover.set_content_margin_all(16)
	_seal_button.add_theme_stylebox_override("hover", seal_hover)
	_seal_button.add_theme_color_override("font_color", Color("#e8dcc4"))
	_seal_button.add_theme_color_override("font_hover_color", Color("#ffffff"))
	_seal_button.add_theme_font_size_override("font_size", 16)
	add_child(_seal_button)

	# Populate
	_populate_actions(chain)
	_populate_targets(world_reg, immortal_reg)
	_action_dropdown.item_selected.connect(_on_selection_changed)
	_target_dropdown.item_selected.connect(_on_selection_changed)

	# Apply prefill if set
	if ComposePrefill.target_ref != &"":
		_apply_prefill()
		ComposePrefill.target_ref = &""
		ComposePrefill.target_kind = &""

	_update_cost_preview()


func _populate_actions(chain: Node) -> void:
	var all_defs: Dictionary = chain.get_all_action_definitions()
	_action_defs.clear()
	for key: StringName in all_defs:
		_action_defs.append(all_defs[key])
	_action_defs.sort_custom(func(a: ActionDefinition, b: ActionDefinition) -> bool:
		return a.tier < b.tier or (a.tier == b.tier and a.display_name < b.display_name))
	for ad: ActionDefinition in _action_defs:
		_action_dropdown.add_item("[T%d] %s" % [ad.tier, ad.display_name])


func _populate_targets(world_reg: Node, immortal_reg: Node) -> void:
	_targets.clear()
	for pid: StringName in world_reg.all_place_ids():
		var p: PlaceRecord = world_reg.get_place(pid)
		_target_dropdown.add_item("%s (%s)" % [p.name, p.region])
		_targets.append({"kind": &"place", "ref": pid})
	for cid: StringName in immortal_reg.all_character_ids():
		var c: CharacterRecord = immortal_reg.get_character(cid)
		if c.chain_status != ChainStatusValues.NONE:
			continue
		_target_dropdown.add_item("%s - %s" % [c.name, c.profession])
		_targets.append({"kind": &"character", "ref": cid})


func _apply_prefill() -> void:
	for i in range(_targets.size()):
		if _targets[i].ref == ComposePrefill.target_ref:
			_target_dropdown.selected = i
			break


func _on_selection_changed(_idx: int) -> void:
	_update_cost_preview()


func _update_cost_preview() -> void:
	if _action_defs.is_empty() or _targets.is_empty():
		_cost_label.text = "Cost: N/A"
		return
	var ad: ActionDefinition = _action_defs[_action_dropdown.selected]
	var immortal_reg: Node = (Engine.get_main_loop() as SceneTree).root.get_node("ImmortalRegistry")
	var player: ImmortalRecord = immortal_reg.get_player()
	var mult: float = PublicPositionValues.EXPOSURE_MULTIPLIER.get(
		player.character.public_position_tier, 1.0)
	_cost_label.text = "Exposure surface  ~%.1f\nBandwidth         %d slot%s\nFinancial         %d silver\nDuration          ~%d days\n(estimate — final cost depends on operative)" % [
		ad.baseline_exposure_cost * mult,
		ad.baseline_bandwidth_cost,
		"s" if ad.baseline_bandwidth_cost != 1 else "",
		ad.baseline_financial_cost,
		ad.baseline_time_days,
	]


func _on_seal_pressed() -> void:
	if _action_defs.is_empty() or _targets.is_empty():
		return
	var ad: ActionDefinition = _action_defs[_action_dropdown.selected]
	var target: Dictionary = _targets[_target_dropdown.selected]
	var target_ref: StringName = target.ref
	var target_place_ref: StringName = &""
	if target.kind == &"place":
		target_place_ref = target.ref
	else:
		var immortal_reg: Node = (Engine.get_main_loop() as SceneTree).root.get_node("ImmortalRegistry")
		var c: CharacterRecord = immortal_reg.get_character(target.ref)
		if c:
			target_place_ref = c.current_place
	var action_node: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Main/Mechanics/Action")
	action_node.dispatch(ad.id, target_ref, target_place_ref)
