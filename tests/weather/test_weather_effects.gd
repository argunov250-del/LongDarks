extends "res://tests/test_case.gd"

const WEnv = preload("res://tests/weather/weather_env.gd")

const RES := {&"logs": 200, &"planks": 100, &"stone": 100, &"scrap_metal": 50, &"spare_parts": 20, &"firewood": 50}


func _env(season: StringName = SeasonDefs.SUMMER, p: float = 0.3, hour: float = 10.0) -> WEnv:
	var e := WEnv.new(5000, RES)
	e.at_day(season, p, hour)
	return e


func test_dog_anxious_before_start_with_correct_lead() -> void:
	var e := _env(SeasonDefs.WINTER, 0.5)
	var lead := WeatherDefs.f(WeatherDefs.BLIZZARD, "lead", 0.0)
	var peak := WeatherDefs.f(WeatherDefs.BLIZZARD, "peak", 0.0)
	e.weather.queue_event(WeatherDefs.BLIZZARD, lead + 60.0, 120.0)
	e.run(30.0)
	assert_eq(e.vs.dog.anxious_level, 0.0, "calm before the lead window")
	var prev := 0.0
	var rose := false
	for i in int((lead + 60.0 - 30.0) / 2.0) + 5:
		e.run(2.0)
		var a := e.vs.dog.anxious_level
		assert_true(a >= prev - 0.0001, "anxiety grows monotonically")
		if a > 0.0:
			rose = true
		prev = a
		if e.weather.current_id() != &"":
			break
	assert_true(rose, "dog got anxious before the event started")
	assert_eq(e.weather.current_id(), WeatherDefs.BLIZZARD)
	# в начале окна lead уровень ещё мал, у старта близок к пику
	var e2 := _env(SeasonDefs.WINTER, 0.5)
	e2.weather.queue_event(WeatherDefs.BLIZZARD, lead, 120.0)
	e2.run(lead * 0.5)
	assert_almost_eq(e2.vs.dog.anxious_level, peak * 0.5, 0.03, "half way through the lead -> half the peak")
	e2.run(lead * 0.5 + 1.0)
	assert_almost_eq(e2.vs.dog.anxious_level, peak, 0.01, "peak while active")
	e2.weather.end_event()
	e2.run(WeatherDefs.AFTER_TIME + 2.0)
	assert_eq(e2.vs.dog.anxious_level, 0.0, "calm after")


func test_temperature_delta_goes_into_season() -> void:
	var e := _env(SeasonDefs.WINTER, 0.5)
	assert_eq(e.seasons.weather_temp_offset, 0.0)
	e.weather.start_event(WeatherDefs.BLIZZARD, 200.0)
	e.run(WeatherDefs.RAMP_IN / 2.0)
	assert_true(e.seasons.weather_temp_offset < -3.0 and e.seasons.weather_temp_offset > -5.0, "ramps in smoothly")
	e.run(WeatherDefs.RAMP_IN)
	assert_almost_eq(e.seasons.weather_temp_offset, -8.0, 0.01, "blizzard -8")
	e.weather.end_event()
	e.run(WeatherDefs.AFTER_TIME + 2.0)
	assert_eq(e.seasons.weather_temp_offset, 0.0, "back to normal")


func _progress(b: Building) -> float:
	return float(b.stage) * 1000.0 + b.progress


func test_construction_stops_in_blizzard_rain_storm_hurricane() -> void:
	for id in [WeatherDefs.BLIZZARD, WeatherDefs.DOWNPOUR, WeatherDefs.THUNDERSTORM, WeatherDefs.HURRICANE]:
		var e := _env(SeasonDefs.SUMMER, 0.5)
		var bid := e.place_near_hub(&"warehouse", 12.0, 0.0)
		var b := e.con.get_building(bid)
		e.run(30.0)
		var before := _progress(b)
		assert_true(before > 0.0, "%s: building progresses normally" % id)
		var pre := e.con.build_speed_multiplier
		e.weather.start_event(id, 600.0)
		e.run(2.0)
		assert_eq(e.con.build_speed_multiplier, 0.0, "%s stops construction" % id)
		var frozen := _progress(b)
		e.run(30.0)
		assert_eq(_progress(b), frozen, "%s: no progress during the event" % id)
		e.weather.end_event()
		e.run(3.0)
		assert_almost_eq(e.con.build_speed_multiplier, pre, 0.15, "%s: multiplier restored" % id)
		e.run(30.0)
		assert_true(_progress(b) > frozen, "%s: work resumes" % id)


func test_strong_frost_slows_but_does_not_stop() -> void:
	var e := _env(SeasonDefs.WINTER, 0.5)
	e.weather.start_event(WeatherDefs.SEVERE_FROST, 300.0)
	e.run(WeatherDefs.RAMP_IN + 2.0)
	var m := e.con.build_speed_multiplier
	assert_true(m > 0.0 and m < 1.0, "frost slows construction: %f" % m)


func test_villagers_go_home_and_outdoor_work_stops() -> void:
	var e := _env()
	e.enable_needs(10.0)
	e.vs.household.heating_needed = false
	var home := e.add_done(&"dugout", 10.0, 0.0)
	var other := e.add_villager(&"builder")
	e.vs.needs.assign_homes()
	for k in 5:
		e.place_near_hub(&"izba", 26.0 + 8.0 * k, 10.0)
	e.run(25.0)
	var working := 0
	for v: Villager in e.vs.villager_list():
		if v.task.get("kind", &"") == &"build":
			working += 1
	assert_true(working > 0, "people build before the storm")
	e.weather.start_event(WeatherDefs.THUNDERSTORM, 400.0)
	e.run(70.0)
	for v: Villager in e.vs.villager_list():
		assert_true(e.vs.needs.at_home(v), "villager %d is home" % v.id)
		assert_true(v.task.get("kind", &"") != &"build", "no outdoor work")
	assert_true(home > 0 and other.home_id == home)
	e.weather.end_event()
	e.run(60.0)
	var back := 0
	for v: Villager in e.vs.villager_list():
		if v.task.get("kind", &"") == &"build":
			back += 1
	assert_true(back > 0, "work resumes after the storm")


func test_caught_outside_loses_warmth_and_health_faster() -> void:
	var res: Array = []
	for storm in [false, true]:
		var e := _env(SeasonDefs.WINTER, 0.5)
		e.enable_needs(10.0)
		var v := e.add_villager(&"cook")  # бездомный: стоит на месте
		if storm:
			e.weather.start_event(WeatherDefs.BLIZZARD, 600.0)
		e.run(60.0)
		res.append([v.need(NeedsDefs.WARMTH), v.need(NeedsDefs.HEALTH)])
	assert_true(res[1][0] < res[0][0], "warmth falls faster in the blizzard")
	assert_true(res[1][1] < res[0][1], "and health too")


func test_rain_waters_garden() -> void:
	var gp: Array = []
	for rain in [false, true]:
		var e := _env()
		var hid := e.add_done(&"dugout", 10.0, 0.0)
		var h := e.vs.household.home(hid)
		e.vs.household.plant(hid)
		if rain:
			e.weather.start_event(WeatherDefs.DOWNPOUR, 600.0)
		e.run(20.0)
		gp.append(h.garden_progress)
	assert_almost_eq(gp[1] / gp[0], 1.3, 0.05, "rain grows the garden 1.3x faster")
	# после дождя эффект держится ещё сутки
	var e2 := _env()
	e2.weather.start_event(WeatherDefs.DOWNPOUR, 60.0)
	e2.run(70.0)
	e2.run(WeatherDefs.AFTER_TIME)
	assert_eq(e2.vs.household.garden_growth_multiplier, 1.3, "bonus lingers after rain")
	e2.run(WeatherDefs.GARDEN_RAIN_AFTER + 5.0)
	assert_eq(e2.vs.household.garden_growth_multiplier, 1.0, "then it ends")


func test_drought_slows_well_and_dries_garden() -> void:
	var e := _env()
	var hid := e.add_done(&"dugout", 10.0, 0.0)
	var h := e.vs.household.home(hid)
	e.vs.household.plant(hid)
	h.garden_progress = 100.0
	var norm := e.vs._phase_work({"phase": &"fetch", "kind": &"water"})
	e.weather.start_event(WeatherDefs.DROUGHT, 600.0)
	e.run(2.0)
	var dry := e.vs._phase_work({"phase": &"fetch", "kind": &"water"})
	assert_true(dry > norm * 2.0, "bucket fill is slower in drought")
	var p0 := h.garden_progress
	e.run(20.0)
	assert_true(h.garden_progress < p0, "unwatered garden dries out")
	assert_true(e.vs.household.water_decay_multiplier > 1.0, "heat: people drink more")
	e.weather.end_event()
	e.run(3.0)
	assert_eq(e.vs._phase_work({"phase": &"fetch", "kind": &"water"}), norm, "wells recover")


func test_burnt_soil_raises_garden_yield() -> void:
	var e := _env()
	var hid := e.add_done(&"dugout", 10.0, 0.0)
	var hs := e.vs.household
	assert_eq(hs.garden_yield(hid), HouseholdDefs.GARDEN_YIELD)
	var gp := hs.garden_pos(e.con.get_building(hid))
	e.weather.set_fertility(e.world.cell_of(gp.x, gp.z), WeatherDefs.BURN_FERTILITY)
	assert_eq(hs.garden_yield(hid), 12, "8 * 1.5")


func test_vehicle_stuck_hook() -> void:
	var e := _env()
	assert_eq(e.weather.vehicle_stuck_multiplier(), 0.0)
	e.weather.start_event(WeatherDefs.HURRICANE, 200.0)
	e.run(WeatherDefs.RAMP_IN + 1.0)
	assert_eq(e.weather.vehicle_stuck_multiplier(), 1.0)
	e.weather.end_event()
	e.run(WeatherDefs.AFTER_TIME + 1.0)
	assert_eq(e.weather.vehicle_stuck_multiplier(), 0.0)
