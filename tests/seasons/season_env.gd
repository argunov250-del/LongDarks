extends "res://tests/villagers/villager_env.gd"
## Стенд шага 13: стенд жителей + календарь (SeasonSystem), выставляющий хуки систем.

var seasons: SeasonSystem


func _init(cap: int = 5000, resources: Dictionary = {}, seed_value: int = 7) -> void:
	super(cap, resources, seed_value)
	seasons = SeasonSystem.new()
	sim.unregister_system(seasons)
	# календарь тикает первым — хуки выставлены до остальных систем
	var rest := sim.get_systems()
	for s in rest:
		sim.unregister_system(s)
	sim.register_system(seasons)
	for s in rest:
		sim.register_system(s)
	seasons.attach(sim)
	seasons.bind(eco, con, vs)


## Ставит календарь (сезон, доля) и час суток.
func at(season: StringName, p: float, hour: float = 12.0) -> void:
	set_hour(hour)
	seasons.start_at(season, p)
