extends Node
## Thin Node wrapper around MapBakeJob so it can be run from inside the
## SceneTree (from MapData on first boot in editor).

func bake() -> void:
	var job: MapBakeJob = MapBakeJob.new()
	job.run()
