extends VBoxContainer

var _stats_label: Label
var _graph_line: Line2D
var _time_keeper: Node
var _update_timer: float = 0.0
const _UPDATE_INTERVAL: float = 0.2  # 5 Hz


func _ready() -> void:
	name = "Tick Budget"
	_time_keeper = (Engine.get_main_loop() as SceneTree).root.get_node("TimeKeeper")

	_stats_label = Label.new()
	_stats_label.text = "Tick budget: waiting for data..."
	add_child(_stats_label)

	var graph_panel := Panel.new()
	graph_panel.custom_minimum_size = Vector2(0, 150)
	graph_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(graph_panel)

	_graph_line = Line2D.new()
	_graph_line.width = 1.5
	_graph_line.default_color = Color.GREEN
	graph_panel.add_child(_graph_line)


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < _UPDATE_INTERVAL:
		return
	_update_timer = 0.0

	var timings: Array = _time_keeper.get_tick_timings()
	if timings.is_empty():
		return

	# Stats
	var last_entry: Dictionary = timings[-1]
	var last_ms: float = last_entry.duration_ms
	var total: float = 0.0
	var max_ms: float = 0.0
	var count: int = mini(timings.size(), 100)
	var start_idx: int = timings.size() - count
	for i in range(start_idx, timings.size()):
		var ms: float = timings[i].duration_ms
		total += ms
		if ms > max_ms:
			max_ms = ms
	var avg: float = total / count if count > 0 else 0.0

	_stats_label.text = "Last: %.2fms | Avg(100): %.2fms | Max(100): %.2fms | Budget: 10ms" % [last_ms, avg, max_ms]

	# Graph (last 100 ticks)
	_graph_line.clear_points()
	if count < 2:
		return
	var graph_width: float = _graph_line.get_parent().size.x if _graph_line.get_parent().size.x > 0 else 400.0
	var graph_height: float = _graph_line.get_parent().size.y if _graph_line.get_parent().size.y > 0 else 150.0
	var max_display_ms: float = maxf(max_ms, 10.0) * 1.2  # scale to fit, at least 10ms
	for i in range(count):
		var x: float = (float(i) / float(count - 1)) * graph_width
		var ms: float = timings[start_idx + i].duration_ms
		var y: float = graph_height - (ms / max_display_ms) * graph_height
		_graph_line.add_point(Vector2(x, y))
		# Color red if over budget
	if max_ms > 10.0:
		_graph_line.default_color = Color.RED
	else:
		_graph_line.default_color = Color.GREEN
