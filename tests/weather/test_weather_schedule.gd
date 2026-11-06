extends "res://tests/test_case.gd"

const WEnv = preload("res://tests/weather/weather_env.gd")


func _year_schedule(seed_value: int, mult: float) -> Array:
	var sim := Simulation.new(seed_value)
	var s := SeasonSystem.new()
	var w := WeatherSystem.new()
	sim.register_system(s)
	sim.register_system(w)
	s.attach(sim)
	w.attach(sim)
	w.seasons = s
	w.set_frequency_multiplier(mult)
	s.start_at(SeasonDefs.SPRING, 0.0)
	sim.clock.set_speed(3)
	var out: Array = []
	sim.bus.subscribe(WeatherSystem.TOPIC_STARTED, func(p): out.append([p["id"], snappedf(sim.clock.get_total_seconds(), 0.1), s.season()]))
	for i in int(s.year_length() / 3.0 / 0.1) + 200:
		sim.advance(0.1)
	return out


func test_schedule_is_deterministic_and_seasonal() -> void:
	var a := _year_schedule(99, 1.0)
	var b := _year_schedule(99, 1.0)
	assert_eq(a, b, "same seed -> same schedule")
	assert_true(a.size() >= 1 and a.size() <= 20, "plausible count: %d" % a.size())
	for e in a:
		var id: StringName = e[0]
		assert_true(not WeatherDefs.def(id).get("seasons", {}).get(e[2], {}).is_empty(), "%s allowed in %s" % [id, e[2]])
	var other := _year_schedule(5, 1.0)
	assert_true(other != a or a.is_empty(), "different seed differs")


func test_zero_frequency_means_no_events() -> void:
	assert_eq(_year_schedule(99, 0.0).size(), 0)


func test_roll_respects_season_windows() -> void:
	# осенняя метель только с 70 % осени; весенний паводок только в окне 10..50 %
	var hits := 0
	for day in 400:
		if WeatherSystem.roll(1, 1, day, WeatherDefs.BLIZZARD, SeasonDefs.AUTUMN, 0.5, 3, 2.0):
			hits += 1
		if WeatherSystem.roll(1, 1, day, WeatherDefs.FLOOD, SeasonDefs.SUMMER, 0.3, 3, 2.0):
			hits += 1
		if WeatherSystem.roll(1, 1, day, WeatherDefs.THUNDERSTORM, SeasonDefs.AUTUMN, 0.9, 3, 2.0):
			hits += 1
	assert_eq(hits, 0)
	var ok := 0
	for day in 400:
		if WeatherSystem.roll(1, 1, day, WeatherDefs.FLOOD, SeasonDefs.SPRING, 0.3, 3, 1.0):
			ok += 1
	assert_true(ok > 0, "flood possible in window")


func test_no_events_first_two_days() -> void:
	var e := WEnv.new()
	e.seasons.start_at(SeasonDefs.SUMMER, 0.3)
	e.weather.set_frequency_multiplier(100.0)  # бросок всегда успешен
	e.set_hour(7.0)
	var started := []
	e.sim.bus.subscribe(WeatherSystem.TOPIC_STARTED, func(p): started.append(e.sim.clock.get_day()))
	e.sim.clock.set_speed(3)
	var cap := 3 * e.sim.clock.day_seconds()
	for i in int(cap / 3.0 / 0.1):
		e.sim.advance(0.1)
		if e.sim.clock.get_day() <= 2:
			assert_true(started.is_empty(), "no events before day 3")
	assert_true(not started.is_empty() or e.weather.queued_id() != &"", "event on day 3+")
	for d in started:
		assert_true(d >= 3)
