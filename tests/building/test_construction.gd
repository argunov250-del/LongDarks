extends "res://tests/test_case.gd"

const SEED := 12345


class Env extends RefCounted:
	var sim := Simulation.new(1)
	var world: WorldMap
	var eco: EconomySystem
	var con: ConstructionSystem

	func _init() -> void:
		world = WorldMap.new(SEED)
		eco = EconomySystem.new(world)
		con = ConstructionSystem.new(world, eco)
		sim.register_system(world)
		sim.register_system(eco)
		sim.register_system(con)
		var s := Storage.new(5000, Vector3.ZERO)
		eco.add_storage(s)

	func stock(res: Dictionary) -> void:
		for k in res:
			eco.deposit(k, res[k])

	func run(seconds: float) -> void:
		var n := int(seconds / 0.1)
		for i in n:
			con.tick(sim, 0.1)

	## Ищет ровный сухой пятачок size x size, подходящий для type; offset — сдвиг поиска.
	func find_site(type: StringName, skip: int = 0) -> Vector3:
		var cs := world.cell_size
		var found := 0
		for cz in range(6, world.size - 6, 3):
			for cx in range(6, world.size - 6, 3):
				var p := world.cell_center(cx, cz)
				if world.cell_type(cx, cz) == WorldMap.Terrain.GROUND and con.validate_placement(type, p, 0.0)["ok"]:
					if found == skip:
						return p
					found += 1
		return Vector3(-1, 0, -1)


func test_footprint_overlap_rotated() -> void:
	var a := Vector2(0, 0)
	var s := Vector2(4, 4)
	assert_true(Footprint.overlaps(a, s, 0.0, Vector2(3.5, 0), s, 0.0))
	assert_false(Footprint.overlaps(a, s, 0.0, Vector2(4.5, 0), s, 0.0))
	# Квадрат 4x4, повёрнутый на 45 градусов, выступает на 2.83 по оси X.
	assert_true(Footprint.overlaps(a, s, 0.0, Vector2(4.5, 0), s, PI / 4.0), "rotated reaches further")
	assert_false(Footprint.overlaps(a, s, 0.0, Vector2(5.0, 0), s, PI / 4.0))
	# Длинная узкая доска, повёрнутая вдоль диагонали.
	assert_true(Footprint.overlaps(Vector2(0, 0), Vector2(10, 0.5), PI / 4.0, Vector2(3, -3), Vector2(1, 1), 0.0))
	assert_false(Footprint.overlaps(Vector2(0, 0), Vector2(10, 0.5), PI / 4.0, Vector2(3, 3), Vector2(1, 1), 0.0))
	assert_true(Footprint.contains(a, Vector2(4, 2), PI / 2.0, Vector2(0.5, 1.8)), "rot 90 swaps axes")


func test_validate_outside_water_slope_overlap() -> void:
	var e := Env.new()
	var ok := e.find_site(&"dugout")
	assert_true(ok.x >= 0.0, "site found")
	assert_true(e.con.validate_placement(&"dugout", ok, 0.0)["ok"])
	assert_eq(e.con.validate_placement(&"dugout", Vector3(-5, 0, 10), 0.0)["reason"], &"outside")
	assert_eq(e.con.validate_placement(&"dugout", Vector3(e.world.get_world_size() - 0.5, 0, 50), 0.0)["reason"], &"outside")
	# вода
	var wp := Vector3(-1, 0, -1)
	for cz in e.world.size:
		for cx in e.world.size:
			if wp.x < 0 and e.world.cell_type(cx, cz) == WorldMap.Terrain.RIVER and cx > 4 and cz > 4 and cx < e.world.size - 4 and cz < e.world.size - 4:
				wp = e.world.cell_center(cx, cz)
	assert_eq(e.con.validate_placement(&"dugout", wp, 0.0)["reason"], &"water")
	# уклон: ищем любую точку, где перепад по основанию превышает лимит, но без воды
	var steep := Vector3(-1, 0, -1)
	for cz in range(4, e.world.size - 4):
		for cx in range(4, e.world.size - 4):
			var p := e.world.cell_center(cx, cz)
			if steep.x < 0 and e.con.validate_placement(&"stone_house", p, 0.0)["reason"] == &"slope":
				steep = p
	assert_true(steep.x >= 0.0, "a steep spot exists")
	# overlap + поворот
	var id := e.con.place(&"dugout", ok, 0.0)
	assert_true(id > 0)
	assert_eq(e.con.validate_placement(&"dugout", ok + Vector3(2, 0, 0), 0.0)["reason"], &"overlap")
	assert_eq(e.con.place(&"dugout", ok + Vector3(2, 0, 0), 0.0), -1)
	var far := ok + Vector3(4.0 + BuildingDefs.BUILD_GAP + 0.1, 0, 0)
	var r0 := e.con.validate_placement(&"dugout", far, 0.0)
	var r45 := e.con.validate_placement(&"dugout", far, PI / 4.0)
	if r0["ok"]:
		assert_eq(r45["reason"], &"overlap", "rotated corner pokes into neighbour")


func test_stage_progress_and_costs() -> void:
	var e := Env.new()
	var site := e.find_site(&"dugout")
	e.stock({&"logs": 100})
	var id := e.con.place(&"dugout", site, 1.0)
	var b := e.con.get_building(id)
	assert_eq(b.stage, BuildingDefs.Stage.FOUNDATION)
	assert_eq(e.eco.total(&"logs"), 100, "nothing paid at placement")
	e.con.tick(e.sim, 0.1)
	assert_eq(e.eco.total(&"logs"), 98, "foundation cost on start")
	e.run(BuildingDefs.stage_work(&"dugout", 0) + 1.0)
	assert_eq(b.stage, BuildingDefs.Stage.WALLS)
	e.run(BuildingDefs.stage_work(&"dugout", 1) + 1.0)
	assert_eq(b.stage, BuildingDefs.Stage.ROOF)
	e.run(BuildingDefs.stage_work(&"dugout", 2) + 1.0)
	assert_true(b.is_done())
	assert_eq(e.eco.total(&"logs"), 100 - 8)


func test_waits_when_unaffordable() -> void:
	var e := Env.new()
	var site := e.find_site(&"dugout")
	e.stock({&"logs": 1})
	var b := e.con.get_building(e.con.place(&"dugout", site, 0.0))
	e.run(30.0)
	assert_eq(b.stage, BuildingDefs.Stage.FOUNDATION)
	assert_eq(b.progress, 0.0)
	assert_false(b.stage_paid)
	assert_eq(b.blocked, &"resources")
	assert_eq(e.eco.total(&"logs"), 1, "atomic: nothing consumed")
	e.stock({&"logs": 20})
	e.run(2.0)
	assert_true(b.stage_paid)
	assert_eq(b.blocked, &"")


func test_frozen_blocks_only_foundation_start() -> void:
	var e := Env.new()
	var site := e.find_site(&"dugout")
	e.stock({&"logs": 100})
	e.con.ground_frozen = true
	var b := e.con.get_building(e.con.place(&"dugout", site, 0.0))
	e.run(20.0)
	assert_eq(b.stage, BuildingDefs.Stage.FOUNDATION)
	assert_false(b.stage_paid)
	assert_eq(b.blocked, &"frozen")
	assert_eq(e.eco.total(&"logs"), 100)
	e.con.ground_frozen = false
	e.run(BuildingDefs.stage_work(&"dugout", 0) + 1.0)
	assert_eq(b.stage, BuildingDefs.Stage.WALLS)
	e.con.ground_frozen = true  # стены и крыша идут даже в мороз
	e.run(BuildingDefs.stage_work(&"dugout", 1) + BuildingDefs.stage_work(&"dugout", 2) + 2.0)
	assert_true(b.is_done())


func test_speed_multiplier() -> void:
	var e := Env.new()
	var site := e.find_site(&"dugout")
	e.stock({&"logs": 100})
	var b := e.con.get_building(e.con.place(&"dugout", site, 0.0))
	e.con.build_speed_multiplier = 0.5
	e.run(10.0)
	assert_almost_eq(b.progress, 5.0, 0.05)
	e.con.build_speed_multiplier = 0.0
	e.run(10.0)
	assert_almost_eq(b.progress, 5.0, 0.05)


func _build_fully(e: Env, id: int) -> void:
	e.run(400.0)
	assert_true(e.con.get_building(id).is_done(), "built")


func test_upgrade_chain_keeps_id_and_position() -> void:
	var e := Env.new()
	var site := e.find_site(&"stone_house")
	e.stock({&"logs": 200, &"planks": 200, &"stone": 200, &"cement": 50, &"scrap_metal": 50})
	var id := e.con.place(&"dugout", site, 0.7)
	assert_false(e.con.can_upgrade(id), "not while under construction")
	_build_fully(e, id)
	var pos := e.con.get_building(id).position
	assert_true(e.con.upgrade(id))
	var b := e.con.get_building(id)
	assert_eq(b.type, &"izba")
	assert_eq(b.stage, BuildingDefs.Stage.FOUNDATION)
	assert_eq(b.position, pos)
	assert_eq(b.id, id)
	assert_false(e.con.can_upgrade(id), "busy")
	_build_fully(e, id)
	assert_true(e.con.upgrade(id))
	assert_eq(e.con.get_building(id).type, &"stone_house")
	_build_fully(e, id)
	assert_false(e.con.upgrade(id), "end of chain")
	assert_eq(e.con.buildings.size(), 1)


func test_warehouse_and_cellar_create_storage() -> void:
	var e := Env.new()
	e.stock({&"logs": 200, &"planks": 200, &"stone": 200})
	var n0 := e.eco.storages.size()
	var wid := e.con.place(&"warehouse", e.find_site(&"warehouse", 0), 0.0)
	var cid := e.con.place(&"cellar", e.find_site(&"cellar", 3), 0.0)
	assert_true(wid > 0 and cid > 0)
	assert_eq(e.eco.storages.size(), n0, "none before completion")
	e.run(400.0)
	assert_eq(e.eco.storages.size(), n0 + 2)
	var ws := e.eco.get_storage(e.con.get_building(wid).storage_id)
	var cs := e.eco.get_storage(e.con.get_building(cid).storage_id)
	assert_eq(ws.capacity, BuildingDefs.WAREHOUSE_CAPACITY)
	assert_false(ws.cellar)
	assert_true(cs.cellar)


func test_dismantle_yields_and_removes_ruin() -> void:
	var e := Env.new()
	var rid: int = e.con.active_ruin_ids()[0]
	var cell: Vector2i = e.con.ruins[rid]["cell"]
	var y := e.con.ruin_yield(rid)
	var scrap0 := e.eco.deposits.remaining(cell)
	assert_eq(y.get(&"scrap_metal", 0), scrap0)
	var before := {}
	for k in y:
		before[k] = e.eco.total(k)
	assert_true(e.con.start_dismantle(rid))
	assert_false(e.con.start_dismantle(rid), "once")
	assert_true(e.con.is_ruin_active(rid), "still there until work done")
	e.run(BuildingDefs.DISMANTLE_WORK * 0.5)
	assert_true(e.con.is_ruin_active(rid))
	assert_almost_eq(e.con.dismantle_fraction(rid), 0.5, 0.02)
	e.run(BuildingDefs.DISMANTLE_WORK * 0.6)
	assert_false(e.con.is_ruin_active(rid))
	for k in y:
		assert_eq(e.eco.total(k), before[k] + y[k], str(k))
	assert_eq(e.eco.deposits.remaining(cell), 0, "no double counting of scrap")
	assert_false(e.con.start_dismantle(rid))
	assert_eq(e.con.restore_ruin(rid, &"dugout"), -1)


func test_restore_ruin_reduced_cost() -> void:
	var e := Env.new()
	e.stock({&"logs": 100})
	var pick := -1
	for rid in e.con.active_ruin_ids():
		if e.con.validate_placement(&"dugout", e.con.ruins[rid]["pos"], e.world.hash01(e.con.ruins[rid]["cell"].x, e.con.ruins[rid]["cell"].y, 77) * TAU)["ok"]:
			pick = rid
			break
	assert_true(pick >= 0, "a restorable ruin exists")
	var bid := e.con.restore_ruin(pick, &"dugout")
	assert_true(bid > 0)
	assert_false(e.con.is_ruin_active(pick))
	assert_eq(e.eco.deposits.remaining(e.con.ruins[pick]["cell"]), 0)
	var b := e.con.get_building(bid)
	assert_true(b.restored)
	assert_eq(b.position.x, e.con.ruins[pick]["pos"].x)
	e.con.tick(e.sim, 0.1)
	assert_eq(e.eco.total(&"logs"), 99, "half cost rounded up: 1 of 2")
	e.run(100.0)
	assert_true(b.is_done())
	assert_eq(e.eco.total(&"logs"), 100 - 4, "total 8 -> 4")
	assert_eq(e.con.restore_ruin(pick, &"dugout"), -1)
	assert_eq(e.con.restore_ruin(e.con.active_ruin_ids()[0], &"izba"), -1, "chain upper tiers not restorable")


func test_save_load_roundtrip() -> void:
	var e := Env.new()
	e.stock({&"logs": 200, &"planks": 200, &"stone": 200})
	var a := e.con.place(&"dugout", e.find_site(&"dugout", 0), 0.4)
	var w := e.con.place(&"warehouse", e.find_site(&"warehouse", 4), 1.2)
	e.run(25.0)
	var rids := e.con.active_ruin_ids()
	e.con.start_dismantle(rids[0])
	e.run(5.0)
	e.con.start_dismantle(rids[1])
	e.run(25.0)  # rids[0] ещё идёт либо готов; rids[1] идёт
	var d := e.sim.to_dict()
	var json := JSON.stringify(d)
	var parsed = JSON.parse_string(json)
	var e2 := Env.new()
	e2.sim.from_dict(parsed)
	assert_eq(e2.con.buildings.size(), e.con.buildings.size())
	for id in e.con.buildings:
		var b1: Building = e.con.buildings[id]
		var b2: Building = e2.con.buildings[id]
		assert_eq(b2.type, b1.type)
		assert_eq(b2.stage, b1.stage)
		assert_eq(b2.stage_paid, b1.stage_paid)
		assert_almost_eq(b2.progress, b1.progress, 0.0001)
		assert_almost_eq(b2.rot, b1.rot, 0.0001)
		assert_almost_eq(b2.position.x, b1.position.x, 0.0001)
		assert_eq(b2.storage_id, b1.storage_id)
	assert_eq(e2.con.active_ruin_ids(), e.con.active_ruin_ids())
	assert_almost_eq(e2.con.dismantle_fraction(rids[1]), e.con.dismantle_fraction(rids[1]), 0.0001)
	var nid := e2.con.place(&"cellar", e2.find_site(&"cellar", 9), 0.0)
	assert_true(nid > a and nid > w, "id counter continues")
	assert_eq(e2.eco.storages.size(), e.eco.storages.size())
