extends Node3D
## Точка входа: строит мир и ставит фиксированную камеру. Камера-контролы — отдельный шаг.

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
	var ws := world_map.get_world_size()
	var cam: Camera3D = $Camera3D
	cam.position = Vector3(ws * 0.5, ws * 0.75, ws * 0.5 + ws * 0.5)
	cam.look_at(Vector3(ws * 0.5, 0.0, ws * 0.5))
	print("LongDarks: main scene ready, world %dx%d, terrain verts %d" % [world_map.size, world_map.size, world_view.terrain_vertex_count])
