extends "res://tests/seasons/season_env.gd"
## Стенд шага 14: стенд календаря + WeatherSystem (тикает последним).

var weather: WeatherSystem


func _init(cap: int = 5000, resources: Dictionary = {}, seed_value: int = 7) -> void:
	super(cap, resources, seed_value)
	weather = WeatherSystem.new()
	sim.register_system(weather)
	weather.attach(sim)
	weather.bind(seasons, con, vs)
	weather.set_frequency_multiplier(0.0)  # случайных событий нет, пока тест не включит


## Лес с деревьями: клетка (первая найденная вблизи центра посёлка), вокруг — тоже лес.
func forest_cell(min_neighbors: int = 0) -> Vector2i:
	var hc := world.cell_of(vs.hub_position().x, vs.hub_position().z)
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	for cz in world.size:
		for cx in world.size:
			var c := Vector2i(cx, cz)
			if eco.deposits.resource_at(c) != &"logs" or eco.deposits.remaining(c) <= 0:
				continue
			var n := 0
			for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if eco.deposits.resource_at(c + off) == &"logs":
					n += 1
			if n < min_neighbors:
				continue
			var d := (c - hc).length_squared()
			if d < bd:
				bd = d
				best = c
	return best


## Включает сезон и время (после создания: ставит календарь, сутки 3+ чтобы события были возможны).
func at_day(season: StringName, p: float, hour: float, day: int = 4) -> void:
	seasons.start_at(season, p)
	sim.clock.set_total_seconds((float(day - 1) * 24.0 + hour) / 24.0 * sim.clock.day_seconds())
	weather._rolled_day = day
