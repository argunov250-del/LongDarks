extends "res://tests/test_case.gd"
## Step 16 food (design/gdd/food.md): fields, greenhouse, hunting, fishing, mushrooms, tasks, save.

const FoodEnv = preload("res://tests/food/food_env.gd")


func test_field_season_gating() -> void:
	var r := FoodEnv.new(SeasonDefs.SPRING)
	var cells := r.field_cells(3)
	assert_true(cells.size() == 3, "brush found ground cells")
	var i := r.idx(cells[0])
	assert_eq(r.food.field_action(i), &"plow", "spring: plow")
	r.food.finish(&"field", i)
	assert_eq(r.food.field_action(i), &"sow", "spring: sow after plow")
	r.food.season_override = SeasonDefs.SUMMER
	assert_eq(r.food.field_action(i), &"", "summer: no field work")
	r.food.season_override = SeasonDefs.AUTUMN
	assert_eq(r.food.field_action(i), &"", "autumn: nothing to harvest yet")
	r.food.season_override = SeasonDefs.WINTER
	assert_eq(r.food.field_action(r.idx(cells[1])), &"", "winter: nothing")
	assert_true(r.food.jobs().filter(func(j): return j["kind"] == &"field").is_empty(), "winter: no field jobs")


func test_crop_grows_in_summer_ripe_in_autumn() -> void:
	var r := FoodEnv.new()
	var c := r.field_cells(1)[0]
	r.ripen(c)
	var f := r.food.field_at(c)
	assert_eq(f["stage"], FoodSystem.Stage.RIPE, "ripe after summer")
	assert_eq(r.food.field_action(r.idx(c)), &"harvest", "harvest in autumn")
	var out := r.food.finish(&"field", r.idx(c))
	assert_eq(out["res"], &"grain")
	assert_true(out["n"] >= 1)
	r.food.season_override = SeasonDefs.WINTER
	r.food.tick(r.e.sim, 1.0)
	assert_eq(r.food.field_at(c)["stage"], FoodSystem.Stage.DESIGNATED, "winter resets fields")


func test_forest_must_be_cleared_for_fields() -> void:
	var r := FoodEnv.new()
	var w := r.e.world
	for cz in w.size:
		for cx in w.size:
			if w.cell_type(cx, cz) == WorldMap.Terrain.FOREST and r.e.eco.deposits.remaining(Vector2i(cx, cz)) > 0:
				assert_false(r.food.is_field_ground(Vector2i(cx, cz)), "uncleared forest is not field ground")
				assert_eq(r.food.designate([Vector2i(cx, cz)], &"grain"), 0)
				return
	assert_true(false, "no forest cell found")


func test_fertility_and_water_affect_yield() -> void:
	var r := FoodEnv.new()
	var cs := r.field_cells(2)
	r.food.water_override = 1.0
	r.ripen(cs[0])
	r.ripen(cs[1])
	var base := r.food.expected_yield(r.idx(cs[0]))
	r.weather.set_fertility(cs[1], WeatherDefs.BURN_FERTILITY)
	assert_true(r.food.expected_yield(r.idx(cs[1])) > base, "burnt cell yields more")
	# rain vs drought across the growth period
	var wet := FoodEnv.new()
	var dry := FoodEnv.new()
	wet.food.water_override = FoodDefs.RAIN_WATER
	dry.food.water_override = FoodDefs.DROUGHT_WATER
	var cw := wet.field_cells(1, &"potato")[0]
	var cd := dry.field_cells(1, &"potato")[0]
	wet.ripen(cw)
	dry.ripen(cd)
	assert_true(wet.food.expected_yield(wet.idx(cw)) > dry.food.expected_yield(dry.idx(cd)), "rain beats drought")
	assert_true(dry.food.expected_yield(dry.idx(cd)) >= 1, "drought hurts but does not zero")


func test_plowed_count_reaches_climate() -> void:
	var r := FoodEnv.new()
	var cs := r.field_cells(4)
	assert_eq(r.food.plowed_count(), 0, "designated is not plowed")
	r.food.finish(&"field", r.idx(cs[0]))
	r.food.finish(&"field", r.idx(cs[1]))
	r.food.tick(r.e.sim, 1.1)
	assert_eq(r.food.plowed_count(), 2)
	assert_eq(r.climate.plowed_cells(), 2, "climate receives plowed count")


func test_greenhouse_winter_needs_fuel() -> void:
	var r := FoodEnv.new(SeasonDefs.WINTER)
	var id := r.e.add_done(&"greenhouse")
	assert_true(id > 0)
	r.food.tick(r.e.sim, 0.1)
	var day := r.e.sim.clock.day_seconds()
	for i in 12:
		r.food.tick(r.e.sim, day)
	assert_eq(r.food._gh(id)["ripe"], 0, "no fuel: nothing grows in winter")
	r.food.add_fuel(id, 12)
	for i in 6:
		r.food.tick(r.e.sim, day)
	assert_true(r.food._gh(id)["ripe"] > 0, "fuel: vegetables in winter")
	var out := r.food.finish(&"gpick", id)
	assert_eq(out["res"], &"vegetables")
	assert_true(r.food._gh(id)["fuel"] < 12.0, "fuel burnt")
	r.food.season_override = SeasonDefs.SUMMER
	var before: float = r.food._gh(id)["fuel"]
	for i in 6:
		r.food.tick(r.e.sim, day)
	assert_almost_eq(r.food._gh(id)["fuel"], before, 0.0001, "no fuel burnt outside winter")


func test_hunting_overhunt_herd_leaves_then_returns() -> void:
	var r := FoodEnv.new()
	assert_true(r.food.regions.size() > 0, "wildlife regions exist")
	var reg: Dictionary = r.food.regions[0]
	var meat := 0
	var out := r.food.finish(&"hunt", reg["id"])
	meat += out["n"]
	assert_eq(out["res"], &"meat")
	assert_true(meat > 0)
	var guard := 0
	while not reg["gone"] and guard < 100:
		r.food.finish(&"hunt", reg["id"])
		guard += 1
	assert_true(reg["gone"], "overhunting: herd leaves")
	assert_eq(r.food.hunt_hint() == "зверь ушёл" or r.food.regions.size() > 1, true)
	assert_true(r.food.finish(&"hunt", reg["id"]).is_empty(), "nothing to hunt while gone")
	var day := r.e.sim.clock.day_seconds()
	for i in int(FoodDefs.RETURN_DAYS * 0.5):
		r.food.tick(r.e.sim, day)
	assert_true(reg["gone"], "still away halfway")
	for i in int(FoodDefs.RETURN_DAYS * 0.5) + 2:
		r.food.tick(r.e.sim, day)
	assert_false(reg["gone"], "herd returned")
	assert_true(reg["pop"] < reg["cap"], "returns small, regrows slowly")
	# step 17 hook: recovery speeds the return
	var r2 := FoodEnv.new()
	var reg2: Dictionary = r2.food.regions[0]
	r2.food.land_recovery = 3.0
	reg2["gone"] = true
	reg2["back_in"] = FoodDefs.RETURN_DAYS
	for i in int(FoodDefs.RETURN_DAYS / 3.0) + 2:
		r2.food.tick(r2.e.sim, day)
	assert_false(reg2["gone"], "land recovery brings animals back sooner")


func test_wildlife_regenerates_slowly() -> void:
	var r := FoodEnv.new()
	var reg: Dictionary = r.food.regions[0]
	reg["pop"] = reg["cap"] * 0.5
	var p0: float = reg["pop"]
	r.food.tick(r.e.sim, r.e.sim.clock.day_seconds())
	assert_true(reg["pop"] > p0, "regrows")
	assert_true(reg["pop"] - p0 < 0.5, "slowly")


func test_fishing_depletes_and_regenerates() -> void:
	var r := FoodEnv.new()
	assert_true(r.food.bodies.size() > 0, "water bodies found")
	var b: Dictionary = r.food.bodies[0]
	var got := 0
	for i in 5000:
		var out := r.food.finish(&"fish", 0)
		if out.is_empty():
			break
		got += out["n"]
	assert_true(got > 0 and b["stock"] < 1.0, "overfished")
	assert_true(r.food.finish(&"fish", 0).is_empty())
	assert_eq(r.food.fish_hint() == "рыбы нет" or r.food.bodies.size() > 1, true)
	var day := r.e.sim.clock.day_seconds()
	for i in 30:
		r.food.tick(r.e.sim, day)
	assert_true(b["stock"] > 1.0, "stock regenerates")


func test_mushrooms_seasonal_in_forest() -> void:
	var r := FoodEnv.new(SeasonDefs.SPRING)
	assert_true(r.food.jobs().filter(func(j): return j["kind"] == &"forage").is_empty(), "spring: none")
	r.food.season_override = SeasonDefs.SUMMER
	r.food.progress_override = 0.2
	assert_true(r.food.jobs().filter(func(j): return j["kind"] == &"forage").is_empty(), "early summer: none")
	r.food.progress_override = 0.9
	var late := r.food.jobs().filter(func(j): return j["kind"] == &"forage")
	r.food.season_override = SeasonDefs.AUTUMN
	var jobs := r.food.jobs().filter(func(j): return j["kind"] == &"forage")
	assert_true(jobs.size() > 0, "autumn: mushrooms to gather")
	assert_true(late.size() <= jobs.size())
	var t: int = jobs[0]["target"]
	assert_eq(r.e.world.cell_type(t % r.e.world.size, t / r.e.world.size), WorldMap.Terrain.FOREST, "in forest")
	var out := r.food.finish(&"forage", t)
	assert_eq(out["res"], &"mushrooms")
	assert_true(r.food.finish(&"forage", t).is_empty(), "picked cell is empty")
	assert_true(ResourceDefs.category(&"mushrooms") == ResourceDefs.Category.FOOD)


func test_task_priorities_respected() -> void:
	var r := FoodEnv.new()
	r.field_cells(3)
	var farmer := r.e.add_villager(&"farmer")
	farmer.pos = r.e.world.cell_center(r.field_cells(1)[0].x, r.field_cells(1)[0].y)
	for c in TaskDefs.CATEGORIES:
		r.e.vs.set_priority(c, 0)
	r.e.vs.assign_now(farmer)
	assert_true(farmer.task.is_empty(), "priority 0: no field work")
	r.e.vs.set_priority(TaskDefs.FIELD, 2)
	r.e.vs.assign_now(farmer)
	assert_eq(farmer.task.get("kind", &""), &"field")
	assert_true(TaskDefs.CATEGORIES.has(TaskDefs.HUNT) and TaskDefs.CATEGORIES.has(TaskDefs.FISH) and TaskDefs.CATEGORIES.has(TaskDefs.FORAGE) and TaskDefs.CATEGORIES.has(TaskDefs.GREENHOUSE))
	var hunter := r.e.add_villager(&"hunter")
	var other := r.e.add_villager(&"cook")
	assert_true(r.e.vs.suitability(hunter, TaskDefs.HUNT) > r.e.vs.suitability(other, TaskDefs.HUNT), "hunter preferred")
	assert_true(r.e.vs.suitability(farmer, TaskDefs.FIELD) > r.e.vs.suitability(other, TaskDefs.FIELD), "farmer preferred")


func test_farmer_plows_and_harvest_goes_to_storage() -> void:
	var r := FoodEnv.new()
	var cs := r.field_cells(2)
	var farmer := r.e.add_villager(&"farmer")
	for c in [TaskDefs.BUILD, TaskDefs.FELL, TaskDefs.DISMANTLE, TaskDefs.PRODUCTION, TaskDefs.CHORES]:
		r.e.vs.set_priority(c, 0)
	r.e.run(240.0)
	assert_true(r.food.plowed_count() == 2 or r.food.field_at(cs[0])["stage"] >= FoodSystem.Stage.SOWN, "farmer plowed and sowed")
	r.food.season_override = SeasonDefs.SUMMER
	r.e.run(1.0)
	r.ripen(cs[0])
	r.ripen(cs[1])
	var before := r.e.eco.total(&"grain")
	r.e.run(240.0)
	assert_true(r.e.eco.total(&"grain") > before, "harvest delivered to storage")


func test_hunter_brings_meat() -> void:
	var r := FoodEnv.new()
	var h := r.e.add_villager(&"hunter")
	for c in [TaskDefs.BUILD, TaskDefs.FELL, TaskDefs.DISMANTLE, TaskDefs.PRODUCTION, TaskDefs.CHORES]:
		r.e.vs.set_priority(c, 0)
	r.e.vs.set_priority(TaskDefs.HUNT, 3)
	var before := r.e.eco.total(&"meat")
	r.e.run(900.0)
	assert_true(r.e.eco.total(&"meat") > before, "hunter delivered meat")
	assert_true(r.e.vs.task_text(h) != "")


func test_save_load_mid_season() -> void:
	var r := FoodEnv.new()
	var cs := r.field_cells(3, &"potato")
	r.food.finish(&"field", r.idx(cs[0]))
	r.food.finish(&"field", r.idx(cs[0]))
	r.food.season_override = SeasonDefs.SUMMER
	r.food.tick(r.e.sim, 100.0)
	r.food.finish(&"hunt", 0)
	r.food.finish(&"fish", 0)
	r.food.finish(&"forage", 1)
	var id := r.e.add_done(&"greenhouse")
	r.food.add_fuel(id, 5)
	var data: Dictionary = JSON.parse_string(JSON.stringify(r.food.save_state()))
	var r2 := FoodEnv.new()
	r2.food.load_state(data)
	assert_eq(r2.food.fields.size(), 3)
	var f := r2.food.field_at(cs[0])
	assert_eq(f["stage"], FoodSystem.Stage.SOWN)
	assert_eq(f["crop"], &"potato")
	assert_almost_eq(f["growth"], r.food.field_at(cs[0])["growth"], 0.0001)
	assert_almost_eq(r2.food.regions[0]["pop"], r.food.regions[0]["pop"], 0.0001)
	assert_almost_eq(r2.food.bodies[0]["stock"], r.food.bodies[0]["stock"], 0.0001)
	assert_almost_eq(r2.food._gh(id)["fuel"], 5.0, 0.0001)


func test_full_storage_keeps_cargo_until_room() -> void:
	var r := FoodEnv.new()
	var f := r.e.add_villager(&"farmer")
	var free := r.e.storage.free_space()
	r.e.storage.add(&"stone", free)  # storage full
	assert_eq(r.e.eco.total_free_space(), 0)
	f.task = {"kind": &"hunt", "cat": TaskDefs.HUNT, "key": "hn:0", "target": 0, "phase": &"deliver", "work": 5.0, "carry": 8, "src": 0, "res": &"meat", "dest": &""}
	f.pos = r.e.storage.position
	r.e.vs._work_food(f, f.task, 1.0)
	assert_eq(f.task.get("carry", 0), 8, "cargo kept while storages are full")
	assert_eq(r.e.eco.total(&"meat"), 0)
	r.e.storage.remove(&"stone", 8)
	r.e.vs._work_food(f, f.task, 1.0)
	assert_eq(r.e.eco.total(&"meat"), 8, "delivered once there is room")
	assert_true(f.task.is_empty())
	# nothing new offered while full
	r.e.storage.add(&"stone", r.e.storage.free_space())
	r.field_cells(2)
	r.food.season_override = SeasonDefs.SPRING
	assert_true(r.food.jobs().size() > 0)
	r.e.vs._jobs_dirty = true
	r.e.vs._ensure_jobs()
	assert_true(r.e.vs._jobs.filter(func(j): return j["kind"] == &"field").is_empty(), "no food jobs while storages full")
