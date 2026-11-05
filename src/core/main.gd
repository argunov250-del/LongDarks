extends Node3D
## Точка входа: строит мир и настраивает камеру (CameraRig).

const DEFAULT_WORLD_SEED := 20260401

var world_map: WorldMap
var world_view: WorldView
var economy: EconomySystem
var construction: ConstructionSystem
var production: ProductionSystem
var buildings_view: BuildingsView
var build_controller: BuildController

## Плейсхолдеры баланса стартового склада.
const START_STORAGE_CAPACITY := 500
const START_RESOURCES := {
	&"logs": 20, &"planks": 10, &"stone": 10, &"scrap_metal": 15,
	&"firewood": 30, &"potato": 25, &"grain": 20, &"spare_parts": 5,
}


func _ready() -> void:
	world_map = WorldMap.new(DEFAULT_WORLD_SEED)
	SimRunner.sim.register_system(world_map)
	economy = EconomySystem.new(world_map)
	SimRunner.sim.register_system(economy)
	_create_starting_storage()
	construction = ConstructionSystem.new(world_map, economy)
	SimRunner.sim.register_system(construction)
	construction.attach(SimRunner.sim)
	production = ProductionSystem.new(construction, economy)
	SimRunner.sim.register_system(production)
	production.attach(SimRunner.sim)
	world_view = WorldView.new()
	world_view.name = "World"
	add_child(world_view)
	world_view.build(world_map)
	buildings_view = BuildingsView.new()
	buildings_view.name = "Buildings"
	add_child(buildings_view)
	buildings_view.setup(construction)
	var rig: CameraRig = $CameraRig
	rig.setup(world_map, $CameraRig/Camera3D)
	SimRunner.sim.register_system(rig.save_system)
	build_controller = BuildController.new()
	build_controller.name = "BuildController"
	add_child(build_controller)
	build_controller.setup(construction, $CameraRig/Camera3D, $UI/HUD, world_view, SimRunner.sim)
	build_controller.production = production
	print("LongDarks: main scene ready, world %dx%d, terrain verts %d" % [world_map.size, world_map.size, world_view.terrain_vertex_count])


func _create_starting_storage() -> void:
	var f := world_map.factory_cell
	var s := Storage.new(START_STORAGE_CAPACITY, world_map.cell_center(f.x, f.y))
	economy.add_storage(s)
	for k in START_RESOURCES:
		s.add(k, START_RESOURCES[k])
