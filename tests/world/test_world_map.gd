extends "res://tests/test_case.gd"

const SEED := 12345


func _sig(m: WorldMap) -> Array:
	return [hash(m.heights), hash(m.terrain), m.factory_cell]


func test_same_seed_identical() -> void:
	assert_eq(_sig(WorldMap.new(SEED)), _sig(WorldMap.new(SEED)))


func test_different_seed_differs() -> void:
	var a := WorldMap.new(SEED)
	var b := WorldMap.new(SEED + 1)
	assert_true(hash(a.heights) != hash(b.heights))
	assert_true(hash(a.terrain) != hash(b.terrain))


func test_has_all_terrain_types() -> void:
	for s in [1, SEED, 987654]:
		var m := WorldMap.new(s)
		for t in [WorldMap.Terrain.GROUND, WorldMap.Terrain.RIVER, WorldMap.Terrain.LAKE,
				WorldMap.Terrain.FOREST, WorldMap.Terrain.RUINS, WorldMap.Terrain.POISON]:
			assert_true(m.count_type(t) > 0, "seed %d missing terrain %d" % [s, t])


func test_poison_surrounds_factory() -> void:
	var m := WorldMap.new(SEED)
	var f := m.factory_cell
	assert_eq(m.cell_type(f.x, f.y), WorldMap.Terrain.RUINS)
	var c := m.cell_center(f.x, f.y)
	assert_false(m.is_water(c.x, c.z))
	var poison_near := 0
	for dz in range(-6, 7):
		for dx in range(-6, 7):
			if m.cell_type(f.x + dx, f.y + dz) == WorldMap.Terrain.POISON:
				poison_near += 1
	assert_true(poison_near > 40, "poison near factory: %d" % poison_near)


func test_height_continuity() -> void:
	var m := WorldMap.new(SEED)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for _i in 200:
		var x := rng.randf_range(0.0, m.get_world_size())
		var z := rng.randf_range(0.0, m.get_world_size())
		var d := 0.01
		assert_true(absf(m.height_at(x, z) - m.height_at(x + d, z + d)) < 0.2, "discontinuity at %f,%f" % [x, z])
	assert_almost_eq(m.height_at(10 * m.cell_size, 7 * m.cell_size), m.node_height(10, 7), 0.0001)
	assert_almost_eq(m.height_at(-50.0, -50.0), m.node_height(0, 0), 0.0001)


func test_bounds_and_water_query() -> void:
	var m := WorldMap.new(SEED)
	assert_eq(m.get_bounds().size, Vector2(m.get_world_size(), m.get_world_size()))
	for cz in m.size:
		for cx in m.size:
			if m.cell_type(cx, cz) == WorldMap.Terrain.LAKE:
				var c := m.cell_center(cx, cz)
				assert_true(m.is_water(c.x, c.z))
				return
	assert_true(false, "no lake")


func test_save_regenerates_identical() -> void:
	var sim := Simulation.new(1)
	var m := WorldMap.new(SEED, 64, {"amplitude": 7.0})
	sim.register_system(m)
	var sig := _sig(m)
	assert_eq(SaveManager.save(sim, "__test_world"), OK)
	var sim2 := Simulation.new(2)
	var m2 := WorldMap.new(999, 32)
	sim2.register_system(m2)
	assert_eq(SaveManager.load_slot(sim2, "__test_world"), OK)
	assert_eq(_sig(m2), sig)
	assert_eq(m2.size, 64)
	assert_almost_eq(m2.params["amplitude"], 7.0)
	SaveManager.delete_slot("__test_world")


func test_save_is_small() -> void:
	var s := WorldMap.new(SEED).save_state()
	assert_true(JSON.stringify(s).length() < 200)
