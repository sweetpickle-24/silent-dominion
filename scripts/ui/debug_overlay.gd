extends CanvasLayer

var _panel: Panel
var _tab_container: TabContainer


func _ready() -> void:
	if not OS.is_debug_build():
		visible = false
		set_process_unhandled_input(false)
		return

	layer = 100
	visible = false

	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 20
	_panel.offset_top = 20
	_panel.offset_right = -20
	_panel.offset_bottom = -20
	add_child(_panel)

	_tab_container = TabContainer.new()
	_tab_container.name = "Tabs"
	_tab_container.anchor_left = 0.0
	_tab_container.anchor_top = 0.0
	_tab_container.anchor_right = 1.0
	_tab_container.anchor_bottom = 1.0
	_tab_container.offset_left = 8
	_tab_container.offset_top = 8
	_tab_container.offset_right = -8
	_tab_container.offset_bottom = -8
	_panel.add_child(_tab_container)

	# Tab 1: Log stream
	var log_stream := preload("res://scripts/ui/tab_log_stream.gd").new()
	_tab_container.add_child(log_stream)

	# Tab 2: Event flow
	var event_flow := preload("res://scripts/ui/tab_event_flow.gd").new()
	_tab_container.add_child(event_flow)

	# Tab 3: Tick budget
	var tick_budget := preload("res://scripts/ui/tab_tick_budget.gd").new()
	_tab_container.add_child(tick_budget)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_overlay"):
		visible = not visible
		get_viewport().set_input_as_handled()
