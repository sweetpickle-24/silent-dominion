extends Control
class_name MapCanvas
## A thin Control that defers its `_draw()` to an external drawer and
## forwards its `_gui_input` events through a signal. The actual map
## logic (polygon geometry, hit-testing, kingdom colouring) lives in
## `map_view.gd`; this node just provides a canvas it can paint on
## and click against.
##
## The canvas is sized from the outside (typically the clipped map
## viewport); its transform — `scale` and `position` — is where the
## pan/zoom state ends up. All polygon coordinates are expressed in
## the canvas's own local space so that scale/position apply uniformly.

signal canvas_gui_input(event: InputEvent)
signal canvas_resized

var drawer: Node = null


func _ready() -> void:
	resized.connect(func() -> void: canvas_resized.emit())


func _gui_input(event: InputEvent) -> void:
	canvas_gui_input.emit(event)


func _draw() -> void:
	if drawer != null and drawer.has_method("draw_map_canvas"):
		drawer.call("draw_map_canvas", self)
