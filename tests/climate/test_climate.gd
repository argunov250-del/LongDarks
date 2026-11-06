extends "res://tests/test_case.gd"
## Шаг 15, design/gdd/climate-warming.md.

const CEnv = preload("res://tests/climate/climate_env.gd")


func test_base_warming_over_years() -> void:
	var e := CEnv.new()
	e.run_years(1.0)
	assert_almost_eq(e.climate.warming(), ClimateDefs.BASE_WARMING_PER_YEAR, 0.001, "one year = base warming")
	e.run_years(3.0)
	assert_almost_eq(e.climate.warming(), ClimateDefs.BASE_WARMING_PER_YEAR * 4.0, 0.001)
	assert_almost_eq(e.seasons.climate_temp_offset, e.climate.warming() * ClimateDefs.TEMP_PER_WARMING, 0.001)


func test_winter_shortens_but_not_below_minimum() -> void:
	var e := CEnv.new()
	var w0 := e.seasons.duration_minutes(SeasonDefs.WINTER)
	e.run_years(3.0)
	var w1 := e.seasons.duration_minutes(SeasonDefs.WINTER)
	assert_true(w1 < w0, "winter is shorter after years")
	e.climate.set_planted_forest_cells(100000)
	e.climate.set_plowed_cells(100000)
	e.run_years(40.0)
	assert_almost_eq(e.seasons.duration_minutes(SeasonDefs.WINTER), w0 * ClimateDefs.WINTER_MIN_FRACTION, 0.001, "floor")
	assert_almost_eq(e.climate.warming(), ClimateDefs.MAX_WARMING, 0.001, "warming capped")


func test_year_length_constant() -> void:
	var e := CEnv.new()
	var yl := e.seasons.year_length()
	for i in 6:
		e.run_years(1.0)
		assert_almost_eq(e.seasons.year_length(), yl, 0.01, "year length after %d years" % (i + 1))
	assert_true(e.seasons.duration_minutes(SeasonDefs.SPRING) > SeasonDefs.DEFAULT_MINUTES[SeasonDefs.SPRING], "spring gains")
	assert_true(e.seasons.duration_minutes(SeasonDefs.SUMMER) > SeasonDefs.DEFAULT_MINUTES[SeasonDefs.SUMMER], "summer gains")


func test_planted_and_plowed_speed_up() -> void:
	var a := CEnv.new()
	var b := CEnv.new()
	var c := CEnv.new()
	b.climate.register_planted_forest_cells(100)
	c.climate.set_plowed_cells(50)
	a.run_years(2.0)
	b.run_years(2.0)
	c.run_years(2.0)
	assert_true(b.climate.warming() > a.climate.warming(), "planted forest accelerates")
	assert_true(c.climate.warming() > a.climate.warming(), "plowed soil accelerates")
	var cap := CEnv.new()
	cap.climate.set_planted_forest_cells(10 ** 6)
	assert_almost_eq(cap.climate.acceleration_bonus(), ClimateDefs.FOREST_BONUS_MAX, 0.0001, "bonus capped")


func test_forest_provider_query() -> void:
	var e := CEnv.new()
	var n := [40]
	e.climate.set_planted_provider(func() -> int: return n[0])
	var b1 := e.climate.acceleration_bonus()
	n[0] = 0
	assert_true(b1 > 0.0 and e.climate.acceleration_bonus() == 0.0, "provider is polled")


func test_removing_forest_removes_bonus_but_never_cools() -> void:
	var e := CEnv.new()
	e.climate.register_planted_forest_cells(200)
	e.run_years(1.0)
	var w := e.climate.warming()
	e.climate.register_planted_forest_cells(-200)
	assert_eq(e.climate.acceleration_bonus(), 0.0, "bonus gone")
	e.climate.register_planted_forest_cells(-50)
	assert_eq(e.climate.planted_forest_cells(), 0, "never negative")
	assert_eq(e.climate.warming(), w, "cutting does not cool")
	var off := e.seasons.climate_temp_offset
	e.run_years(1.0)
	assert_true(e.climate.warming() > w, "base warming continues")
	assert_true(e.seasons.climate_temp_offset >= off, "temperature never drops")
	assert_almost_eq(e.climate.warming() - w, ClimateDefs.BASE_WARMING_PER_YEAR, 0.001, "only base remains")


func test_milestones_emit_once() -> void:
	var e := CEnv.new()
	e.climate.set_plowed_cells(100000)
	e.climate.set_planted_forest_cells(100000)
	e.run_years(40.0)
	assert_eq(e.count(ClimateSystem.TOPIC_FIRST_BIRDS), 1, "first_birds once")
	assert_eq(e.count(ClimateSystem.TOPIC_WARMING_MILESTONE), ClimateDefs.MILESTONES.size(), "each milestone once")
	e.run_years(5.0)
	assert_eq(e.count(ClimateSystem.TOPIC_FIRST_BIRDS), 1)
	assert_eq(e.count(ClimateSystem.TOPIC_WARMING_MILESTONE), ClimateDefs.MILESTONES.size())


func test_first_birds_in_first_spring_and_bird_count() -> void:
	var e := CEnv.new()
	assert_eq(e.climate.bird_count(), 0)
	e.run(10.0)  # старт в начале весны: первая весна игры
	assert_eq(e.count(ClimateSystem.TOPIC_FIRST_BIRDS), 1, "first_birds in the first spring")
	assert_true(e.climate.warming() < 0.1, "regardless of warming")
	var n1 := e.climate.bird_count()
	assert_true(n1 >= ClimateDefs.BIRDS_MIN)
	e.climate.set_plowed_cells(100000)
	e.run_years(30.0)
	assert_eq(e.count(ClimateSystem.TOPIC_FIRST_BIRDS), 1, "only once")
	assert_true(e.climate.bird_count() > n1, "more birds as it warms")
	assert_true(e.climate.bird_count() <= ClimateDefs.BIRDS_MAX)


func test_snow_melts_earlier_when_warm() -> void:
	var e := CEnv.new()
	e.seasons.start_at(SeasonDefs.SPRING, 0.3)
	var cold := e.seasons.snow_cover()
	e.climate.set_plowed_cells(100000)
	e.climate.set_planted_forest_cells(100000)
	e.run_years(40.0)
	e.seasons.start_at(SeasonDefs.SPRING, 0.3)
	assert_true(e.seasons.snow_cover() < cold, "less snow at the same spring progress")
	assert_true(e.seasons.outdoor_temp() > -50.0)


func test_no_climate_scale_ui() -> void:
	var hud := FileAccess.get_file_as_string("res://src/ui/hud.gd")
	assert_false(hud.to_lower().contains("climate") or hud.to_lower().contains("warming"), "HUD has no climate scale")
	assert_false(ClassDB.class_exists(&"ClimateUI"))


func test_save_load_roundtrip() -> void:
	var e := CEnv.new()
	e.climate.register_planted_forest_cells(30)
	e.run_years(3.0)
	var text := JSON.stringify({"c": e.climate.save_state(), "s": e.seasons.save_state()})
	var json := JSON.new()
	assert_eq(json.parse(text), OK)
	var d := CEnv.new()
	d.seasons.load_state(json.data["s"])
	d.climate.load_state(json.data["c"])
	assert_almost_eq(d.climate.warming(), e.climate.warming(), 0.0001)
	assert_eq(d.climate.planted_forest_cells(), 30)
	assert_eq(d.climate.first_birds_seen(), e.climate.first_birds_seen())
	assert_almost_eq(d.seasons.duration_minutes(SeasonDefs.WINTER), e.seasons.duration_minutes(SeasonDefs.WINTER), 0.001)
	assert_almost_eq(d.seasons.climate_temp_offset, e.seasons.climate_temp_offset, 0.0001)
	var before := d.events.size()
	d.run_years(0.5)
	assert_eq(d.count(ClimateSystem.TOPIC_FIRST_BIRDS), 0, "already-fired flag survives load: no repeat")
	assert_true(before == 0)
