extends RefCounted
## Test rig for step 16: villager env + FoodSystem (no SeasonSystem: season is forced).

const Env = preload("res://tests/villagers/villager_env.gd")

var e: Env
var food: FoodSystem
var climate: ClimateSystem
var weather: WeatherSystem


func _init(season: StringName = SeasonDefs.SPRING) -> void:
	e = Env.new()
	food = FoodSystem.new()
	climate = ClimateSystem.new()
	weather = WeatherSystem.new()
	weather.world = e.world
	food.season_override = season
	food.bind(e.eco, e.world, e.con, null, weather, climate)
	e.sim.register_system(food)
	e.vs.food = food


func field_cells(n: int = 6, crop: StringName = &"grain") -> Array[Vector2i]:
	var hub := e.vs.hub_position()
	for k in 60:
		var a := float(k) * 2.4
		var p := hub + Vector3(cos(a), 0.0, sin(a)) * (8.0 + k * 1.2)
		var cells := food.field_cells_in_brush(p, 5.0, true)
		if cells.size() >= n:
			cells = cells.slice(0, n)
			food.designate(cells, crop)
			return cells
	return []


func idx(c: Vector2i) -> int:
	return c.y * e.world.size + c.x


## Plows, sows and grows one cell to RIPE (spring -> summer), leaves season at autumn.
func ripen(c: Vector2i) -> void:
	food.season_override = SeasonDefs.SPRING
	food.finish(&"field", idx(c))
	food.finish(&"field", idx(c))
	food.season_override = SeasonDefs.SUMMER
	for i in 40:
		food.tick(e.sim, 60.0)
	food.season_override = SeasonDefs.AUTUMN
