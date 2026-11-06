extends Node3D
## Точка входа: строит мир и настраивает камеру (CameraRig).

const DEFAULT_WORLD_SEED := 20260401

var world_map: WorldMap
var seasons: SeasonSystem
var weather: WeatherSystem
var weather_visuals: WeatherVisuals
var climate: ClimateSystem
var climate_birds: ClimateBirds
var food: FoodSystem
var food_view: FoodView
var restoration: RestorationSystem
var restoration_view: RestorationView
var season_visuals: SeasonVisuals
var world_view: WorldView
var economy: EconomySystem
var construction: ConstructionSystem
var production: ProductionSystem
var villagers: VillagerSystem
var villagers_view: VillagersView
var buildings_view: BuildingsView
var build_controller: BuildController


func _ready() -> void:
	world_map = WorldMap.new(DEFAULT_WORLD_SEED)
	SimRunner.sim.register_system(world_map)
	seasons = SeasonSystem.new()
	SimRunner.sim.register_system(seasons)
	seasons.attach(SimRunner.sim)
	economy = EconomySystem.new(world_map)
	SimRunner.sim.register_system(economy)
	StartState.create_storage(world_map, economy)
	construction = ConstructionSystem.new(world_map, economy)
	SimRunner.sim.register_system(construction)
	construction.attach(SimRunner.sim)
	production = ProductionSystem.new(construction, economy)
	SimRunner.sim.register_system(production)
	production.attach(SimRunner.sim)
	villagers = VillagerSystem.new(world_map, economy, construction, production)
	SimRunner.sim.register_system(villagers)
	villagers.attach(SimRunner.sim)
	villagers.start_new_game()
	seasons.bind(economy, construction, villagers)
	StartState.populate(construction, villagers, seasons)
	weather = WeatherSystem.new()
	SimRunner.sim.register_system(weather)  # после жителей: тикает последним
	weather.attach(SimRunner.sim)
	weather.bind(seasons, construction, villagers)
	climate = ClimateSystem.new()
	SimRunner.sim.register_system(climate)
	climate.attach(SimRunner.sim)
	climate.bind(seasons)
	food = FoodSystem.new()
	SimRunner.sim.register_system(food)
	food.attach(SimRunner.sim)
	food.bind(economy, world_map, construction, seasons, weather, climate)
	villagers.food = food
	restoration = RestorationSystem.new()
	SimRunner.sim.register_system(restoration)
	restoration.attach(SimRunner.sim)
	restoration.bind(economy, world_map, construction, food, climate, seasons)
	world_view = WorldView.new()
	world_view.name = "World"
	add_child(world_view)
	world_view.build(world_map)
	buildings_view = BuildingsView.new()
	buildings_view.name = "Buildings"
	add_child(buildings_view)
	buildings_view.household = villagers.household
	buildings_view.villagers = villagers
	buildings_view.setup(construction)
	villagers_view = VillagersView.new()
	villagers_view.name = "Villagers"
	add_child(villagers_view)
	villagers_view.setup(villagers)
	$UI/HUD.bind_villagers(villagers)
	$UI/HUD.bind_seasons(seasons)
	$UI/HUD.bind_weather(SimRunner.sim)
	season_visuals = SeasonVisuals.new()
	season_visuals.name = "SeasonVisuals"
	add_child(season_visuals)
	season_visuals.weather = weather
	season_visuals.setup(seasons, world_view, $WorldEnvironment, $DirectionalLight3D)
	weather_visuals = WeatherVisuals.new()
	weather_visuals.name = "WeatherVisuals"
	add_child(weather_visuals)
	weather_visuals.setup(weather, world_view, construction, $CameraRig/Camera3D)
	climate_birds = ClimateBirds.new()
	climate_birds.name = "ClimateBirds"
	add_child(climate_birds)
	climate_birds.setup(climate, seasons, world_map, economy.deposits, func() -> Vector3: return weather_visuals._focus_point())
	food_view = FoodView.new()
	food_view.name = "FoodView"
	add_child(food_view)
	food_view.setup(food, world_map, SimRunner.sim)
	restoration_view = RestorationView.new()
	restoration_view.name = "RestorationView"
	add_child(restoration_view)
	restoration_view.setup(restoration, world_map, economy.deposits, world_view, SimRunner.sim)
	var rig: CameraRig = $CameraRig
	rig.setup(world_map, $CameraRig/Camera3D)
	SimRunner.sim.register_system(rig.save_system)
	build_controller = BuildController.new()
	build_controller.name = "BuildController"
	add_child(build_controller)
	build_controller.setup(construction, $CameraRig/Camera3D, $UI/HUD, world_view, SimRunner.sim)
	build_controller.production = production
	build_controller.villagers = villagers
	build_controller.villagers_view = villagers_view
	build_controller.food = food
	build_controller.restoration = restoration
	print("LongDarks: main scene ready, world %dx%d, terrain verts %d" % [world_map.size, world_map.size, world_view.terrain_vertex_count])
