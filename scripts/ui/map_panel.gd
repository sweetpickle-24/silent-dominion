extends VBoxContainer


func _ready() -> void:
	var world_reg: Node = (Engine.get_main_loop() as SceneTree).root.get_node("WorldRegistry")
	var place_mech: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main/Mechanics/Place")
	var serif_font: Font = load("res://data/fonts/EBGaramond-Regular.ttf")

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "Map"
	if serif_font:
		title.add_theme_font_override("font", serif_font)
	title.add_theme_font_size_override("font_size", 22)
	outer.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "A more detailed map will be drawn in substep 11.6."
	subtitle.add_theme_color_override("font_color", Color("#7a6850"))
	subtitle.add_theme_font_size_override("font_size", 12)
	outer.add_child(subtitle)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	var places: Array = []
	for pid: StringName in world_reg.all_place_ids():
		places.append(world_reg.get_place(pid))
	places.sort_custom(func(a: PlaceRecord, b: PlaceRecord) -> bool:
		return a.region < b.region or (a.region == b.region and a.name < b.name))

	for place: PlaceRecord in places:
		var pop: int = place.population
		if place_mech and place_mech.has_method("get_place_state"):
			var runtime: PlaceRecord = place_mech.get_place_state(place.id)
			if runtime:
				pop = runtime.population

		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(280, 0)
		var card_sb := StyleBoxFlat.new()
		card_sb.bg_color = Color("#e8dcc4")
		card_sb.set_corner_radius_all(4)
		card_sb.set_content_margin_all(16)
		card.add_theme_stylebox_override("panel", card_sb)

		var card_content := VBoxContainer.new()
		card_content.add_theme_constant_override("separation", 4)
		card.add_child(card_content)

		var name_label := Label.new()
		name_label.text = place.name
		if serif_font:
			name_label.add_theme_font_override("font", serif_font)
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.add_theme_color_override("font_color", Color("#1a1108"))
		card_content.add_child(name_label)

		var region_label := Label.new()
		region_label.text = str(place.region).to_upper()
		region_label.add_theme_font_size_override("font_size", 11)
		region_label.add_theme_color_override("font_color", Color("#5a4530"))
		card_content.add_child(region_label)

		var details := Label.new()
		details.text = "Population: %d\nType: %s" % [pop, place.place_type]
		details.add_theme_font_size_override("font_size", 12)
		details.add_theme_color_override("font_color", Color("#7a6850"))
		card_content.add_child(details)

		grid.add_child(card)
