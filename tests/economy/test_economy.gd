extends "res://tests/test_case.gd"

const SEED := 12345
const DAY := 1440.0


func _eco() -> EconomySystem:
	return EconomySystem.new(WorldMap.new(SEED))


func test_add_remove_capacity() -> void:
	var s := Storage.new(10)
	assert_eq(s.add(&"logs", 7), 7)
	assert_eq(s.add(&"stone", 7), 3, "capped by free space")
	assert_eq(s.free_space(), 0)
	assert_eq(s.remove(&"logs", 100), 7)
	assert_false(s.has(&"logs"))
	assert_eq(s.remove(&"logs", 1), 0)
	assert_eq(s.add(&"nonsense", 1), 0)
	assert_true(s.has(&"stone", 3))


func test_catalog() -> void:
	assert_eq(ResourceDefs.all_ids().size(), 24)
	assert_true(ResourceDefs.is_perishable(&"milk"))
	assert_false(ResourceDefs.is_perishable(&"logs"))
	assert_eq(ResourceDefs.display_name(&"logs"), "бревно")


func test_atomic_consume() -> void:
	var e := _eco()
	var a := e.add_storage(Storage.new(100))
	var b := e.add_storage(Storage.new(100))
	a.add(&"logs", 5)
	b.add(&"logs", 5)
	b.add(&"stone", 2)
	assert_eq(e.total(&"logs"), 10)
	assert_false(e.consume({&"logs": 8, &"stone": 3}))
	assert_eq(e.total(&"logs"), 10, "no partial removal")
	assert_eq(e.total(&"stone"), 2)
	assert_true(e.can_afford({&"logs": 8, &"stone": 2}))
	assert_true(e.consume({&"logs": 8, &"stone": 2}))
	assert_eq(e.total(&"logs"), 2)
	assert_eq(e.total(&"stone"), 0)


func test_spoilage_rules() -> void:
	var e := _eco()
	var plain := e.add_storage(Storage.new(1000))
	var cellar := e.add_storage(Storage.new(1000, Vector3.ZERO, true))
	var cold := e.add_storage(Storage.new(1000, Vector3.ZERO, false, true))
	for s in [plain, cellar, cold]:
		s.add(&"milk", 100)
		s.add(&"logs", 100)
	var sim := Simulation.new(1)
	e.tick(sim, DAY)
	assert_true(plain.amount(&"milk") < 100)
	assert_eq(plain.amount(&"logs"), 100)
	assert_eq(cellar.amount(&"milk"), 100)
	assert_eq(cold.amount(&"milk"), 100)
	# ambient_cold останавливает порчу
	var before := plain.amount(&"milk")
	e.set_ambient_cold(true)
	e.tick(sim, DAY)
	assert_eq(plain.amount(&"milk"), before)


func test_fractional_spoilage_deterministic() -> void:
	var run := func() -> int:
		var e := _eco()
		var s := e.add_storage(Storage.new(1000))
		s.add(&"potato", 10)  # 2%/сутки: 0.2 ед/сутки
		var sim := Simulation.new(1)
		for _i in 1440:
			e.tick(sim, 1.0)  # одни сутки мелкими шагами
		return s.amount(&"potato")
	assert_eq(run.call(), run.call())
	assert_eq(run.call(), 10, "0.2 units lost < 1 so nothing yet")
	var e := _eco()
	var s := e.add_storage(Storage.new(1000))
	s.add(&"potato", 10)
	var sim := Simulation.new(1)
	for _i in 5:
		e.tick(sim, DAY)
	assert_eq(s.amount(&"potato"), 9, "accumulated fraction crosses 1")


func test_changed_event() -> void:
	var e := _eco()
	var sim := Simulation.new(1)
	e.tick(sim, 0.0)
	var count := [0]
	sim.bus.subscribe(EconomySystem.TOPIC_RESOURCES_CHANGED, func(_p): count[0] += 1)
	var s := e.add_storage(Storage.new(10))
	s.add(&"logs", 5)
	e.consume({&"logs": 2})
	assert_true(count[0] >= 1)


func _find(m: WorldMap, t: int) -> Vector2i:
	for cz in m.size:
		for cx in m.size:
			if m.cell_type(cx, cz) == t:
				return Vector2i(cx, cz)
	return Vector2i(-1, -1)


func test_deposit_finite() -> void:
	var m := WorldMap.new(SEED)
	var d := Deposits.new(m)
	var f := _find(m, WorldMap.Terrain.FOREST)
	var r := _find(m, WorldMap.Terrain.RUINS)
	assert_eq(d.resource_at(f), &"logs")
	assert_eq(d.resource_at(r), &"scrap_metal")
	var n := d.remaining(f)
	assert_true(n >= Deposits.TREES_MIN and n <= Deposits.TREES_MAX)
	assert_eq(d.take(f, 1), 1)
	assert_eq(d.take(f, 100), n - 1)
	assert_eq(d.take(f, 1), 0)
	assert_true(d.is_depleted(f))
	assert_false(d.is_depleted(r))
	assert_eq(d.resource_at(Vector2i(-1, -1)), &"")
	assert_eq(Deposits.new(m).remaining(f), n, "deterministic")


func test_save_load_roundtrip() -> void:
	var m := WorldMap.new(SEED)
	var e := EconomySystem.new(m)
	var a := e.add_storage(Storage.new(200, Vector3(1, 2, 3)))
	var b := e.add_storage(Storage.new(50, Vector3.ZERO, true))
	a.add(&"potato", 40)
	a.add(&"logs", 9)
	b.add(&"milk", 5)
	e.set_ambient_cold(true)
	var f := _find(m, WorldMap.Terrain.FOREST)
	e.deposits.take(f, 2)
	var sim := Simulation.new(1)
	sim.register_system(e)
	e.ambient_cold = false
	e.tick(sim, DAY * 3.0)
	var json := JSON.stringify(e.save_state())
	var parsed = JSON.parse_string(json)
	var e2 := EconomySystem.new(WorldMap.new(SEED))
	e2.load_state(parsed)
	assert_eq(e2.storages.size(), 2)
	assert_eq(e2.total(&"potato"), e.total(&"potato"))
	assert_eq(e2.total(&"logs"), 9)
	assert_eq(e2.storages[0].position, Vector3(1, 2, 3))
	assert_true(e2.storages[1].cellar)
	assert_eq(e2.storages[1].amount(&"milk"), 5)
	assert_eq(e2.deposits.remaining(f), e.deposits.remaining(f))
	assert_eq(e2.add_storage(Storage.new(1)).id, 3)
	# дальнейшая порча идентична
	e.tick(sim, DAY)
	e2.tick(sim, DAY)
	assert_eq(e2.total(&"potato"), e.total(&"potato"))
	assert_eq(e2.total(&"milk"), e.total(&"milk"))
	# через Simulation
	var sim2 := Simulation.new(1)
	var e3 := EconomySystem.new(WorldMap.new(SEED))
	sim2.register_system(e3)
	sim2.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	assert_eq(e3.total(&"logs"), 9)
