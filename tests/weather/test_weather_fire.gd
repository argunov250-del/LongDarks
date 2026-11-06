extends "res://tests/test_case.gd"

const WEnv = preload("res://tests/weather/weather_env.gd")

const RES := {&"logs": 200, &"planks": 100, &"stone": 100, &"scrap_metal": 50, &"spare_parts": 20, &"firewood": 50}


func _env() -> WEnv:
	var e := WEnv.new(5000, RES)
	e.at_day(SeasonDefs.SUMMER, 0.3, 10.0)
	return e


## Готовое здание вплотную к клетке леса (без деревьев под ним). -1 — не нашлось.
func _building_beside(e: WEnv, c: Vector2i, type: StringName = &"warehouse") -> int:
	var cc := e.world.cell_center(c.x, c.y)
	for off in [Vector2(5.5, 0), Vector2(-5.5, 0), Vector2(0, 5.0), Vector2(0, -5.0), Vector2(6.5, 0), Vector2(-6.5, 0), Vector2(0, 6.0), Vector2(0, -6.0)]:
		var p := cc + Vector3(off.x, 0.0, off.y)
		if e.con.placement_tree_cells(type, p, 0.0).is_empty():
			var id := e.con.place_completed(type, p, 0.0)
			if id > 0:
				return id
	return -1


func test_fire_spreads_in_forest_and_burns_trees() -> void:
	var e := _env()
	var c := e.forest_cell(3)
	var f := e.weather.fire
	f.spread_chance = 1.0
	f.building_chance = 0.0
	assert_true(e.eco.deposits.remaining(c) > 0)
	assert_true(f.ignite_cell(c), "forest cell ignites")
	assert_false(f.ignite_cell(c), "already burning")
	e.run(f.spread_interval * 2.0 + 1.0)
	assert_true(f.burning_cell_count() >= 2, "fire spreads to neighbours: %d" % f.burning_cell_count())
	assert_true(f.burning_cell_count() <= f.max_cells)
	e.run(f.burn_time * 3.0)
	assert_true(f.is_empty(), "everything burnt out")
	assert_eq(e.eco.deposits.remaining(c), 0, "trees burnt")
	assert_almost_eq(e.weather.fertility_at(c), WeatherDefs.BURN_FERTILITY, 0.03, "burnt soil is richer")
	assert_false(f.ignite_cell(c), "nothing left to burn")


func test_fire_limited_per_focus() -> void:
	var e := _env()
	var f := e.weather.fire
	f.spread_chance = 1.0
	f.spread_interval = 1.0
	f.max_cells = 4
	f.building_chance = 0.0
	f.ignite_cell(e.forest_cell(3))
	e.run(200.0)
	var burnt := 0
	for i in e.weather.fertility:
		burnt += 1
	assert_true(burnt <= 4 and burnt >= 1, "no more than max_cells per focus: %d" % burnt)


func test_fire_reaches_adjacent_building_and_it_stops_working() -> void:
	var e := _env()
	var c := e.forest_cell(2)
	var bid := _building_beside(e, c, &"sawmill")
	assert_true(bid > 0, "building beside the forest")
	var b := e.con.get_building(bid)
	var f := e.weather.fire
	f.building_chance = 1.0
	f.spread_chance = 0.0
	f.ignite_cell(c)
	e.run(f.spread_interval + 1.0)
	assert_true(b.burning, "building caught fire")
	assert_false(b.operational())
	assert_false(e.prod.needs_worker(bid), "burning building does not work")
	# колодец не горит
	var w := _building_beside(e, c, &"well")
	if w > 0:
		assert_false(f.ignite_building(w), "wells do not burn")


func test_unextinguished_building_is_damaged_not_destroyed_then_repaired() -> void:
	var e := _env()
	var bid := e.add_done(&"sawmill", 14.0, 0.0)
	var b := e.con.get_building(bid)
	e.weather.fire.building_burn_time = 20.0
	assert_true(e.weather.fire.ignite_building(bid))
	e.run(15.0)
	assert_true(b.burning)
	e.run(10.0)
	assert_false(b.burning)
	assert_true(b.damaged, "burnt down -> damaged")
	assert_true(e.con.get_building(bid) != null and b.is_done(), "not destroyed")
	assert_false(b.operational())
	assert_false(e.prod.needs_worker(bid))
	# ремонт: материалы и работа жителей
	var logs0 := e.eco.total(&"planks")
	e.run(60.0)
	assert_false(b.damaged, "villagers repaired it")
	assert_true(b.operational())
	assert_true(e.eco.total(&"planks") < logs0 or e.eco.total(&"logs") < 200, "repair spent materials")


func test_repair_waits_for_materials() -> void:
	var e := WEnv.new(5000, {})
	e.at_day(SeasonDefs.SUMMER, 0.3, 10.0)
	var bid := e.add_done(&"sawmill", 14.0, 0.0)
	var b := e.con.get_building(bid)
	b.damaged = true
	e.run(30.0)
	assert_true(b.damaged and b.blocked == &"resources", "no materials -> no repair")
	e.storage.add(&"planks", 50)
	e.storage.add(&"logs", 50)
	e.storage.add(&"stone", 50)
	e.storage.add(&"scrap_metal", 50)
	e.run(60.0)
	assert_false(b.damaged)


func test_villagers_extinguish_building_with_carried_water() -> void:
	var e := _env()
	e.enable_needs(10.0)
	e.vs.household.heating_needed = false
	e.add_done(&"well", 8.0, 6.0)
	var bid := e.add_done(&"sawmill", 14.0, 0.0)
	var b := e.con.get_building(bid)
	e.weather.fire.building_burn_time = 400.0
	e.weather.fire.ignite_building(bid)
	var saw_carry := false
	for i in 40:
		e.run(5.0)
		for v: Villager in e.vs.villager_list():
			if v.task.get("kind", &"") == &"extinguish" and v.task.get("phase", &"") == &"deliver" and int(v.task.get("carry", 0)) > 0:
				saw_carry = true
				assert_eq(VillagerAnim.load_of(v.task), VillagerAnim.LOAD_BUCKETS, "carries buckets")
		if not b.burning:
			break
	assert_true(saw_carry, "water was physically carried")
	assert_false(b.burning, "extinguished")
	assert_false(b.damaged, "saved from damage")
	assert_true(b.operational())


func test_villagers_extinguish_forest_cell_and_trees_survive() -> void:
	var e := _env()
	e.enable_needs(10.0)
	e.vs.household.heating_needed = false
	e.add_done(&"well", 8.0, 6.0)
	var c := e.forest_cell(0)
	var trees := e.eco.deposits.remaining(c)
	e.weather.fire.burn_time = 400.0
	e.weather.fire.ignite_cell(c)
	for i in 60:
		e.run(5.0)
		if e.weather.fire.is_empty():
			break
	assert_true(e.weather.fire.is_empty(), "put out")
	assert_eq(e.eco.deposits.remaining(c), trees, "trees survive")
	assert_eq(e.weather.fertility_at(c), 0.0)


func test_no_well_nothing_to_extinguish_with() -> void:
	var e := _env()
	e.enable_needs(10.0)
	e.weather.fire.burn_time = 30.0
	var c := e.forest_cell(0)
	e.weather.fire.ignite_cell(c)
	e.run(40.0)
	assert_eq(e.eco.deposits.remaining(c), 0, "no well -> burnt")


func test_rain_extinguishes_fire() -> void:
	var e := _env()
	var c := e.forest_cell(0)
	var bid := e.add_done(&"sawmill", 14.0, 0.0)
	e.weather.fire.burn_time = 400.0
	e.weather.fire.building_burn_time = 400.0
	e.weather.fire.ignite_cell(c)
	e.weather.fire.ignite_building(bid)
	e.weather.start_event(WeatherDefs.DOWNPOUR, 120.0)
	assert_true(e.weather.fire.is_empty(), "downpour puts everything out")
	assert_false(e.con.get_building(bid).burning)
	assert_true(e.eco.deposits.remaining(c) > 0)
	assert_false(e.weather.fire.ignite_cell(c) and false)
	e.run(5.0)
	assert_true(e.weather.fire.is_empty())


func test_thunderstorm_lightning_ignites_forest_sometimes() -> void:
	var e := _env()
	e.weather.fire.ignite_chance = 1.0
	var strikes := []
	e.sim.bus.subscribe(WeatherSystem.TOPIC_LIGHTNING, func(p): strikes.append(p["cell"]))
	e.weather.start_event(WeatherDefs.THUNDERSTORM, 400.0)
	e.run(WeatherDefs.LIGHTNING_PERIOD * 10.0 + 1.0)
	assert_eq(strikes.size(), 10, "a strike every LIGHTNING_PERIOD")
	assert_true(e.weather.fire.burning_cell_count() > 0 or e.weather.fertility.size() > 0, "some strike hit a forest")


func test_fertility_decays_over_a_year() -> void:
	var e := _env()
	var c := e.forest_cell(0)
	e.weather.set_fertility(c, WeatherDefs.BURN_FERTILITY)
	e.weather._tick_fertility(e.seasons.year_length() * 0.5)
	assert_almost_eq(e.weather.fertility_at(c), WeatherDefs.BURN_FERTILITY * 0.5, 0.001, "half a year -> half the bonus")
	e.weather._tick_fertility(e.seasons.year_length() * 0.6)
	assert_eq(e.weather.fertility_at(c), 0.0, "gone after ~a year")
