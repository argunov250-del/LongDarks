extends "res://tests/test_case.gd"

const SEED := 12345
const P := "__test_prod_"


class Env extends RefCounted:
	var sim := Simulation.new(1)
	var world: WorldMap
	var eco: EconomySystem
	var con: ConstructionSystem
	var prod: ProductionSystem
	var store: Storage

	func _init(capacity: int = 5000) -> void:
		world = WorldMap.new(SEED)
		eco = EconomySystem.new(world)
		con = ConstructionSystem.new(world, eco)
		prod = ProductionSystem.new(con, eco)
		sim.register_system(world)
		sim.register_system(eco)
		sim.register_system(con)
		sim.register_system(prod)
		con.attach(sim)
		prod.attach(sim)
		store = Storage.new(capacity, Vector3.ZERO)
		eco.add_storage(store)

	## Здание сразу готовое (или на заданной стадии).
	func building(type: StringName, stage: int = BuildingDefs.Stage.DONE) -> int:
		var b := Building.new()
		b.id = 100 + con.buildings.size()
		b.type = type
		b.stage = stage
		con.buildings[b.id] = b
		return b.id

	func run(seconds: float) -> void:
		for i in int(round(seconds / 0.1)):
			prod.tick(sim, 0.1)


class Truck extends Repairable:
	pass


func test_sawmill_cycle_consumes_and_produces() -> void:
	var e := Env.new()
	var id := e.building(&"sawmill")
	e.eco.deposit(&"logs", 4)
	e.run(1.0)  # старт: входы списаны
	assert_eq(e.eco.total(&"logs"), 2)
	assert_eq(e.eco.total(&"planks"), 0)
	assert_true(e.prod.progress_fraction(id) > 0.0)
	e.run(Recipes.duration(&"sawmill_planks"))
	assert_eq(e.eco.total(&"planks"), 3)
	e.run(Recipes.duration(&"sawmill_planks") + 1.0)
	assert_eq(e.eco.total(&"logs"), 0)
	assert_eq(e.eco.total(&"planks"), 6)


func test_other_recipes() -> void:
	var e := Env.new()
	var oid := e.building(&"oil_press")
	var wid := e.building(&"workshop")
	e.eco.deposit(&"rapeseed", 3)
	e.eco.deposit(&"scrap_metal", 2)
	e.run(45.0)
	assert_eq(e.eco.total(&"oil"), 1)
	assert_eq(e.eco.total(&"spare_parts"), 1)
	assert_eq(e.prod.recipe_of(oid), &"oil_press_oil")
	assert_eq(e.prod.recipe_of(wid), &"workshop_parts")


func test_stalls_on_missing_input() -> void:
	var e := Env.new()
	var id := e.building(&"sawmill")
	var seen := []
	e.sim.bus.subscribe(ProductionSystem.TOPIC_STALLED, func(p): seen.append(p))
	e.eco.deposit(&"logs", 1)
	e.run(5.0)
	assert_eq(e.prod.stall_reason(id), &"no_input")
	assert_eq(e.eco.total(&"logs"), 1, "nothing lost")
	assert_eq(seen.size(), 1, "stalled emitted once")
	e.eco.deposit(&"logs", 1)
	e.run(1.0)
	assert_eq(e.prod.stall_reason(id), &"")
	assert_eq(e.eco.total(&"logs"), 0)


func test_stalls_on_full_storage_without_losing_goods() -> void:
	var e := Env.new(5)
	var id := e.building(&"sawmill")
	e.eco.deposit(&"logs", 2)
	e.eco.deposit(&"stone", 3)  # занято 5/5, после списания логов свободно 2 < 3
	e.run(Recipes.duration(&"sawmill_planks") + 5.0)
	assert_eq(e.prod.stall_reason(id), &"no_space")
	assert_eq(e.eco.total(&"planks"), 0)
	assert_eq(e.prod.progress_fraction(id), 1.0, "finished cycle is held")
	e.store.remove(&"stone", 3)
	e.run(0.5)
	assert_true(e.prod.stall_reason(id) != &"no_space")
	assert_eq(e.eco.total(&"planks"), 3, "goods delivered after space frees")


func test_only_completed_buildings_produce() -> void:
	var e := Env.new()
	var id := e.building(&"sawmill", BuildingDefs.Stage.ROOF)
	e.eco.deposit(&"logs", 10)
	e.run(60.0)
	assert_eq(e.eco.total(&"logs"), 10)
	assert_true(e.prod.get_state(id).is_empty())
	assert_false(e.prod.set_paused(id, true))
	assert_false(e.prod.is_producing_building(e.building(&"warehouse")), "non-production type")


func test_pause_and_resume() -> void:
	var e := Env.new()
	var id := e.building(&"sawmill")
	e.eco.deposit(&"logs", 4)
	e.run(5.0)
	var f := e.prod.progress_fraction(id)
	assert_true(e.prod.set_paused(id, true))
	e.run(30.0)
	assert_eq(e.prod.progress_fraction(id), f, "frozen while paused")
	assert_eq(e.eco.total(&"planks"), 0)
	e.prod.toggle_pause(id)
	e.run(20.0)
	assert_eq(e.eco.total(&"planks"), 3)


func test_set_recipe_validation() -> void:
	var e := Env.new()
	var id := e.building(&"sawmill")
	assert_false(e.prod.set_recipe(id, &"oil_press_oil"), "wrong building")
	assert_true(e.prod.set_recipe(id, &"sawmill_planks"))
	e.eco.deposit(&"logs", 2)
	e.run(2.0)
	assert_false(e.prod.set_recipe(id, &"sawmill_planks"), "mid-cycle refused")


func test_workshop_repair_consumes_parts_and_completes() -> void:
	var e := Env.new()
	var w := e.building(&"workshop")
	var t := Truck.new(&"truck1", 0.75)
	e.prod.register_repairable(t)
	e.eco.deposit(&"spare_parts", 5)
	var progress := []
	var done := []
	e.sim.bus.subscribe(ProductionSystem.TOPIC_REPAIR_PROGRESS, func(p): progress.append(p))
	e.sim.bus.subscribe(ProductionSystem.TOPIC_REPAIR_DONE, func(p): done.append(p))
	assert_true(e.prod.queue_repair(w, &"truck1"))
	assert_false(e.prod.queue_repair(w, &"truck1"), "already queued")
	assert_false(e.prod.queue_repair(w, &"nope"))
	e.run(Recipes.REPAIR_STEP_TIME * 4.0)
	assert_almost_eq(t.condition, 1.0)
	assert_eq(e.eco.total(&"spare_parts"), 2, "3 steps x 1 part")
	assert_eq(progress.size(), 3)
	assert_eq(done.size(), 1)
	assert_true(e.prod.repair_queue(w).is_empty())
	assert_false(e.prod.queue_repair(w, &"truck1"), "healthy")


func test_repair_waits_for_parts() -> void:
	var e := Env.new()
	var w := e.building(&"workshop")
	var t := Truck.new(&"t", 0.5)
	e.prod.register_repairable(t)
	e.prod.queue_repair(w, &"t")
	e.run(30.0)
	assert_eq(e.prod.stall_reason(w), &"no_input")
	assert_almost_eq(t.condition, 0.5)
	e.eco.deposit(&"spare_parts", 10)
	e.run(Recipes.REPAIR_STEP_TIME * 6.0)
	assert_almost_eq(t.condition, 1.0)
	assert_eq(e.eco.total(&"spare_parts"), 5)


func test_non_workshop_cannot_queue_repair() -> void:
	var e := Env.new()
	var s := e.building(&"sawmill")
	e.prod.register_repairable(Truck.new(&"t", 0.5))
	assert_false(e.prod.queue_repair(s, &"t"))


func test_save_load_mid_cycle_roundtrip() -> void:
	var a := Env.new()
	var id := a.building(&"sawmill")
	var w := a.building(&"workshop")
	var t := Truck.new(&"truck", 0.4)
	a.prod.register_repairable(t)
	a.eco.deposit(&"logs", 4)
	a.eco.deposit(&"spare_parts", 3)
	a.prod.queue_repair(w, &"truck")
	a.run(25.0)  # пила: цикл 1 завершён, цикл 2 идёт; ремонт: 2 шага
	a.prod.set_paused(id, false)
	var data := a.prod.save_state()
	var json: Variant = JSON.parse_string(JSON.stringify(data))
	var eco_json: Variant = JSON.parse_string(JSON.stringify(a.eco.save_state()))

	var b := Env.new()
	b.building(&"sawmill")
	b.building(&"workshop")
	var t2 := Truck.new(&"truck", 1.0)
	b.prod.load_state(json)  # раньше регистрации
	b.prod.register_repairable(t2)
	b.eco.load_state(eco_json)
	assert_almost_eq(t2.condition, t.condition)
	assert_almost_eq(b.prod.progress_fraction(id), a.prod.progress_fraction(id), 0.0001)
	assert_eq(b.prod.repair_queue(w), a.prod.repair_queue(w))
	a.run(60.0)
	b.run(60.0)
	assert_eq(b.eco.total(&"planks"), a.eco.total(&"planks"))
	assert_eq(b.eco.total(&"spare_parts"), a.eco.total(&"spare_parts"))
	assert_almost_eq(t2.condition, t.condition)
	assert_true(a.eco.total(&"planks") > 0)


func test_save_via_simulation() -> void:
	var a := Env.new()
	var id := a.building(&"sawmill")
	a.eco.deposit(&"logs", 2)
	a.run(5.0)
	var d := a.sim.to_dict()
	assert_true((d["systems"] as Dictionary).has("production"))
	assert_true(a.prod.progress_fraction(id) > 0.0)
	a.prod.set_paused(id, true)
	a.sim.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_false(a.prod.is_paused(id))
	assert_true(a.prod.progress_fraction(id) > 0.0)
