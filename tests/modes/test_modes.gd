extends "res://tests/test_case.gd"
## Шаг 25: режимы и сложность (design/gdd/modes-difficulty.md).

const P := "__mtest_"
const NeighbourEnv := preload("res://tests/neighbours/neighbour_env.gd")


func _cleanup() -> void:
	for s in SaveManager.list_slots():
		if s.begins_with(P):
			SaveManager.delete_slot(s)


func test_presets_map_to_knobs() -> void:
	for id in ModeDefs.PRESET_ORDER:
		var g := GameSettings.new(id)
		var p: Dictionary = ModeDefs.PRESETS[id]
		assert_eq(g.preset, id)
		assert_almost_eq(g.winter_mult, float(p["winter_mult"]))
		assert_eq(g.neighbour_mode, p["neighbour_mode"])
		assert_almost_eq(g.weather_mult, float(p["weather_mult"]))
	var g2 := GameSettings.new()
	g2.set_winter_mult(1.23)
	assert_eq(g2.preset, ModeDefs.CUSTOM, "tweaking a knob makes the preset custom")
	g2.set_winter_mult(99.0)
	assert_almost_eq(g2.winter_mult, ModeDefs.WINTER_MULT_RANGE.y, 0.0001, "clamped")
	assert_true(g2.set_mode(ModeDefs.CAREER), "career enabled (step 26)")
	assert_true(g2.set_mode(ModeDefs.SANDBOX))


func test_winter_knob_changes_winter_minutes() -> void:
	var e := NeighbourEnv.new()
	var g := GameSettings.new()
	g.bind(e.seasons, null, e.nb)
	g.set_winter_mult(1.5)
	g.apply()
	assert_almost_eq(e.seasons.duration_minutes(SeasonDefs.WINTER), SeasonDefs.DEFAULT_MINUTES[SeasonDefs.WINTER] * 1.5, 0.001)
	g.set_preset(ModeDefs.EASY)
	g.apply()
	assert_almost_eq(e.seasons.duration_minutes(SeasonDefs.WINTER), SeasonDefs.DEFAULT_MINUTES[SeasonDefs.WINTER] * 0.7, 0.001)


func test_weather_knob_scales_event_rate() -> void:
	var w := WeatherSystem.new()
	var g := GameSettings.new()
	g.bind(null, w, null)
	var counts := []
	for m in [0.5, 1.0, 2.0]:
		g.set_weather_mult(m)
		g.apply()
		assert_almost_eq(w.frequency_multiplier, m)
		var c := 0
		for day in 2000:
			for id in WeatherDefs.ORDER:
				if WeatherSystem.roll(1, 1, day, id, SeasonDefs.SPRING, 0.5, 25, w.frequency_multiplier):
					c += 1
		counts.append(c)
	assert_true(counts[0] < counts[1] and counts[1] < counts[2], "rate grows with multiplier: %s" % str(counts))
	assert_true(absf(float(counts[2]) / maxf(1.0, counts[1]) - 2.0) < 0.35, "about x2: %s" % str(counts))


func _incidents(mode: StringName, days: int) -> int:
	var e := NeighbourEnv.new()
	var g := GameSettings.new()
	g.bind(e.seasons, null, e.nb)
	g.set_neighbour_mode(mode)
	g.apply()
	e.z()["relation"] = -0.9
	e.z()["baseline"] = -5.0  # relation stays hostile
	var c := 0
	for _i in days:
		e.z()["relation"] = -0.9
		e.z()["cd_theft"] = 0.0
		e.z()["cd_raid"] = 0.0
		e.nb.step_days(1.0)
		c = int(e.z()["thefts"]) + e.nb.parties.size()
	return c


func test_neighbour_knob_changes_raid_frequency() -> void:
	var peace := _incidents(ModeDefs.PEACEFUL, 120)
	var normal := _incidents(ModeDefs.NORMAL, 120)
	var aggr := _incidents(ModeDefs.AGGRESSIVE, 120)
	assert_true(peace < normal and normal < aggr, "peaceful < normal < aggressive: %d %d %d" % [peace, normal, aggr])


func test_settings_saved_and_loaded_with_game() -> void:
	var e := NeighbourEnv.new()
	var g := GameSettings.new()
	g.bind(e.seasons, null, e.nb)
	e.sim.register_system(g)
	g.set_preset(ModeDefs.HARD)
	g.set_winter_mult(1.65)
	g.apply()
	var sess := GameSession.new(e.sim, g, e.seasons, e.vs)
	assert_eq(sess.save(P + "a", "Тест"), OK)
	g.set_preset(ModeDefs.EASY)
	g.apply()
	assert_eq(sess.load_slot(P + "a"), OK)
	assert_almost_eq(g.winter_mult, 1.65, 0.0001)
	assert_eq(g.neighbour_mode, ModeDefs.AGGRESSIVE)
	assert_almost_eq(e.seasons.duration_minutes(SeasonDefs.WINTER), 30.0 * 1.65, 0.001)
	assert_almost_eq(e.nb.incident_scale, 2.0)
	_cleanup()


func test_named_slots_list_and_delete() -> void:
	var e := NeighbourEnv.new()
	var g := GameSettings.new()
	var sess := GameSession.new(e.sim, g, e.seasons, e.vs)
	assert_eq(sess.save(P + "one", "Первый"), OK)
	assert_eq(sess.save(P + "two", "Второй"), OK)
	var names: Array[String] = []
	for i in SaveManager.list_infos():
		if String(i["slot"]).begins_with(P):
			names.append(i["slot"])
			assert_true(i.has("day") and i.has("season") and i.has("population") and i.has("saved_at"), "meta present")
	assert_eq(names.size(), 2)
	var info := SaveManager.slot_info(P + "one")
	assert_eq(info["name"], "Первый")
	assert_eq(SaveManager.to_int(info["day"]), 1)
	assert_eq(SaveManager.delete_slot(P + "one"), OK)
	assert_eq(SaveManager.list_slots().has(P + "one"), false)
	assert_eq(SlotsView.slot_for_name("a/b:c"), "a_b_c")
	assert_eq(sess.save("", "x"), ERR_INVALID_PARAMETER)
	_cleanup()


func test_autosave_daily_and_on_pause() -> void:
	var e := NeighbourEnv.new()
	var g := GameSettings.new()
	var sess := GameSession.new(e.sim, g, e.seasons, e.vs)
	var count := [0]
	sess.autosave.save_fn = func() -> Error:
		count[0] += 1
		return OK
	e.sim.advance(1.0)
	assert_eq(count[0], 0, "no save inside the first day")
	e.sim.clock.set_total_seconds(e.sim.clock.day_seconds() * 1.01)
	e.sim.advance(0.2)
	assert_eq(count[0], 1, "one autosave at day change")
	e.sim.advance(0.2)
	assert_eq(count[0], 1, "not again in the same day")
	sess.autosave.on_app_paused()
	assert_eq(count[0], 2, "autosave on app pause")
	# real slot
	sess.autosave.save_fn = func() -> Error: return sess.save(P + "auto", "Авто")
	assert_eq(sess.autosave.trigger(), OK)
	assert_true(SaveManager.list_slots().has(P + "auto"))
	_cleanup()
