extends SceneTree
## CLI entry for map baking.
##
## Run from the repo root:
##   godot --headless -s scripts/map_bake_main.gd
##
## Regenerates:
##   res://assets/map/generated/{provinces,terrain,shading}.png
##   res://data/map_cells.json
##
## Also triggered inline on first boot from MapData when the baked
## assets are missing, but this entry point is faster than booting
## the full game.

func _initialize() -> void:
	var job: MapBakeJob = MapBakeJob.new()
	job.run()
	quit(0)
