extends "res://tests/social/social_env.gd"
## Стенд шага 24: психика + NeighbourSystem (без ИИ-визитов: по умолчанию тесты задают отношения сами).

var nb: NeighbourSystem
var nb_events: Array = []


func _init(cap: int = 5000, resources: Dictionary = {}, seed_value: int = 7) -> void:
	super._init(cap, resources, seed_value)
	nb = NeighbourSystem.new(seed_value)
	sim.register_system(nb)
	nb.attach(sim)
	nb.bind(vs, eco, con, seasons, social, null, world)
	for topic in [NeighbourSystem.TOPIC_CARAVAN, NeighbourSystem.TOPIC_REQUEST, NeighbourSystem.TOPIC_THEFT, NeighbourSystem.TOPIC_RAID,
			NeighbourSystem.TOPIC_MIGRATE, NeighbourSystem.TOPIC_PACT_BROKEN]:
		sim.bus.subscribe(topic, func(p: Dictionary) -> void: nb_events.append([topic, p]))


func ncount(topic: StringName) -> int:
	var c := 0
	for e in nb_events:
		if e[0] == topic:
			c += 1
	return c


func z() -> Dictionary:
	return nb.get_neighbour(&"zarechye")


## Прогон суток ИИ (без отрядов).
func days(k: int) -> void:
	for _i in k:
		nb.step_days(1.0)
