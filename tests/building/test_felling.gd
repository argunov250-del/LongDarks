extends "res://tests/test_case.gd"

const SEED := 12345


class Env extends RefCounted:
	var sim := Simulation.new(1)
	var world: WorldMap
	var eco: EconomySystem
	var con: ConstructionSystem

	func _init(cap: int = 5000) -> void:
		world = WorldMap.new(SEED)
		eco = EconomySystem.new(world)
		con = ConstructionSystem.new(world, eco)
		sim.register_system(world)
		sim.register_system(eco)
		sim.register_system(con)
		eco.add_storage(Storage.new(cap, Vector3.ZERO))

	func run(seconds: float) -> void:
		for i in int(seconds / 0.1):
			con.tick(sim, 0.1)

	## Лесная клетка, вокруг которой можно поставить type.
	func forest_site(type: StringName) -> Vector3:
		for cz in range(6, world.size - 6):
			for cx in range(6, world.size - 6):
				if world.cell_type(cx, cz) == WorldMap.Terrain.FOREST:
					var p := world.cell_center(cx, cz)
					if con.validate_placement(type, p, 0.0)["ok"] and not con.footprint_tree_cells(Vector2(p.x, p.z), BuildingDefs.footprint(type), 0.0).is_empty():
						return p
		return Vector3(-1, 0, -1)


func test_dismantle_pauses_when_full_and_resumes() -> void:
	var e := Env.new(0)
	var rid: int = e.con.active_ruin_ids()[0]
	var y := e.con.ruin_yield(rid)
	var need := 0
	for k in y:
		need += y[k]
	var s := Storage.new(need - 1, Vector3.ZERO)
	e.eco.add_storage(s)
	e.con.start_dismantle(rid)
	e.run(BuildingDefs.DISMANTLE_WORK + 5.0)
	assert_true(e.con.is_ruin_active(rid), "paused")
	assert_true(e.con.is_dismantle_blocked(rid))
	assert_eq(s.used(), 0, "nothing lost or partially stored")
	s.capacity = need
	e.run(1.0)
	assert_false(e.con.is_ruin_active(rid))
	for k in y:
		assert_eq(e.eco.total(k), y[k], str(k))


func test_felling_yields_logs_and_clears_cell() -> void:
	var e := Env.new()
	var p := e.forest_site(&"cellar")
	assert_true(p.x >= 0.0)
	var cell := e.world.cell_of(p.x, p.z)
	var n0 := e.eco.deposits.remaining(cell)
	assert_true(n0 > 0)
	assert_eq(e.con.start_felling([cell] as Array[Vector2i]), 1)
	assert_eq(e.con.start_felling([cell] as Array[Vector2i]), 0, "once")
	e.run(BuildingDefs.FELL_WORK_PER_LOG * (n0 + 1))
	assert_eq(e.eco.total(&"logs"), n0)
	assert_eq(e.eco.deposits.remaining(cell), 0)
	assert_false(e.con.has_trees(cell))
	assert_false(e.con.is_felling(cell))


func test_felling_pauses_on_full_storage() -> void:
	var e := Env.new(0)
	var s := Storage.new(1, Vector3.ZERO)
	e.eco.add_storage(s)
	var p := e.forest_site(&"cellar")
	var cell := e.world.cell_of(p.x, p.z)
	var n0 := e.eco.deposits.remaining(cell)
	e.con.start_felling([cell] as Array[Vector2i])
	e.run(BuildingDefs.FELL_WORK_PER_LOG * (n0 + 2))
	assert_eq(s.amount(&"logs"), 1)
	assert_eq(e.eco.deposits.remaining(cell), n0 - 1, "no log lost")
	assert_true(e.con.is_felling_blocked())
	s.capacity = 100
	e.run(BuildingDefs.FELL_WORK_PER_LOG * (n0 + 1))
	assert_eq(s.amount(&"logs"), n0)
	assert_false(e.con.is_felling_blocked())


func test_blueprint_on_forest_waits_for_felling_then_builds() -> void:
	var e := Env.new()
	e.eco.deposit(&"logs", 50)
	e.eco.deposit(&"stone", 50)
	var base_logs := e.eco.total(&"logs")
	var p := e.forest_site(&"cellar")
	assert_true(e.con.validate_placement(&"cellar", p, 0.0)["ok"], "forest does not block a blueprint")
	var trees := e.con.footprint_tree_cells(Vector2(p.x, p.z), BuildingDefs.footprint(&"cellar"), 0.0)
	var id := e.con.place(&"cellar", p, 0.0)
	assert_true(id > 0)
	assert_eq(e.con.felling_count(), trees.size())
	var b := e.con.get_building(id)
	e.run(0.5)
	assert_eq(b.blocked, &"forest")
	assert_false(b.stage_paid)
	assert_eq(e.eco.total(&"stone"), 50, "nothing spent while waiting")
	e.run(60.0)
	assert_true(e.con.footprint_tree_cells(Vector2(p.x, p.z), BuildingDefs.footprint(&"cellar"), 0.0).is_empty())
	assert_true(b.stage > BuildingDefs.Stage.FOUNDATION or b.stage_paid, "foundation started by itself")
	assert_true(e.eco.total(&"logs") > base_logs - 10)
	e.run(100.0)
	assert_true(b.is_done())


func test_cancel_blueprint_removes_felling_jobs() -> void:
	var e := Env.new()
	var p := e.forest_site(&"cellar")
	var id := e.con.place(&"cellar", p, 0.0)
	assert_true(e.con.felling_count() > 0)
	assert_true(e.con.cancel_building(id))
	assert_eq(e.con.felling_count(), 0)
	assert_true(e.con.get_building(id) == null)
	assert_false(e.con.cancel_building(id))


func test_brush_selects_forest_only() -> void:
	var e := Env.new()
	var p := e.forest_site(&"cellar")
	var cells := e.con.fell_cells_in_brush(p, 6.0, true)
	assert_true(cells.size() > 0)
	for c in cells:
		assert_eq(e.world.cell_type(c.x, c.y), WorldMap.Terrain.FOREST)
	assert_true(e.con.fell_cells_in_brush(p, 6.0, false).size() >= cells.size())


func test_save_load_felling_midway() -> void:
	var e := Env.new()
	var p := e.forest_site(&"cellar")
	var cells := e.con.fell_cells_in_brush(p, 6.0, true)
	e.con.start_felling(cells)
	e.run(BuildingDefs.FELL_WORK_PER_LOG * 1.5)
	var d = JSON.parse_string(JSON.stringify(e.sim.to_dict()))
	var e2 := Env.new()
	e2.sim.from_dict(d)
	assert_eq(e2.con.felling_count(), e.con.felling_count())
	for c in cells:
		assert_eq(e2.eco.deposits.remaining(c), e.eco.deposits.remaining(c))
		assert_eq(e2.con.is_felling(c), e.con.is_felling(c))
	e.run(300.0)
	e2.run(300.0)
	assert_eq(e2.con.felling_count(), 0)
	assert_eq(e2.eco.total(&"logs"), e.eco.total(&"logs"))
	for c in cells:
		assert_false(e2.con.has_trees(c))
