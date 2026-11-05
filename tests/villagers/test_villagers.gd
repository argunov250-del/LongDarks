extends "res://tests/test_case.gd"

const Env = preload("res://tests/villagers/villager_env.gd")


func _snapshot(vs: VillagerSystem) -> Array:
	var out := []
	for v: Villager in vs.villager_list():
		out.append([v.id, v.display_name, v.profession, v.traits.duplicate(), v.age, v.backstory, v.sex])
	return out


func test_start_is_hero_and_dog_only() -> void:
	var e := Env.new()
	assert_eq(e.vs.population(), 1)
	var h := e.hero()
	assert_true(h != null and h.is_hero, "hero exists")
	assert_eq(h.sex, &"m")
	assert_true(h.immortal)
	assert_true(e.vs.dog != null and e.vs.dog.immortal, "dog exists")
	assert_true(e.vs.pathfinder.is_walkable(h.pos))


func test_villager_generation_rules() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var seen_prof := {}
	for i in 200:
		var v := Villager.generate(rng)
		seen_prof[v.profession] = true
		assert_true(v.traits.size() >= 1 and v.traits.size() <= 3, "1-3 traits")
		assert_true(v.skills.has(v.profession), "skill field")
		assert_true(v.backstory != "" and not v.backstory.contains("{"), "backstory rendered: " + v.backstory)
		assert_true(v.display_name.split(" ").size() == 2)
		for a in v.traits:
			assert_true(TraitDefs.exists(a))
			for b in v.traits:
				assert_false(TraitDefs.are_exclusive(a, b), "exclusive pair")
		assert_eq(v.traits.size(), v.traits.duplicate().filter(func(x): return v.traits.count(x) == 1).size(), "no duplicates")
	assert_eq(seen_prof.size(), 9, "all nine professions appear")
	assert_eq(VillagerDefs.PROFESSIONS.size(), 9)


func test_trait_table_is_valid() -> void:
	var good := 0
	var bad := 0
	for t in TraitDefs.ids():
		if TraitDefs.is_good(t):
			good += 1
		else:
			bad += 1
		for c in TraitDefs.modifiers(t):
			assert_true(TaskDefs.WORK_CATEGORIES.has(c), "known category in " + String(t))
	assert_true(good >= 5 and bad >= 5)
	assert_true(TraitDefs.rate_multiplier([&"strong"], TaskDefs.BUILD) > 1.0)
	assert_true(TraitDefs.rate_multiplier([&"lazy"], TaskDefs.BUILD) < 1.0)
	assert_true(TraitDefs.rate_multiplier([&"clumsy"], TaskDefs.REPAIR) < 1.0)
	assert_almost_eq(TraitDefs.rate_multiplier([&"clumsy"], TaskDefs.BUILD), 1.0)
	assert_true(TraitDefs.rate_multiplier([&"lazy", &"weak", &"loner"], TaskDefs.BUILD) >= TaskDefs.MIN_RATE_MULT)


func test_gendered_text() -> void:
	assert_eq(VillagerDefs.gendered("{Был|Была} тут. Знал{а}.", &"m"), "Был тут. Знал.")
	assert_eq(VillagerDefs.gendered("{Был|Была} тут. Знал{а}.", &"f"), "Была тут. Знала.")
	assert_eq(VillagerDefs.age_text(21), "21 год")
	assert_eq(VillagerDefs.age_text(34), "34 года")
	assert_eq(VillagerDefs.age_text(45), "45 лет")
	assert_eq(VillagerDefs.age_text(12), "12 лет")


func test_arrivals_are_deterministic_and_capped() -> void:
	var runs := []
	var events: Array = []
	for r in 2:
		var e := Env.new(5000, {}, 31)
		e.vs.arrival_min = 20.0
		e.vs.arrival_max = 40.0
		e.vs.next_arrival_in = 25.0
		if r == 0:
			e.sim.bus.subscribe(VillagerSystem.TOPIC_ARRIVED, func(p): events.append(p["name"]))
		e.run(300.0)
		runs.append(_snapshot(e.vs))
	assert_true((runs[0] as Array).size() > 3, "newcomers arrived")
	assert_eq(runs[0], runs[1], "same seed -> same newcomers")
	assert_eq(events.size(), (runs[0] as Array).size() - 1, "notification per newcomer")
	# Лимит
	var e2 := Env.new()
	e2.vs.arrival_min = 1.0
	e2.vs.arrival_max = 2.0
	e2.vs.next_arrival_in = 1.0
	e2.run(200.0)
	assert_true(e2.vs.population() > 1)
	for i in 80:
		e2.vs.spawn_newcomer()
	assert_eq(e2.vs.population(), VillagerDefs.MAX_POPULATION)
	assert_eq(VillagerDefs.MAX_POPULATION, 40)
	e2.run(60.0)
	assert_eq(e2.vs.population(), VillagerDefs.MAX_POPULATION, "cap holds while timer fires")


func test_newcomer_walks_in_from_edge_to_hub() -> void:
	var e := Env.new()
	var v := e.vs.spawn_newcomer()
	var c := e.world.cell_of(v.pos.x, v.pos.z)
	var n := e.world.size
	assert_true(c.x <= 0 or c.y <= 0 or c.x >= n - 1 or c.y >= n - 1, "spawned on map edge")
	assert_true(v.arriving)
	e.run(240.0)
	assert_false(v.arriving, "reached the village")
	assert_true(Vector2(v.pos.x - e.vs.hub_position().x, v.pos.z - e.vs.hub_position().z).length() <= TaskDefs.ARRIVE_RADIUS_HUB + 0.5)


func test_priority_zero_never_assigns() -> void:
	var e := Env.new(5000, {&"logs": 50, &"planks": 50, &"stone": 50})
	var id := e.place_near_hub(&"dugout")
	var b := e.con.get_building(id)
	e.vs.set_priority(TaskDefs.BUILD, 0)
	e.vs.set_priority(TaskDefs.CHORES, 0)
	e.run(60.0)
	assert_eq(b.progress, 0.0, "no work at priority 0")
	assert_true(e.hero().task.is_empty(), "hero idle")
	e.vs.set_priority(TaskDefs.BUILD, 2)
	e.run(30.0)
	assert_true(b.progress > 0.0 or b.stage > 0, "works once enabled")
	assert_eq(e.hero().task.get("cat"), TaskDefs.BUILD)
	# Приоритет 0 посреди работы снимает задачу.
	e.vs.set_priority(TaskDefs.BUILD, 0)
	e.run(2.0)
	assert_true(e.hero().task.is_empty())
	# Клампится в 0..3
	e.vs.set_priority(TaskDefs.BUILD, 9)
	assert_eq(e.vs.get_priority(TaskDefs.BUILD), 3)
	e.vs.change_priority(TaskDefs.BUILD, -10)
	assert_eq(e.vs.get_priority(TaskDefs.BUILD), 0)


func test_building_priority_overrides_category() -> void:
	var e := Env.new(5000, {&"logs": 50, &"planks": 50, &"stone": 50})
	var id := e.place_near_hub(&"dugout")
	e.vs.set_building_priority(id, 0)
	e.run(30.0)
	assert_eq(e.con.get_building(id).progress, 0.0)
	e.vs.set_building_priority(id, -1)
	e.run(30.0)
	assert_true(e.con.get_building(id).stage > 0 or e.con.get_building(id).progress > 0.0)


func test_higher_priority_wins() -> void:
	var e := Env.new(5000, {&"logs": 50, &"planks": 50, &"stone": 50, &"scrap_metal": 40})
	var site := e.place_near_hub(&"dugout")
	var mill := e.add_done(&"sawmill", -14.0, 0.0)
	e.run(0.2)
	var h := e.hero()
	e.vs.set_priority(TaskDefs.BUILD, 3)
	e.vs.set_priority(TaskDefs.PRODUCTION, 1)
	assert_eq(e.vs.best_job_for(h)["cat"], TaskDefs.BUILD)
	e.vs.set_priority(TaskDefs.BUILD, 1)
	e.vs.set_priority(TaskDefs.PRODUCTION, 3)
	assert_eq(e.vs.best_job_for(h)["cat"], TaskDefs.PRODUCTION)
	assert_true(site > 0 and mill > 0)


func test_suitability_affects_choice() -> void:
	var e := Env.new(5000, {&"logs": 50, &"scrap_metal": 40})
	var hub := e.vs.hub_position()
	var mill := e.add_done(&"sawmill", 0.0, 0.0)
	var shop := e.add_done(&"workshop", 0.0, 0.0)
	# Оба здания на одинаковом расстоянии от точки, где стоят жители.
	e.con.get_building(mill).position = hub + Vector3(-16, 0, 0)
	e.con.get_building(shop).position = hub + Vector3(16, 0, 0)
	e.vs.remove_villager(2)
	var carp := e.add_villager(&"carpenter")
	var mech := e.add_villager(&"mechanic")
	var cook := e.add_villager(&"cook")
	for v in [carp, mech, cook]:
		v.pos = hub
	e.run(0.5)
	assert_eq(e.vs.best_job_for(carp)["target"], mill, "carpenter -> sawmill")
	assert_eq(e.vs.best_job_for(mech)["target"], shop, "mechanic -> workshop")
	# Черты тоже влияют на скорость
	assert_true(e.vs.work_rate(carp, TaskDefs.PRODUCTION, &"sawmill") > e.vs.work_rate(cook, TaskDefs.PRODUCTION, &"sawmill"))


func test_suitability_affects_speed() -> void:
	var e := Env.new()
	var builder := e.add_villager(&"builder", [&"strong"])
	var lazy_cook := e.add_villager(&"cook", [&"lazy"])
	var plain := e.add_villager(&"cook")
	var rb := e.vs.work_rate(builder, TaskDefs.BUILD)
	var rp := e.vs.work_rate(plain, TaskDefs.BUILD)
	var rl := e.vs.work_rate(lazy_cook, TaskDefs.BUILD)
	assert_almost_eq(rp, BuildingDefs.BUILD_RATE)
	assert_true(rb > rp * 1.5, "builder+strong much faster")
	assert_true(rl < rp, "lazy slower")
	var clumsy_mech := e.add_villager(&"mechanic", [&"clumsy"])
	var careful_mech := e.add_villager(&"mechanic", [&"careful"])
	assert_true(e.vs.work_rate(careful_mech, TaskDefs.REPAIR) > e.vs.work_rate(clumsy_mech, TaskDefs.REPAIR))
	assert_true(e.vs.work_rate(clumsy_mech, TaskDefs.REPAIR) > 0.0)


func test_construction_progresses_only_with_villager_on_site() -> void:
	var e := Env.new(5000, {&"logs": 50, &"planks": 50, &"stone": 50})
	var id := e.place_near_hub(&"dugout", 40.0, 0.0)
	var b := e.con.get_building(id)
	var h := e.hero()
	# Без работников стадия оплачена, но работа не идёт.
	e.vs.set_priority(TaskDefs.BUILD, 0)
	e.vs.set_priority(TaskDefs.CHORES, 0)
	e.run(20.0)
	assert_true(b.stage_paid)
	assert_eq(b.progress, 0.0)
	# Включаем: пока герой идёт — прогресса нет.
	e.vs.set_priority(TaskDefs.BUILD, 2)
	e.run(3.0)
	var dist := Vector2(h.pos.x - b.position.x, h.pos.z - b.position.z).length()
	assert_true(dist > 3.0, "still walking")
	assert_eq(b.progress, 0.0, "no progress while walking")
	assert_eq(b.stage, 0)
	e.run(60.0)
	assert_true(b.is_done() or b.stage > 0 or b.progress > 0.0, "progress after arrival")
	# Герой вынужденно уведён — работа замирает.
	var before := b.progress + b.stage * 1000.0
	if not b.is_done():
		h.pos = e.vs.hub_position() + Vector3(-60, 0, 0)
		h.pos = e.vs.pathfinder.nearest_walkable(h.pos)
		h.path.clear()
		e.vs.set_priority(TaskDefs.BUILD, 0)
		e.run(5.0)
		assert_eq(b.progress + b.stage * 1000.0, before, "no progress when away")


func test_builder_finishes_house_faster_than_non_builder() -> void:
	var times := []
	for prof in [&"builder", &"cook"]:
		var e := Env.new(5000, {&"logs": 50, &"planks": 50, &"stone": 50})
		e.vs.remove_villager(999)
		var id := e.place_near_hub(&"dugout", 8.0, 0.0)
		var hero := e.hero()
		hero.traits.clear()
		hero.profession = prof
		var t := 0.0
		while not e.con.get_building(id).is_done() and t < 600.0:
			e.run(1.0)
			t += 1.0
		times.append(t)
	assert_true(times[0] < times[1], "builder faster: %s" % str(times))
	assert_true(times[0] < 600.0)


func test_idle_villager_does_chores_logs_to_firewood_to_house() -> void:
	var e := Env.new(5000, {&"logs": 40})
	var house := e.add_done(&"dugout", 10.0, 0.0)
	assert_eq(e.vs.firewood_capacity(house), BuildingDefs.firewood_capacity(&"dugout"))
	assert_eq(e.vs.firewood_stock(house), 0)
	e.run(300.0)
	assert_true(e.vs.firewood_stock(house) > 0, "firewood carried into house")
	assert_eq(e.vs.firewood_stock(house), e.vs.firewood_capacity(house), "house filled")
	assert_true(e.eco.total(&"logs") < 40, "logs were chopped")
	assert_true(e.eco.total(&"logs") >= TaskDefs.CHORE_LOGS_RESERVE, "reserve respected")
	# Дрова сохраняются: 2 на бревно
	var chopped := 40 - e.eco.total(&"logs")
	assert_eq(e.eco.total(&"firewood") + e.vs.firewood_stock(house), chopped * TaskDefs.FIREWOOD_PER_LOG)


func test_chores_can_be_disabled_or_prioritized() -> void:
	var e := Env.new(5000, {&"logs": 40})
	e.add_done(&"dugout", 10.0, 0.0)
	e.vs.set_priority(TaskDefs.CHORES, 0)
	e.run(60.0)
	assert_eq(e.eco.total(&"logs"), 40)
	e.vs.set_priority(TaskDefs.CHORES, 3)
	e.run(60.0)
	assert_true(e.eco.total(&"logs") < 40)


func test_real_work_beats_chores() -> void:
	var e := Env.new(5000, {&"logs": 40, &"planks": 50, &"stone": 50})
	e.add_done(&"dugout", 10.0, 0.0)
	e.run(20.0)
	e.place_near_hub(&"izba", 16.0, 10.0)
	e.run(5.0)
	assert_eq(e.hero().task.get("cat"), TaskDefs.BUILD, "left chores for construction")


func test_felling_needs_villager_and_gives_logs() -> void:
	var e := Env.new(5000, {})
	var cell := Vector2i(-1, -1)
	var hub := e.world.cell_of(e.vs.hub_position().x, e.vs.hub_position().z)
	for cz in range(hub.y - 30, hub.y + 30):
		for cx in range(hub.x - 30, hub.x + 30):
			if cell.x < 0 and e.world.cell_type(cx, cz) == WorldMap.Terrain.FOREST and e.eco.deposits.remaining(Vector2i(cx, cz)) > 0:
				cell = Vector2i(cx, cz)
	assert_true(cell.x >= 0)
	e.vs.set_priority(TaskDefs.FELL, 0)
	e.con.start_felling([cell])
	e.run(30.0)
	assert_eq(e.eco.total(&"logs"), 0, "nobody felled at priority 0")
	e.vs.set_priority(TaskDefs.FELL, 2)
	e.run(120.0)
	assert_true(e.eco.total(&"logs") > 0, "felled by villager")


func test_dismantle_by_villager() -> void:
	var e := Env.new(5000, {})
	var rid: int = e.con.active_ruin_ids()[0]
	e.con.start_dismantle(rid)
	e.vs.set_priority(TaskDefs.DISMANTLE, 0)
	e.run(30.0)
	assert_true(e.con.is_ruin_active(rid))
	e.vs.set_priority(TaskDefs.DISMANTLE, 2)
	e.run(200.0)
	assert_false(e.con.is_ruin_active(rid), "ruin dismantled by hero")


func test_production_needs_worker_slot() -> void:
	var e := Env.new(5000, {&"logs": 40})
	var mill := e.add_done(&"sawmill", 10.0, 0.0)
	e.vs.set_priority(TaskDefs.PRODUCTION, 0)
	e.vs.set_priority(TaskDefs.CHORES, 0)
	e.run(60.0)
	assert_eq(e.eco.total(&"planks"), 0, "no worker -> no planks")
	e.vs.set_priority(TaskDefs.PRODUCTION, 2)
	e.run(120.0)
	assert_true(e.eco.total(&"planks") > 0, "worker produces")
	assert_true(mill > 0)
	# Один слот: второй работник идёт заниматься другим
	var second := e.add_villager(&"cook")
	e.run(5.0)
	var on_mill := 0
	for v: Villager in e.vs.villager_list():
		if v.task.get("kind") == &"produce":
			on_mill += 1
	assert_true(on_mill <= 1, "one slot")
	assert_true(second != null)


func test_hero_and_dog_not_removable() -> void:
	var e := Env.new()
	var h := e.hero()
	assert_false(e.vs.remove_villager(h.id))
	assert_eq(e.vs.population(), 1)
	assert_false(h.can_die())
	var n := e.add_villager(&"cook")
	assert_true(n.can_die())
	assert_true(e.vs.remove_villager(n.id))
	assert_true(e.vs.dog.immortal)
	assert_eq(e.vs.get_hero(), h)


func test_dog_follows_hero_and_anxiety_hook() -> void:
	var e := Env.new(5000, {&"logs": 50, &"planks": 50, &"stone": 50})
	e.place_near_hub(&"dugout", 40.0, 0.0)
	e.run(60.0)
	var h := e.hero()
	var d := Vector2(h.pos.x - e.vs.dog.pos.x, h.pos.z - e.vs.dog.pos.z).length()
	assert_true(d < 8.0, "dog stays near hero, dist %f" % d)
	e.vs.dog.set_anxious(2.0)
	assert_eq(e.vs.dog.anxious_level, 1.0)
	e.vs.dog.set_anxious(-1.0)
	assert_eq(e.vs.dog.anxious_level, 0.0)
	# Далеко -> догоняет
	e.vs.dog.pos = e.vs.pathfinder.nearest_walkable(h.pos + Vector3(30, 0, 0))
	e.run(30.0)
	d = Vector2(h.pos.x - e.vs.dog.pos.x, h.pos.z - e.vs.dog.pos.z).length()
	assert_true(d < 8.0, "dog caught up")


func test_unreachable_target_is_banned_not_stuck() -> void:
	var e := Env.new(5000, {&"logs": 50, &"planks": 50, &"stone": 50})
	var id := e.place_near_hub(&"dugout")
	e.run(0.3)
	e.vs.assign_now(e.hero())
	assert_eq(e.hero().task.get("key"), "b:%d" % id)
	e.hero().banned["b:%d" % id] = e.vs._time + 100.0
	e.vs.assign_now(e.hero())
	assert_ne_task(e.hero(), "b:%d" % id)


func assert_ne_task(v: Villager, key: String) -> void:
	assert_true(v.task.get("key", "") != key, "banned key avoided")
