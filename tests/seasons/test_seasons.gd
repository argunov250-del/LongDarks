extends "res://tests/test_case.gd"

const SEnv = preload("res://tests/seasons/season_env.gd")


func test_day_length_is_8_minutes() -> void:
	assert_eq(GameClock.DEFAULT_DAY_LENGTH, 480.0)
	var c := GameClock.new()
	c.set_total_seconds(480.0)
	assert_eq(c.get_day(), 2, "one game day = 8 min at 1x")


## Все скорости «в сутки» — от одних игровых суток: житель ест и пьёт примерно раз в сутки.
func test_villager_eats_and_drinks_about_once_a_day() -> void:
	var e := SEnv.new()
	e.at(SeasonDefs.SUMMER, 0.3, 8.0)  # тепло: без зимнего множителя
	e.vs.needs_enabled = true
	var v := e.add_villager(&"cook")
	v.set_need(NeedsDefs.FOOD, NeedsDefs.MEAL_FULL)
	v.set_need(NeedsDefs.WATER, NeedsDefs.MEAL_FULL)
	var day := e.sim.clock.day_seconds()
	var food_drop := NeedsDefs.FOOD_DECAY_PER_DAY * e.vs.consumption_multiplier()
	var water_drop := NeedsDefs.WATER_DECAY_PER_DAY * e.vs.consumption_multiplier()
	var gap := NeedsDefs.MEAL_FULL - NeedsDefs.EAT_BELOW
	assert_true(gap / food_drop >= 0.6 and gap / food_drop <= 1.2, "meal every ~day: %.2f days" % (gap / food_drop))
	assert_true(gap / water_drop >= 0.5 and gap / water_drop <= 1.0, "drink every ~day: %.2f days" % (gap / water_drop))
	# убыль за реальное время совпадает с «за сутки» (днём, без сна: множитель 1)
	var f0 := v.need(NeedsDefs.FOOD)
	e.run(day * 0.1)
	assert_almost_eq(f0 - v.need(NeedsDefs.FOOD), food_drop * 0.1, 0.01, "food per game day")


func test_season_order_and_durations() -> void:
	assert_eq(SeasonDefs.ORDER, [SeasonDefs.SPRING, SeasonDefs.SUMMER, SeasonDefs.AUTUMN, SeasonDefs.WINTER])
	var s := SeasonSystem.new()
	assert_eq(s.duration_minutes(SeasonDefs.WINTER), 30.0)
	assert_eq(s.duration_minutes(SeasonDefs.SPRING), 25.0)
	assert_eq(s.duration_minutes(SeasonDefs.AUTUMN), 25.0)
	assert_eq(s.duration_minutes(SeasonDefs.SUMMER), 20.0)
	for se in SeasonDefs.ORDER:
		assert_true(s.duration(SeasonDefs.WINTER) >= s.duration(se), "winter longest")
		assert_true(s.duration(SeasonDefs.SUMMER) <= s.duration(se), "summer shortest")
	# смена сезонов по ходу симуляции: события в порядке, моменты — по длительностям
	var sim := Simulation.new(1)
	sim.register_system(s)
	s.attach(sim)
	s.start_at(SeasonDefs.SPRING, 0.0)
	var seen: Array = []
	sim.bus.subscribe(SeasonSystem.TOPIC_SEASON_CHANGED, func(p): seen.append([p["season"], sim.clock.get_total_seconds()]))
	sim.clock.set_speed(3)
	var year := s.year_length()
	assert_almost_eq(year, 100.0 * 60.0, 0.01, "year = 100 real minutes at 1x")
	for i in int((year + 30.0) / 0.3):
		sim.advance(0.1)
	var names := seen.map(func(x): return x[0])
	assert_eq(names, [SeasonDefs.SUMMER, SeasonDefs.AUTUMN, SeasonDefs.WINTER, SeasonDefs.SPRING])
	assert_almost_eq(seen[0][1], 25.0 * 60.0, 0.5, "summer after 25 min of spring")
	assert_almost_eq(seen[1][1], 45.0 * 60.0, 0.5)
	assert_almost_eq(seen[2][1], 70.0 * 60.0, 0.5)
	assert_almost_eq(seen[3][1], 100.0 * 60.0, 0.5)
	assert_eq(s.year(), 2)


func test_day_of_season_and_progress() -> void:
	var e := SEnv.new()
	e.seasons.start_at(SeasonDefs.SPRING, 0.0)
	assert_eq(e.seasons.day_of_season(), 1)
	e.seasons.start_at(SeasonDefs.SPRING, 0.5)
	assert_almost_eq(e.seasons.progress(), 0.5, 0.001)
	assert_eq(e.seasons.day_of_season(), int(25.0 * 60.0 * 0.5 / GameClock.DEFAULT_DAY_LENGTH) + 1, "day 2 of spring")
	assert_eq(e.seasons.days_in_season(SeasonDefs.WINTER), 4, "winter ~ 3.75 days of 8 min")


func test_durations_configurable_hook() -> void:
	var s := SeasonSystem.new()
	s.start_at(SeasonDefs.WINTER, 0.5)
	s.set_duration_minutes(SeasonDefs.WINTER, 20.0)
	s.set_duration_minutes(SeasonDefs.SUMMER, 30.0)
	assert_eq(s.duration_minutes(SeasonDefs.WINTER), 20.0)
	assert_almost_eq(s.year_length(), 100.0 * 60.0, 0.01)
	assert_eq(s.season(), SeasonDefs.WINTER, "stays in the same season")
	assert_almost_eq(s.progress(), 0.5, 0.001)
	s.set_duration_minutes(SeasonDefs.SPRING, -1.0)
	assert_eq(s.duration_minutes(SeasonDefs.SPRING), 25.0, "invalid ignored")


## Температура во всех сезонах, все часы суток: диапазоны и порядок средних.
func test_temperature_range_per_season() -> void:
	var e := SEnv.new()
	var ranges := {
		SeasonDefs.SPRING: [-12.0, 26.0], SeasonDefs.SUMMER: [3.0, 32.0],
		SeasonDefs.AUTUMN: [-15.0, 22.0], SeasonDefs.WINTER: [-28.0, 6.0],
	}
	var mean := {}
	for se in SeasonDefs.ORDER:
		var sum := 0.0
		var n := 0
		for i in 21:
			for h in [0.0, 4.0, 8.0, 12.0, 15.0, 20.0]:
				e.at(se, i / 20.0, h)
				var t := e.seasons.outdoor_temp()
				assert_true(t >= ranges[se][0] and t <= ranges[se][1], "%s %.2f h%.0f: %.1f" % [se, i / 20.0, h, t])
				sum += t
				n += 1
		mean[se] = sum / n
	assert_true(mean[SeasonDefs.SUMMER] > mean[SeasonDefs.SPRING] and mean[SeasonDefs.SUMMER] > mean[SeasonDefs.AUTUMN], "summer warmest")
	assert_true(mean[SeasonDefs.WINTER] < mean[SeasonDefs.SPRING] and mean[SeasonDefs.WINTER] < mean[SeasonDefs.AUTUMN], "winter coldest")
	e.at(SeasonDefs.WINTER, 0.5, 3.0)
	assert_true(e.seasons.outdoor_temp() < -8.0, "deep winter frost")
	e.at(SeasonDefs.SUMMER, 0.5, 15.0)
	assert_true(e.seasons.outdoor_temp() > 14.0, "summer afternoon warm")
	# день теплее ночи
	e.at(SeasonDefs.SPRING, 0.5, 15.0)
	var day := e.seasons.outdoor_temp()
	e.at(SeasonDefs.SPRING, 0.5, 3.0)
	assert_true(day > e.seasons.outdoor_temp() + 4.0, "day/night swing")


## Целый год по 1 игр. с: без скачков (и на стыках сезонов), детерминированно.
func test_temperature_continuity_and_determinism() -> void:
	var run := func() -> Array:
		var sim := Simulation.new(3)
		var s := SeasonSystem.new()
		sim.register_system(s)
		s.attach(sim)
		s.start_at(SeasonDefs.SPRING, 0.0)
		sim.clock.set_speed(1)
		var prev := s.outdoor_temp()
		var max_step := 0.0
		var samples: Array = []
		var steps := int(s.year_length()) * 10
		for i in steps:
			sim.advance(0.1)
			if i % 10 == 0:
				var t := s.outdoor_temp()
				max_step = maxf(max_step, absf(t - prev))
				prev = t
				if i % 6000 == 0:
					samples.append(t)
		return [max_step, samples]
	var a: Array = run.call()
	# предел — крутизна суточного хода (5.5 °C · 2π / 480 с ≈ 0.07 °C/с) + шум; скачков нет
	assert_true(a[0] < 0.15, "max change per game second %.3f" % a[0])
	var b: Array = run.call()
	assert_eq(a[1], b[1], "deterministic")


func test_heating_only_at_or_below_plus_5() -> void:
	var e := SEnv.new()
	var hs := e.vs.household
	var seen_on := false
	var seen_off := false
	for se in SeasonDefs.ORDER:
		for i in 11:
			for h in [3.0, 15.0]:
				e.at(se, i / 10.0, h)
				var t := e.seasons.outdoor_temp()
				assert_eq(hs.heating_needed, t <= SeasonDefs.HEATING_MAX_TEMP, "%s %.1f °C" % [se, t])
				seen_on = seen_on or hs.heating_needed
				seen_off = seen_off or not hs.heating_needed
	assert_true(seen_on and seen_off)
	# печь: летом не требует дров, зимой — требует; чем холоднее, тем быстрее горит
	var id := e.add_done(&"dugout", 10.0, 0.0)
	e.at(SeasonDefs.SUMMER, 0.5, 15.0)
	assert_eq(hs.stove_demand(id), 0, "no stoking in summer")
	e.at(SeasonDefs.AUTUMN, 0.5, 15.0)
	var autumn_burn := hs.fuel_per_day()
	e.at(SeasonDefs.WINTER, 0.5, 3.0)
	assert_true(hs.stove_demand(id) > 0, "stove wants wood in winter")
	assert_true(hs.fuel_per_day() > autumn_burn * 1.3, "colder -> stove burns faster")


func test_cold_and_consumption_hooks_follow_temperature() -> void:
	var e := SEnv.new()
	e.at(SeasonDefs.SUMMER, 0.5, 15.0)
	var summer_cold := e.vs.outdoor_cold()
	var summer_mult := e.vs.consumption_multiplier()
	e.at(SeasonDefs.WINTER, 0.5, 3.0)
	assert_true(e.vs.outdoor_cold() > summer_cold + 0.4, "winter is cold")
	assert_almost_eq(e.vs.outdoor_cold(), SeasonDefs.cold_from_temp(e.seasons.outdoor_temp()), 0.001)
	assert_true(e.vs.consumption_multiplier() > summer_mult, "winter consumption higher")
	assert_almost_eq(summer_mult, 1.0, 0.001)


func test_ground_frozen_blocks_foundation_in_winter_only() -> void:
	var probe := SeasonSystem.new()
	for se in SeasonDefs.ORDER:
		for i in 21:
			probe.start_at(se, i / 20.0)
			if probe.ground_frozen():
				assert_eq(se, SeasonDefs.WINTER, "frozen only in winter (%s %.2f)" % [se, i / 20.0])
	probe.start_at(SeasonDefs.WINTER, 0.5)
	assert_true(probe.ground_frozen(), "deep winter frozen")
	# фундамент не начинается зимой, начинается летом; стройка в мороз медленнее
	var e := SEnv.new(5000, {&"logs": 40})
	e.at(SeasonDefs.WINTER, 0.5, 12.0)
	assert_true(e.con.ground_frozen)
	assert_true(e.con.build_speed_multiplier < 1.0, "frost slows building")
	var id := e.place_near_hub(&"dugout", 10.0, 0.0)
	e.run(3.0)
	var b := e.con.get_building(id)
	assert_eq(b.blocked, &"frozen")
	assert_false(b.stage_paid, "foundation not started")
	assert_eq(e.eco.total(&"logs"), 40, "nothing spent")
	e.at(SeasonDefs.SUMMER, 0.5, 12.0)
	e.run(3.0)
	assert_false(e.con.ground_frozen)
	assert_eq(e.con.build_speed_multiplier, 1.0)
	assert_true(b.stage_paid, "foundation poured in summer")
	assert_true(b.blocked != &"frozen")


## Распутица: весной жители идут медленнее (и есть хук mud_level).
func test_mud_slows_walking_in_spring() -> void:
	var dist := func(se: StringName, p: float) -> Array:
		var e := SEnv.new(5000, {&"logs": 40, &"planks": 40})
		e.at(se, p, 10.0)
		var hero := e.hero()
		var id := e.place_near_hub(&"dugout", 40.0, 0.0)
		e.run(0.5)  # выбрал задачу
		var start := hero.pos
		var walked := 0.0
		for i in 20:
			var before := hero.pos
			e.run(0.1)
			walked += Vector2(hero.pos.x - before.x, hero.pos.z - before.z).length()
		return [walked, e.vs.mud_level, e.vs.walk_speed_multiplier, id, start]
	var spring: Array = dist.call(SeasonDefs.SPRING, 0.3)
	var summer: Array = dist.call(SeasonDefs.SUMMER, 0.5)
	assert_true(spring[1] > 0.9, "full mud early spring: %.2f" % spring[1])
	assert_almost_eq(summer[1], 0.0, 0.0001, "no mud in summer")
	assert_almost_eq(spring[2], 1.0 - SeasonDefs.MUD_WALK_SLOW * spring[1], 0.001)
	assert_true(summer[0] > 1.0, "hero walks: %.2f" % summer[0])
	assert_true(spring[0] < summer[0] * 0.8, "slower on mud: %.2f vs %.2f" % [spring[0], summer[0]])
	var s := SeasonSystem.new()
	s.start_at(SeasonDefs.SPRING, 0.99)
	assert_true(s.mud_level() < 0.05, "dries by summer")
	for se in [SeasonDefs.SUMMER, SeasonDefs.AUTUMN, SeasonDefs.WINTER]:
		s.start_at(se, 0.5)
		assert_eq(s.mud_level(), 0.0)


func test_garden_gated_by_season() -> void:
	assert_true(HouseholdDefs.garden_season_allows(SeasonDefs.SPRING, &"plant"))
	assert_false(HouseholdDefs.garden_season_allows(SeasonDefs.SUMMER, &"plant"))
	assert_true(HouseholdDefs.garden_season_allows(SeasonDefs.SUMMER, &"grow"))
	assert_true(HouseholdDefs.garden_season_allows(SeasonDefs.AUTUMN, &"harvest"))
	for ph in [&"plant", &"grow", &"harvest"]:
		assert_false(HouseholdDefs.garden_season_allows(SeasonDefs.WINTER, ph), "nothing in winter: %s" % ph)
	var e := SEnv.new()
	var hs := e.vs.household
	var id := e.add_done(&"dugout", 10.0, 0.0)
	var h := hs.home(id)
	e.at(SeasonDefs.WINTER, 0.5)
	assert_false(hs.can_plant(id), "no planting in winter")
	e.at(SeasonDefs.SPRING, 0.5)
	assert_true(hs.can_plant(id), "plant in spring")
	assert_true(hs.plant(id))
	hs.tick(e.sim, 30.0)
	assert_eq(h.garden_progress, 0.0, "does not grow in spring")
	e.at(SeasonDefs.SUMMER, 0.2)
	for i in int(HouseholdDefs.GARDEN_GROW_TIME / 10.0) + 1:
		hs.tick(e.sim, 10.0)
	assert_eq(h.garden_state, Household.GARDEN_RIPE, "grows in summer")
	assert_false(hs.can_harvest(id), "harvest waits for autumn")
	e.at(SeasonDefs.AUTUMN, 0.3)
	assert_true(hs.can_harvest(id), "harvest in autumn")
	e.at(SeasonDefs.WINTER, 0.1)
	assert_false(hs.can_harvest(id))


func test_spoilage_stops_below_plus_4() -> void:
	var e := SEnv.new()
	e.at(SeasonDefs.WINTER, 0.5)
	assert_true(e.eco.ambient_cold, "no spoilage in frost")
	e.at(SeasonDefs.SUMMER, 0.5, 15.0)
	assert_false(e.eco.ambient_cold, "summer spoils")
	e.storage.add(&"milk", 100)
	var id := e.add_done(&"dugout", 10.0, 0.0)
	e.vs.household.add_food(id, &"milk", 20)
	e.at(SeasonDefs.WINTER, 0.5)
	e.eco.tick(e.sim, 5000.0)
	e.vs.household.tick(e.sim, 5000.0)
	assert_eq(e.storage.amount(&"milk"), 100, "storage milk kept in cold")
	assert_eq(e.vs.household.home(id).food.amount(&"milk"), 20, "house milk kept in cold")


func test_start_state_contents() -> void:
	var e := SEnv.new(10, {})
	var eco := e.eco
	StartState.create_storage(e.world, eco)
	var id := StartState.populate(e.con, e.vs, e.seasons)
	assert_true(id > 0, "house placed")
	var b := e.con.get_building(id)
	assert_eq(b.type, &"dugout")
	assert_true(b.is_done(), "built")
	assert_eq(e.vs.population(), 1, "only the hero")
	assert_true(e.hero().is_hero)
	assert_true(e.vs.dog != null, "and the dog")
	assert_eq(e.hero().home_id, id, "hero lives in the dugout")
	var h := e.vs.household.home(id)
	assert_true(h.food.used() > 0 and h.food.used() <= 15, "small food supply at home: %d" % h.food.used())
	assert_true(h.water > 0, "some water at home")
	assert_true(h.woodpile > 0 and h.stove > 0 and h.lit(), "stove lit, woodpile stocked")
	var food := 0
	for res in ResourceDefs.ids_in_category(ResourceDefs.Category.FOOD):
		food += eco.total(res)
	assert_true(food > 0 and food <= 20, "small food in storage: %d" % food)
	assert_true(eco.total(&"firewood") >= 3 * (food + h.food.used()), "much more firewood than food")
	assert_eq(e.seasons.season(), SeasonDefs.WINTER, "starts in winter")
	assert_true(e.seasons.progress() >= 0.75, "end of winter")
	assert_eq(StartState.START_SEASON_PROGRESS, 0.8)
	# дом сразу отапливается и стоит у героя рядом
	for c in StartState.site_cells(e.world, b.position, b.rot, StartState.POISON_BUFFER_CELLS):
		if c.x >= 0 and c.y >= 0 and c.x < e.world.size and c.y < e.world.size:
			assert_true(e.world.cell_type(c.x, c.y) != WorldMap.Terrain.POISON, "start house outside poison buffer")
	var d := e.vs.household.door_pos(b)
	assert_true(Vector2(d.x - e.hero().pos.x, d.z - e.hero().pos.z).length() < 6.0, "hero near home")


## Стартовый дом с двором — вне отравленной зоны (с буфером), не на воде/склоне, лес и вода рядом.
func test_start_site_avoids_poison_with_buffer() -> void:
	for seed_value in [12345, 20260401, 7, 99]:
		var world := WorldMap.new(seed_value)
		var eco := EconomySystem.new(world)
		var con := ConstructionSystem.new(world, eco)
		var f := world.factory_cell
		var hub := world.cell_center(f.x, f.y)
		var p := StartState.find_house_site(con, hub)
		assert_true(p != Vector3.INF, "site found (seed %d)" % seed_value)
		if p == Vector3.INF:
			continue
		for c in StartState.site_cells(world, p, 0.0, StartState.POISON_BUFFER_CELLS):
			if c.x >= 0 and c.y >= 0 and c.x < world.size and c.y < world.size:
				assert_true(world.cell_type(c.x, c.y) != WorldMap.Terrain.POISON, "no poison near house/yard %s (seed %d)" % [c, seed_value])
		for c in StartState.site_cells(world, p, 0.0, 0):
			assert_false(WorldMap.is_water_type(world.cell_type(c.x, c.y)), "not on water")
		assert_true(con.validate_placement(StartState.HOUSE_TYPE, p, 0.0)["ok"], "valid: no water, slope ok")
		assert_true(con.placement_tree_cells(StartState.HOUSE_TYPE, p, 0.0).is_empty(), "no trees under house")
		var hc := world.cell_of(p.x, p.z)
		assert_true(StartState._near(world, hc, StartState.FOREST_NEAR_CELLS, false), "forest near (seed %d)" % seed_value)
		assert_true(StartState._near(world, hc, StartState.WATER_NEAR_CELLS, true), "water near (seed %d)" % seed_value)


func test_save_load_mid_season() -> void:
	var e := SEnv.new()
	e.seasons.set_duration_minutes(SeasonDefs.SUMMER, 18.0)
	e.at(SeasonDefs.AUTUMN, 0.37, 9.0)
	e.run(7.0)
	var data := e.sim.to_dict()
	var json: Dictionary = JSON.parse_string(JSON.stringify(data))
	var e2 := SEnv.new()
	e2.sim.from_dict(json)
	assert_eq(e2.seasons.season(), SeasonDefs.AUTUMN)
	assert_almost_eq(e2.seasons.progress(), e.seasons.progress(), 0.0001)
	assert_eq(e2.seasons.day_of_season(), e.seasons.day_of_season())
	assert_eq(e2.seasons.duration_minutes(SeasonDefs.SUMMER), 18.0, "configured duration saved")
	assert_almost_eq(e2.seasons.outdoor_temp(), e.seasons.outdoor_temp(), 0.0001)
	assert_eq(e2.con.ground_frozen, e.con.ground_frozen)
	assert_eq(e2.vs.household.heating_needed, e.vs.household.heating_needed)
	# дальше идут одинаково
	e.run(5.0)
	e2.run(5.0)
	assert_almost_eq(e2.seasons.outdoor_temp(), e.seasons.outdoor_temp(), 0.0001)
	assert_eq(e2.seasons.year(), e.seasons.year())


func test_hud_shows_season_day_and_temperature() -> void:
	assert_eq(Hud.format_season_date("Весна", 3), "Весна, день 3")
	assert_eq(Hud.format_temp(-7.6), "-8 °C")
	assert_eq(Hud.format_temp(12.2), "+12 °C")
	assert_eq(Hud.format_temp(0.3), "0 °C")
	var hud := Hud.new()
	var e := SEnv.new()
	hud.sim = e.sim
	hud._build()
	e.at(SeasonDefs.WINTER, 0.8, 7.0)
	hud.bind_seasons(e.seasons)
	assert_eq(hud.date_label.text, "Зима, день %d" % e.seasons.day_of_season())
	assert_true(hud.time_label.text.begins_with("07:00"))
	assert_true(hud.time_label.text.ends_with("°C"), hud.time_label.text)
	hud.free()


func test_day_night_lighting() -> void:
	assert_true(SeasonDefs.daylight(12.0) > 0.95, "noon is day")
	assert_true(SeasonDefs.daylight(0.0) < 0.05 and SeasonDefs.daylight(23.0) < 0.05, "night is dark")
	assert_true(SeasonDefs.daylight(7.0) > SeasonDefs.daylight(5.0), "dawn brightens")
	# реальная сцена: ночью свет и ambient слабее, но не ноль (играбельно)
	var e := SEnv.new()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	var light := DirectionalLight3D.new()
	var vis := SeasonVisuals.new()
	vis.setup(e.seasons, null, env, light)
	e.at(SeasonDefs.SUMMER, 0.5, 12.0)
	vis.apply_now()
	var day_energy := light.light_energy
	var day_amb := env.environment.ambient_light_energy
	var day_pitch := light.rotation.x
	e.at(SeasonDefs.SUMMER, 0.5, 1.0)
	vis.apply_now()
	assert_true(light.light_energy < day_energy * 0.4, "night light dimmer")
	assert_true(light.light_energy > 0.1, "but playable")
	assert_true(env.environment.ambient_light_energy < day_amb, "night ambient dimmer")
	assert_true(light.rotation.x < 0.0 and day_pitch < light.rotation.x, "sun higher at noon than moon")
	vis.free()
	light.free()
	env.free()
