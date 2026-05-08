extends VBoxContainer


func _ready() -> void:
	var world_reg: Node = (Engine.get_main_loop() as SceneTree).root.get_node("WorldRegistry")
	var place_mech: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main/Mechanics/Place")

	var title := Label.new()
	title.text = "Map (placeholder — substep 11.6 ships real cartography)"
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var places: Array = []
	for pid: StringName in world_reg.all_place_ids():
		places.append(world_reg.get_place(pid))
	places.sort_custom(func(a: PlaceRecord, b: PlaceRecord) -> bool:
		return a.region < b.region or (a.region == b.region and a.name < b.name))

	var current_region: StringName = &""
	for place: PlaceRecord in places:
		if place.region != current_region:
			current_region = place.region
			var region_header := Label.new()
			region_header.text = "--- %s ---" % current_region
			region_header.add_theme_font_size_override("font_size", 16)
			list.add_child(region_header)
		# Get runtime population if Place mechanic is available
		var pop: int = place.population
		if place_mech and place_mech.has_method("get_place_state"):
			var runtime: PlaceRecord = place_mech.get_place_state(place.id)
			if runtime:
				pop = runtime.population
		var card := Label.new()
		card.text = "  %s  |  %s  |  pop: %d" % [place.name, place.place_type, pop]
		list.add_child(card)
