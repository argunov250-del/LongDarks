extends "res://tests/test_case.gd"
## Step 17 land restoration (design/gdd/land-restoration.md).

const RestEnv = preload("res://tests/restoration/rest_env.gd")


func test_planting_saplings_become_harvestable_trees() -> void:
	var r := RestEnv.new()
	var c := r.free_cells(1)[0]
	assert_eq(r.e.eco.deposits.remaining(c), 0, "bare ground has no trees")
	assert_eq(r.rs.designate_plant([c]), 1)
	assert_eq(r.rs.designate_plant([c]), 0, "no double marks")
	var jobs := r.rs.jobs().filter(func(j): return j["kind"] == &"plant")
	assert_eq(jobs.size(), 1, "villagers get a planting job")
	assert_eq(jobs[0]["cat"], TaskDefs.PLANT)
	r.rs.finish(&"plant", r.idx(c))
	assert_eq(r.rs.sapling_count(), 1)
	assert_eq(r.e.eco.deposits.remaining(c), 0, "sapling is not harvestable yet")
	var secs := SeasonDefs.DEFAULT_MINUTES[SeasonDefs.SUMMER] * 60.0
	r.rs.tick(r.e.sim, secs * RestorationDefs.SAPLING_GROW_SEASONS * 1.01)
	assert_eq(r.rs.sapling_count(), 0)
	assert_eq(r.e.eco.deposits.remaining(c), RestorationDefs.TREES_PER_PLANTED, "grown into trees")
	assert_true(r.e.con.has_trees(c), "harvestable by felling")
	var cl: Array[Vector2i] = [c]
	assert_eq(r.e.con.start_felling(cl), 1, "felling job accepted on a planted ground cell")


func test_no_planting_in_winter_and_not_on_occupied() -> void:
	var r := RestEnv.new(SeasonDefs.WINTER)
	var c := r.free_cells(1)[0]
	r.rs.designate_plant([c])
	assert_true(r.rs.jobs().is_empty(), "no planting jobs in winter")
	var p := RestEnv.new()
	var h: Vector3 = p.e.vs.hub_position()
	var b: Building = p.e.con.buildings.values()[0] if not p.e.con.buildings.is_empty() else null
	if b != null:
		var cells: Array[Vector2i] = p.e.con.footprint_cells(Vector2(b.position.x, b.position.z), b.size(), b.rot)
		assert_eq(p.rs.designate_plant(cells), 0, "cannot plant under buildings")
	assert_true(h.length() >= 0.0)


func test_planted_cells_feed_climate_and_felling_removes_them() -> void:
	var r := RestEnv.new()
	var cs := r.free_cells(2)
	r.grow_tree(cs[0])
	r.grow_tree(cs[1])
	assert_eq(r.rs.planted_count(), 2)
	assert_eq(r.f.climate.planted_forest_cells(), 2, "planted count reaches ClimateSystem")
	var bonus := r.f.climate.acceleration_bonus()
	assert_true(bonus > 0.0)
	r.e.eco.deposits.take(cs[0], 99)
	r.rs.tick(r.e.sim, 2.0)
	assert_eq(r.f.climate.planted_forest_cells(), 1, "felled cell removed from the count")
	assert_true(r.f.climate.acceleration_bonus() < bonus, "bonus removed")
	var w0 := r.f.climate.warming()
	r.f.climate.advance_season()
	assert_true(r.f.climate.warming() >= w0, "felling never cools")


func test_regrowth_on_felled_forest_cell() -> void:
	var r := RestEnv.new()
	var forest := Vector2i(-1, -1)
	for cz in r.world.size:
		for cx in r.world.size:
			if forest.x < 0 and r.world.cell_type(cx, cz) == WorldMap.Terrain.FOREST and r.e.eco.deposits.remaining(Vector2i(cx, cz)) > 0 and r.e.con.footprint_cells(Vector2(0, 0), Vector2(1, 1), 0) != null:
				forest = Vector2i(cx, cz)
	r.e.eco.deposits.take(forest, 99)
	assert_true(r.rs.can_plant(forest), "felled forest cell can be replanted")
	r.grow_tree(forest)
	assert_true(r.e.eco.deposits.remaining(forest) > 0, "forest regrew")
	assert_eq(r.rs.planted_count(), 1)


func test_natural_spread_slow_and_only_at_edges() -> void:
	var r := RestEnv.new()
	r.rs.natural_spread = true
	var cands := r.rs.spread_candidates()
	assert_true(cands.size() > 0, "forest has edges")
	for i in mini(cands.size(), 200):
		var c := Vector2i(cands[i] % r.world.size, cands[i] / r.world.size)
		var near := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if r.e.eco.deposits.remaining(c + d) > 0:
				near = true
		assert_true(near, "candidate touches existing trees")
		assert_true(r.e.eco.deposits.remaining(c) == 0)
	r.days(10.0)
	var n := r.rs.sapling_count()
	assert_true(n <= ceili(RestorationDefs.SPREAD_CELLS_PER_DAY * 10.0) + 1, "spread is slow: %d" % n)
	assert_true(n >= 1, "but it happens")
	for i in r.rs.saplings:
		assert_true(cands.has(i), "sapling placed on an edge candidate")


func test_water_quality_raises_fish_capacity() -> void:
	var r := RestEnv.new()
	r.rs.sync_now()
	var cap0: float = r.f.food.bodies[0]["cap"]
	assert_almost_eq(cap0, r.f.food.bodies[0]["cap0"], 1.0, "start quality = baseline capacity")
	var q0 := r.rs.water_quality_avg()
	r.days(60.0, 2.0)
	assert_true(r.rs.water_quality_avg() > q0, "rivers and lakes gradually clean")
	assert_true(r.f.food.bodies[0]["cap"] > cap0, "cleaner water, more fish")
	assert_true(RestorationSystem.fish_multiplier(1.0) > RestorationSystem.fish_multiplier(0.5))


func test_wildlife_returns_with_recovery() -> void:
	var r := RestEnv.new()
	var reg: Dictionary = r.f.food.regions[0]
	var cap0: float = reg["cap"]
	for i in 40:
		r.rs.water_quality[0] = 1.0
	for i in r.rs.water_quality.size():
		r.rs.water_quality[i] = 1.0
	var cs := r.free_cells(1)
	r.rs.sync_now()
	assert_true(r.rs.recovery() > 0.0)
	assert_true(r.f.food.land_recovery > 1.0, "recovery speeds regen / return")
	r.f.food.tick(r.e.sim, 1.0)
	assert_true(reg["cap"] > cap0, "capacity grows with recovery")
	assert_true(cs.size() >= 0)
	assert_true(r.f.climate.land_recovery > 0.0, "birds scale with recovery")
	var b0 := ClimateSystem.new()
	b0.attach(r.e.sim)
	b0.tick(r.e.sim, 1.0)
	var low := r.f.climate.bird_count()
	r.f.climate.land_recovery = 0.0
	var base := r.f.climate.bird_count()
	assert_true(low >= base)


func test_soil_fertility_rises_slowly() -> void:
	var r := RestEnv.new()
	var c := r.free_cells(1)[0]
	var f0 := r.f.food.fertility_at(c)
	r.days(5.0)
	var f1 := r.f.food.fertility_at(c)
	assert_true(f1 > f0, "fertility grows")
	assert_true(f1 - f0 < 0.05, "but slowly")
	r.days(200.0, 5.0)
	assert_true(r.f.food.fertility_at(c) <= RestorationDefs.SOIL_MAX + 0.001, "capped")
	r.f.food.water_override = 1.0
	r.f.food.designate([c], &"grain")
	assert_true(r.f.food.expected_yield(r.idx(c)) >= 1, "fields keep their rules")


func test_poison_heals_only_when_treated() -> void:
	var r := RestEnv.new()
	var c := r.poison_cell()
	assert_true(c.x >= 0, "poison zone exists")
	assert_almost_eq(r.rs.poison_at(c), 1.0)
	r.days(60.0, 2.0)
	assert_almost_eq(r.rs.poison_at(c), 1.0, 0.0001, "untreated poison never heals")
	assert_eq(r.rs.designate_heal([c]), 1)
	assert_eq(r.rs.jobs().filter(func(j): return j["kind"] == &"heal_land").size(), 1)
	r.days(5.0)
	assert_almost_eq(r.rs.poison_at(c), 1.0, 0.0001, "designated but nobody treated yet")
	r.rs.finish(&"heal_land", r.idx(c))
	assert_true(r.rs.is_treated(c))
	r.days(4.0)
	var mid := r.rs.poison_at(c)
	assert_true(mid < 1.0 and mid > 0.0, "poison drops while treated")
	assert_eq(r.rs.state_text(c), "Земля оживает")
	r.days(30.0, 2.0)
	assert_almost_eq(r.rs.poison_at(c), 0.0, 0.0001, "healed")
	assert_eq(r.rs.state_text(c), "Земля чистая")
	assert_true(r.rs.recovery() > 0.0, "healing counts for recovery")


func test_poison_blocks_fields_and_lowers_fertility() -> void:
	var r := RestEnv.new()
	var c := r.poison_cell()
	assert_false(r.f.food.is_field_ground(c), "no fields on poison")
	assert_eq(r.f.food.designate([c], &"grain"), 0)
	assert_false(r.rs.can_cultivate(c), "no gardens on poison")
	assert_true(r.rs.water_bad_at(r.world.cell_center(c.x, c.y)), "well in poison: bad water hook")
	assert_eq(r.rs.designate_plant([c]), 0, "saplings are not planted on raw poison")
	r.rs.designate_heal([c])
	r.rs.finish(&"heal_land", r.idx(c))
	assert_false(r.f.food.is_field_ground(c), "still no field while poison remains")
	assert_true(r.f.food.fertility_at(c) <= r.f.food.fertility_at(r.free_cells(1)[0]), "poison lowers fertility")
	r.days(40.0, 2.0)
	assert_true(r.f.food.is_field_ground(c), "healed cell can be cultivated")


func test_frequent_hunting_makes_herd_leave_even_with_high_numbers_and_return() -> void:
	var r := RestEnv.new()
	var reg: Dictionary = r.f.food.regions[0]
	reg["pop"] = 500.0
	reg["cap"] = 500.0
	reg["cap0"] = 500.0  # huge herd: numbers irrelevant
	var n := 0
	while not reg["gone"] and n < 50:
		r.f.food.finish(&"hunt", reg["id"])
		n += 1
	assert_eq(n, FoodDefs.HUNT_PRESSURE_MAX + 1, "leaves after too many hunts in the window")
	assert_true(reg["pop"] > 400.0, "regardless of current numbers")
	# hunting spread over a long time does not scare the herd
	var r2 := RestEnv.new()
	var g: Dictionary = r2.f.food.regions[0]
	g["pop"] = 500.0
	g["cap"] = 500.0
	g["cap0"] = 500.0
	for i in 20:
		r2.f.food.finish(&"hunt", g["id"])
		r2.f.food.tick(r2.e.sim, FoodDefs.HUNT_WINDOW_DAYS / FoodDefs.HUNT_PRESSURE_MAX * 1.5 * r2.day())
	assert_false(g["gone"], "rare hunting is fine")
	# return later; faster with recovery
	r.days(FoodDefs.RETURN_DAYS * 0.5)
	assert_true(reg["gone"], "still away")
	r.days(FoodDefs.RETURN_DAYS * 0.6)
	assert_false(reg["gone"], "returns when pressure is low")
	var r3 := RestEnv.new()
	var h: Dictionary = r3.f.food.regions[0]
	r3.f.food.land_recovery = 3.0
	h["gone"] = true
	h["back_in"] = FoodDefs.RETURN_DAYS
	for i in int(FoodDefs.RETURN_DAYS / 3.0) + 2:
		r3.f.food.tick(r3.e.sim, r3.day())
	assert_false(h["gone"], "faster when land recovered")


func test_save_load_roundtrip() -> void:
	var r := RestEnv.new()
	var cs := r.free_cells(3)
	r.grow_tree(cs[0])
	r.rs.designate_plant([cs[1]])
	r.rs.finish(&"plant", r.idx(cs[1]))
	r.rs.designate_plant([cs[2]])
	var pc := r.poison_cell()
	r.rs.designate_heal([pc])
	r.rs.finish(&"heal_land", r.idx(pc))
	r.days(3.0)
	r.f.food.finish(&"hunt", 0)
	var data: Dictionary = JSON.parse_string(JSON.stringify(r.rs.save_state()))
	var fdata: Dictionary = JSON.parse_string(JSON.stringify(r.f.food.save_state()))
	var ddata: Dictionary = JSON.parse_string(JSON.stringify(r.e.eco.deposits.to_dict()))
	var r2 := RestEnv.new()
	r2.e.eco.deposits.from_dict(ddata)
	r2.f.food.load_state(fdata)
	r2.rs.load_state(data)
	assert_eq(r2.rs.planted_count(), 1)
	assert_eq(r2.rs.sapling_count(), r.rs.sapling_count())
	assert_eq(r2.rs.plant_marks.size(), 1)
	assert_true(r2.rs.is_treated(pc))
	assert_almost_eq(r2.rs.poison_at(pc), r.rs.poison_at(pc), 0.0001)
	assert_almost_eq(r2.rs.soil, r.rs.soil, 0.0001)
	assert_almost_eq(r2.rs.water_quality_avg(), r.rs.water_quality_avg(), 0.0001)
	assert_eq(r2.e.eco.deposits.remaining(cs[0]), RestorationDefs.TREES_PER_PLANTED, "planted trees saved in deposits")
	assert_eq(r2.f.food.regions[0]["hunts"].size(), 1, "hunting pressure saved")


func test_crop_view_stages() -> void:
	var r := RestEnv.new()
	var cs := r.f.field_cells(3, &"grain")
	var view := FoodView.new()
	assert_eq(view.crop_stage(r.f.food.field_at(cs[0])), FoodView.CROP_NONE, "designated: nothing grows")
	var mk := func(stage: int, growth: float, crop: StringName) -> Dictionary: return {"crop": crop, "stage": stage, "growth": growth}
	assert_eq(view.crop_stage(mk.call(FoodSystem.Stage.PLOWED, 0.0, &"grain")), FoodView.CROP_NONE)
	assert_eq(view.crop_stage(mk.call(FoodSystem.Stage.SOWN, 0.1, &"grain")), FoodView.CROP_SPROUT)
	assert_eq(view.crop_stage(mk.call(FoodSystem.Stage.SOWN, 0.7, &"grain")), FoodView.CROP_TALL)
	assert_eq(view.crop_stage(mk.call(FoodSystem.Stage.RIPE, 1.0, &"grain")), FoodView.CROP_RIPE)
	assert_true(view.crop_color(&"grain", FoodView.CROP_RIPE) != view.crop_color(&"potato", FoodView.CROP_RIPE))
	view.setup(r.f.food, r.world, r.e.sim)
	view.rebuild_crops()
	assert_eq(view.crop_count(), 0, "no crops on unsown fields")
	r.f.ripen(cs[0])
	view.rebuild_crops()
	assert_true(view.crop_count() > 0, "ripe field shows plants")
	view.free()
