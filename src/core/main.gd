extends Node3D
## Точка входа: строит мир и настраивает камеру (CameraRig).

const DEFAULT_WORLD_SEED := 20260401

var world_map: WorldMap
var world_view: WorldView


func _ready() -> void:
	world_map = WorldMap.new(DEFAULT_WORLD_SEED)
	SimRunner.sim.register_system(world_map)
	world_view = WorldView.new()
	world_view.name = "World"
	add_child(world_view)
	world_view.build(world_map)
	var rig: CameraRig = $CameraRig
	rig.setup(world_map, $CameraRig/Camera3D)
	SimRunner.sim.register_system(rig.save_system)
	print("LongDarks: main scene ready, world %dx%d, terrain verts %d" % [world_map.size, world_map.size, world_view.terrain_vertex_count])
