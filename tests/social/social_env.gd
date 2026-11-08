extends "res://tests/villagers/villager_env.gd"
## Стенд шага 22: стенд жителей + психика (SocialSystem) + календарь. Сутки 400 с, день.

var social: SocialSystem
var seasons: SeasonSystem
var events: Array = []


func _init(cap: int = 5000, resources: Dictionary = {}, seed_value: int = 7) -> void:
	super._init(cap, resources, seed_value)
	sim.clock.set_day_length(400.0)
	enable_needs(10.0)
	seasons = SeasonSystem.new()
	sim.register_system(seasons)
	seasons.attach(sim)
	social = SocialSystem.new(vs)
	sim.register_system(social)
	social.attach(sim)
	social.bind(seasons)
	seasons.start_at(SeasonDefs.AUTUMN, 0.3)  # без календарных праздников, пока тест сам не включит
	for topic in [SocialSystem.TOPIC_QUARREL, SocialSystem.TOPIC_LEFT, SocialSystem.TOPIC_HOLIDAY_STARTED, SocialSystem.TOPIC_HOLIDAY_ENDED]:
		sim.bus.subscribe(topic, func(p: Dictionary) -> void: events.append([topic, p]))


func count(topic: StringName) -> int:
	var c := 0
	for e in events:
		if e[0] == topic:
			c += 1
	return c


## Житель с полными телесными нуждами (герой в стороне), заданным настроением-нуждами.
func person(profession: StringName = &"cook", traits: Array = []) -> Villager:
	return add_villager(profession, traits)


func set_mental(v: Villager, x: float) -> void:
	for n in SocialDefs.NEEDS:
		social.set_need(v, n, x)


## Телесные нужды держим полными (тест психики, а не голода).
func feed(v: Villager) -> void:
	for n in NeedsDefs.NEEDS:
		v.set_need(n, 1.0)
