extends "res://tests/test_case.gd"

const Env = preload("res://tests/villagers/villager_env.gd")
const SLOT := "__test_villagers"


func _fresh() -> Env:
	return Env.new(5000, {&"logs": 40, &"planks": 50, &"stone": 50}, 5)


func _snap(e: Env) -> Dictionary:
	var vs := e.vs
	var list := []
	for v: Villager in vs.villager_list():
		list.append([v.id, v.display_name, String(v.sex), v.age, v.backstory, String(v.profession), v.traits.map(func(t): return String(t)),
			v.is_hero, v.immortal, v.arriving, snappedf(v.pos.x, 0.001), snappedf(v.pos.z, 0.001), v.task.duplicate()])
	return {"list": list, "dog": [snappedf(vs.dog.pos.x, 0.001), snappedf(vs.dog.pos.z, 0.001), vs.dog.anxious_level],
		"prio": vs.priorities.duplicate(), "bprio": vs.building_priorities.duplicate(), "stock": vs.house_stock.duplicate(),
		"arrival": snappedf(vs.next_arrival_in, 0.001)}


func test_round_trip_through_save_file() -> void:
	var e := _fresh()
	var house := e.add_done(&"dugout", 10.0, 0.0)
	e.place_near_hub(&"izba", 20.0, 10.0)
	e.vs.arrival_min = 30.0
	e.vs.arrival_max = 60.0
	e.vs.next_arrival_in = 100.0
	for i in 3:
		e.vs.spawn_newcomer()
	e.vs.set_priority(TaskDefs.FELL, 3)
	e.vs.set_priority(TaskDefs.CHORES, 0)
	e.vs.set_building_priority(house, 1)
	e.vs.dog.set_anxious(0.6)
	e.vs.house_stock[house] = 4
	e.run(25.0)
	var busy := 0
	for v: Villager in e.vs.villager_list():
		if not v.task.is_empty():
			busy += 1
	assert_true(busy >= 2, "some villagers have tasks")
	var before := _snap(e)
	assert_eq(SaveManager.save(e.sim, SLOT), OK)

	var e2 := _fresh()
	e2.vs.start_new_game()
	assert_eq(SaveManager.load_slot(e2.sim, SLOT), OK)
	var after := _snap(e2)
	assert_eq(after["list"], before["list"], "villagers incl. positions and tasks")
	assert_eq(after["dog"], before["dog"])
	assert_eq(after["prio"], before["prio"])
	assert_eq(after["bprio"], before["bprio"])
	assert_eq(after["stock"], before["stock"])
	assert_eq(after["arrival"], before["arrival"])
	assert_true(e2.vs.get_hero().immortal)
	# Продолжение игры идёт одинаково
	e.run(30.0)
	e2.run(30.0)
	assert_eq(_snap(e2)["list"], _snap(e)["list"], "same continuation after load")
	SaveManager.delete_slot(SLOT)


func test_load_ignores_garbage() -> void:
	var e := _fresh()
	e.vs.load_state({"villagers": [{"id": 5, "profession": "nope", "traits": ["lazy", "bogus"], "task": {"kind": "build", "target": 3}}, 7, {"id": 0}],
		"priorities": {"build": 99, "zzz": 1}, "next_arrival_in": -5})
	assert_eq(e.vs.population(), 1)
	var v := e.vs.get_villager(5)
	assert_true(VillagerDefs.PROFESSIONS.has(v.profession))
	assert_eq(v.traits, [&"lazy"] as Array[StringName])
	assert_eq(e.vs.get_priority(TaskDefs.BUILD), 3)
	assert_true(e.vs.next_arrival_in > 0.0)
	assert_true(v.task.is_empty(), "task without key dropped on load")
	e.run(5.0)  # задача на несуществующую стройку не ломает тик
	assert_true(v.task.get("kind", &"") != &"build")
