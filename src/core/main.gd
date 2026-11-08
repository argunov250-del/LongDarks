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
var vehicles: VehicleSystem
var vehicles_view: VehiclesView
var season_visuals: SeasonVisuals
var world_view: WorldView
var economy: EconomySystem
var construction: ConstructionSystem
var production: ProductionSystem
var villagers: VillagerSystem
var social: SocialSystem
var family: FamilySystem
var neighbours: NeighbourSystem
var neighbours_view: NeighboursView
var villagers_view: VillagersView
var buildings_view: BuildingsView
var build_controller: BuildController
var drive: ManualDriveController
var drive_settings: DriveSettings
var settings: GameSettings
var session: GameSession
var career: CareerSystem


func _ready() -> void:
	var pend := SimRunner.take_pending()
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
	villagers.household.restoration = restoration
	restoration.bind(economy, world_map, construction, food, climate, seasons)
	vehicles = VehicleSystem.new()
	SimRunner.sim.register_system(vehicles)
	vehicles.attach(SimRunner.sim)
	vehicles.bind(world_map, economy, construction, production, villagers, food, seasons, weather)
	vehicles.populate_start()
	social = SocialSystem.new(villagers)  # step 22: mental needs, friendship, holidays (design/gdd/mental-needs.md)
	SimRunner.sim.register_system(social)
	social.attach(SimRunner.sim)
	social.bind(seasons)
	family = FamilySystem.new(villagers)  # step 23: couples, children, aging (design/gdd/families.md)
	SimRunner.sim.register_system(family)
	family.attach(SimRunner.sim)
	family.bind(social)
	neighbours = NeighbourSystem.new(world_map.seed if "seed" in world_map else 1)  # step 24 (design/gdd/neighbours.md)
	SimRunner.sim.register_system(neighbours)
	neighbours.attach(SimRunner.sim)
	neighbours.bind(villagers, economy, construction, seasons, social, vehicles, world_map)
	settings = GameSettings.new()  # step 25 (design/gdd/modes-difficulty.md)
	if pend.get("settings") is Dictionary:
		settings.from_dict(pend["settings"])
	settings.bind(seasons, weather, neighbours)
	SimRunner.sim.register_system(settings)
	settings.apply()
	career = CareerSystem.new()  # step 26 (design/gdd/career.md); inactive outside career mode
	SimRunner.sim.register_system(career)
	career.attach(SimRunner.sim)
	career.bind(villagers, seasons, economy, neighbours)
	if settings.mode == ModeDefs.CAREER and not pend.get("load_slot") is String:
		career.start_new()
	session = GameSession.new(SimRunner.sim, settings, seasons, villagers)
	$UI/HUD.bind_session(session)
	$UI/HUD.bind_career(career, SimRunner.sim)
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
	$UI/HUD.bind_social(social)
	$UI/HUD.bind_family(family)
	$UI/HUD.bind_neighbours(neighbours, SimRunner.sim)
	neighbours_view = NeighboursView.new()
	neighbours_view.name = "NeighboursView"
	add_child(neighbours_view)
	neighbours_view.setup(neighbours)
	$UI/HUD.bind_weather(SimRunner.sim)
	$UI/HUD.bind_vehicles(SimRunner.sim)
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
	vehicles_view = VehiclesView.new()
	vehicles_view.name = "VehiclesView"
	add_child(vehicles_view)
	vehicles_view.setup(vehicles, world_map, SimRunner.sim)
	var rig: CameraRig = $CameraRig
	rig.setup(world_map, $CameraRig/Camera3D)
	SimRunner.sim.register_system(rig.save_system)
	build_controller = BuildController.new()
	build_controller.name = "BuildController"
	add_child(build_controller)
	build_controller.setup(construction, $CameraRig/Camera3D, $UI/HUD, world_view, SimRunner.sim)
	build_controller.production = production
	build_controller.villagers = villagers
	build_controller.social = social
	build_controller.family = family
	build_controller.villagers_view = villagers_view
	build_controller.food = food
	build_controller.restoration = restoration
	build_controller.vehicles = vehicles
	drive_settings = DriveSettings.new()
	drive_settings.load()
	$UI/HUD.drive_settings = drive_settings
	drive = ManualDriveController.new()
	drive.name = "ManualDrive"
	add_child(drive)
	drive.setup(vehicles, rig, $UI/HUD, drive_settings)
	build_controller.drive = drive
	if pend.get("load_slot") is String and session.load_slot(pend["load_slot"]) != OK:
		push_warning("LongDarks: cannot load slot %s" % pend["load_slot"])
	print("LongDarks: main scene ready, world %dx%d, terrain verts %d" % [world_map.size, world_map.size, world_view.terrain_vertex_count])


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and session != null:
		session.autosave.on_app_paused()
