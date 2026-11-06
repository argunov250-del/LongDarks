extends RefCounted
## Лёгкий стенд шага 15: Simulation + календарь + климат без жителей; годы прокручиваются тиками календаря.

var sim := Simulation.new(1)
var seasons := SeasonSystem.new()
var climate := ClimateSystem.new()
var events: Array = []


func _init() -> void:
	sim.register_system(seasons)
	sim.register_system(climate)
	seasons.attach(sim)
	climate.attach(sim)
	climate.bind(seasons)
	seasons.start_at(SeasonDefs.SPRING, 0.0)
	for topic in [ClimateSystem.TOPIC_FIRST_BIRDS, ClimateSystem.TOPIC_WARMING_MILESTONE]:
		sim.bus.subscribe(topic, func(p: Dictionary) -> void: events.append([topic, p]))


## Крутит календарь и климат (шаг 30 игровых секунд).
func run(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var dt := minf(30.0, left)
		seasons.tick(sim, dt)
		climate.tick(sim, dt)
		left -= dt


func run_years(n: float) -> void:
	run(n * seasons.year_length())


func count(topic: StringName) -> int:
	var c := 0
	for e in events:
		if e[0] == topic:
			c += 1
	return c
