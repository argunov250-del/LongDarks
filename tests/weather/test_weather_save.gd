extends "res://tests/test_case.gd"

const WEnv = preload("res://tests/weather/weather_env.gd")

const RES := {&"logs": 200, &"planks": 100, &"stone": 100, &"scrap_metal": 50}


func _roundtrip(src: WEnv) -> WEnv:
	var text := JSON.stringify(src.sim.to_dict())
	var json := JSON.new()
	assert_eq(json.parse(text), OK)
	var dst := WEnv.new(5000, RES)
	dst.sim.from_dict(json.data)
	return dst


func test_save_load_mid_event() -> void:
	var e := WEnv.new(5000, RES)
	e.at_day(SeasonDefs.WINTER, 0.5, 10.0)
	e.weather.queue_event(WeatherDefs.BLIZZARD, 0.0, 300.0)
	e.run(100.0)
	e.weather.fertility[5] = 0.3
	var left := e.weather.elapsed()
	var d := _roundtrip(e)
	assert_eq(d.weather.current_id(), WeatherDefs.BLIZZARD)
	assert_almost_eq(d.weather.elapsed(), left, 0.01)
	assert_eq(d.con.build_speed_multiplier, 0.0, "hooks restored")
	assert_true(d.vs.household.shelter_required)
	assert_almost_eq(float(d.weather.fertility.get(5, 0.0)), 0.3, 0.001)
	# доигрывается до конца
	d.run(300.0 - left + 5.0)
	assert_eq(d.weather.current_id(), &"")


func test_save_load_queued_event_keeps_lead() -> void:
	var e := WEnv.new(5000, RES)
	e.at_day(SeasonDefs.SUMMER, 0.3, 10.0)
	e.weather.queue_event(WeatherDefs.HURRICANE, 200.0, 100.0)
	e.run(50.0)
	var d := _roundtrip(e)
	assert_eq(d.weather.queued_id(), WeatherDefs.HURRICANE)
	assert_almost_eq(d.weather.time_to_start(), 150.0, 0.2)


func test_save_load_mid_flood_recomputes_water() -> void:
	var e := WEnv.new(5000, RES)
	e.at_day(SeasonDefs.SPRING, 0.3, 10.0)
	e.weather.start_event(WeatherDefs.FLOOD, 120.0)
	e.run(WeatherDefs.FLOOD_RISE + 10.0)
	var n := e.weather.flood.flooded_count()
	assert_true(n > 0)
	var d := _roundtrip(e)
	assert_eq(d.weather.flood.flooded_count(), n, "flood recomputed from the saved phase")
	assert_false(d.vs.pathfinder.is_walkable_cell(Vector2i(d.weather.flood.flooded.keys()[0] % d.world.size, d.weather.flood.flooded.keys()[0] / d.world.size)))


func test_save_load_mid_fire_and_damage() -> void:
	var e := WEnv.new(5000, RES)
	e.at_day(SeasonDefs.SUMMER, 0.3, 10.0)
	var c := e.forest_cell(0)
	var bid := e.add_done(&"sawmill", 14.0, 0.0)
	var burnt := e.add_done(&"workshop", 14.0, 12.0)
	e.weather.fire.ignite_cell(c)
	e.weather.fire.ignite_building(bid)
	e.con.get_building(burnt).damaged = true
	e.con.get_building(burnt).repair_progress = 3.0
	e.run(5.0)
	var left: float = e.weather.fire.cells[e.weather.fire.idx(c)]["left"]
	var d := _roundtrip(e)
	var f := d.weather.fire
	assert_true(f.is_cell_burning(c))
	assert_almost_eq(float(f.cells[f.idx(c)]["left"]), left, 0.01)
	assert_true(f.is_building_burning(bid))
	assert_true(d.con.get_building(bid).burning, "burning flag restored")
	assert_true(d.con.get_building(burnt).damaged, "damage survives save")
	assert_almost_eq(d.con.get_building(burnt).repair_progress, 3.0, 0.5)
	d.weather.fire.burn_time = 1.0
	d.run(WeatherDefs.BURN_TIME + 5.0)
	assert_eq(d.eco.deposits.remaining(c), 0, "the loaded fire keeps burning to the end")
