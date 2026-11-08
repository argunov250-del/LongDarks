extends "res://tests/social/social_env.gd"
## Стенд шага 23: психика + семья (FamilySystem). Сутки 400 с.

var family: FamilySystem
var fam_events: Array = []


func _init(cap: int = 5000, resources: Dictionary = {}, seed_value: int = 7) -> void:
	super._init(cap, resources, seed_value)
	family = FamilySystem.new(vs)
	sim.register_system(family)
	family.attach(sim)
	family.bind(social)
	for topic in [FamilySystem.TOPIC_WEDDING, FamilySystem.TOPIC_BORN, FamilySystem.TOPIC_GREW, VillagerSystem.TOPIC_DIED]:
		sim.bus.subscribe(topic, func(p: Dictionary) -> void: fam_events.append([topic, p]))


func fcount(topic: StringName) -> int:
	var c := 0
	for e in fam_events:
		if e[0] == topic:
			c += 1
	return c


## Взрослый нужного пола с полными нуждами; герой держится вдали, чтобы не мешал.
func adult(sex: StringName, prof: StringName = &"cook", age: int = 28) -> Villager:
	var v := add_villager(prof)
	v.sex = sex
	v.age = age
	v.display_name = ("Иван Смирнов" if sex == &"m" else "Анна Волкова")
	feed(v)
	return v


func house(dx: float = 10.0) -> int:
	return add_done(&"izba", dx, 0.0)


## Пара в одном доме (брак заключён).
func couple(home: int) -> Array:
	var m := adult(&"m")
	var f := adult(&"f")
	m.home_id = home
	f.home_id = home
	family.marry(m, f)
	return [f, m]
