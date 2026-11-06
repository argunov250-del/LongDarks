extends "res://tests/test_case.gd"

const Env = preload("res://tests/villagers/villager_env.gd")


## Стенд: потребности включены, сутки 400 с (быстрее 480 с), день. Шаг 13: скорости «в сутки»
## уменьшены втрое (сутки игры 480 вместо 1440 с) — длительности тестов умножены на 3.
func _env(hour: float = 10.0, day_len: float = 400.0) -> Env:
	var e := Env.new(5000, {})
	e.sim.clock.set_day_length(day_len)
	e.enable_needs(hour)
	return e


## Житель с полными нуждами; герой отодвигается в сторону (сыт и не мешает).
func _villager(e: Env, prof: StringName = &"cook") -> Villager:
	var v := e.add_villager(prof)
	return v


func _house(e: Env, food: int = 0, water: int = 0) -> int:
	var id := e.add_done(&"dugout", 10.0, 0.0)
	if food > 0:
		e.vs.household.add_food(id, &"potato", food)
	if water > 0:
		e.vs.household.add_water(id, water)
	return id


func test_needs_decay_and_defaults() -> void:
	var e := _env()
	var v := _villager(e)
	for n in NeedsDefs.NEEDS:
		assert_eq(v.need(n), 1.0, "full at start: %s" % n)
	e.run(40.0)
	assert_true(v.need(NeedsDefs.FOOD) < 1.0 and v.need(NeedsDefs.WATER) < 1.0, "food and water decay")
	assert_true(v.need(NeedsDefs.WATER) < v.need(NeedsDefs.FOOD), "water decays faster")
	assert_true(v.need(NeedsDefs.REST) < 1.0, "tiredness grows")
	assert_true(e.vs.get_hero().need(NeedsDefs.FOOD) < 1.0, "hero has needs too")
	assert_eq(e.vs.dog.get("needs"), null, "dog has no needs")


func test_housing_capacity_by_tier_and_homeless() -> void:
	assert_true(NeedsDefs.housing_capacity(&"dugout") < NeedsDefs.housing_capacity(&"izba"))
	assert_true(NeedsDefs.housing_capacity(&"izba") < NeedsDefs.housing_capacity(&"stone_house"))
	var e := _env()
	var id := _house(e)
	for i in 3:
		_villager(e)
	e.vs.needs.assign_homes()
	assert_eq(e.vs.needs.residents(id).size(), NeedsDefs.housing_capacity(&"dugout"), "dugout full")
	assert_eq(e.vs.needs.homeless_count(), 4 - NeedsDefs.housing_capacity(&"dugout"), "rest homeless")
	var id2 := e.add_done(&"izba", 10.0, 12.0)
	e.vs.needs.assign_homes()
	assert_eq(e.vs.needs.homeless_count(), 0, "second house takes the rest")
	assert_true(e.vs.needs.residents(id2).size() >= 1)
	# жильцы сохраняют жильё
	var first := e.vs.needs.residents(id).map(func(x: Villager) -> int: return x.id)
	e.vs.needs.assign_homes()
	assert_eq(e.vs.needs.residents(id).map(func(x: Villager) -> int: return x.id), first, "stable")


func test_eat_at_home_from_house_stock() -> void:
	var e := _env()
	var id := _house(e, 6)
	e.vs.get_hero().home_id = 0
	var v := _villager(e)
	e.vs.needs.assign_homes()
	assert_eq(v.home_id, id)
	e.vs.household.home(id).food.add(&"potato", 0)
	v.set_need(NeedsDefs.FOOD, 0.2)
	e.run(40.0)
	assert_true(v.need(NeedsDefs.FOOD) >= 0.8, "ate to full: %f" % v.need(NeedsDefs.FOOD))
	assert_true(e.vs.household.home(id).food.amount(&"potato") < 6, "food taken from the house")
	assert_true(e.vs.household.home(id).food.amount(&"potato") >= 6 - 4, "only a meal")


func test_canteen_fallback_when_house_has_no_food() -> void:
	var e := _env()
	var id := _house(e, 0)
	var cid := e.add_done(&"canteen", 10.0, -14.0)
	e.vs.household.add_food(cid, &"potato", 10)
	var v := _villager(e)
	e.vs.needs.assign_homes()
	assert_eq(v.home_id, id)
	assert_false(e.vs.house_has_food(id))
	assert_eq(e.vs.canteen_for(v), cid)
	v.set_need(NeedsDefs.FOOD, 0.2)
	e.run(5.0)
	assert_eq(v.task.get("kind"), &"eat", "goes to eat")
	assert_eq(v.task.get("dest"), &"canteen")
	e.run(60.0)
	assert_true(v.need(NeedsDefs.FOOD) >= 0.8, "ate in canteen")
	assert_true(e.vs.household.canteen(cid).food.used() < 10)
	assert_eq(e.vs.household.home(id).food.used(), 0)


func test_drink_from_house_then_canteen_water() -> void:
	var e := _env()
	var id := _house(e, 0, 6)
	var v := _villager(e)
	e.vs.needs.assign_homes()
	v.set_need(NeedsDefs.WATER, 0.1)
	e.run(40.0)
	assert_true(v.need(NeedsDefs.WATER) >= 0.8, "drank at home")
	assert_true(e.vs.household.home(id).water < 6)
	# дом без воды -> столовая с водой
	e.vs.household.home(id).water = 0
	var cid := e.add_done(&"canteen", 10.0, -14.0)
	e.vs.household.add_water(cid, 10)
	v.set_need(NeedsDefs.WATER, 0.1)
	e.run(30.0)
	assert_true(v.need(NeedsDefs.WATER) >= 0.7, "drank in canteen")
	assert_true(e.vs.household.canteen(cid).water < 10)


func test_no_food_anywhere_means_hunger_not_storage_raid() -> void:
	var e := _env()
	e.storage.add(&"potato", 50)  # еда есть только на складе — есть её нельзя
	_house(e, 0)
	var v := _villager(e)
	e.vs.needs.assign_homes()
	v.set_need(NeedsDefs.FOOD, 0.4)
	e.run(150.0)
	assert_true(v.need(NeedsDefs.FOOD) < 0.25, "starving: %f" % v.need(NeedsDefs.FOOD))
	assert_eq(e.storage.amount(&"potato"), 50, "warehouse untouched by eating")
	assert_true(NeedsDefs.warnings(v.needs, v.sick).has(NeedsDefs.FOOD), "hungry warning")
	assert_true(v.need(NeedsDefs.HEALTH) <= 1.0)


func test_stove_burns_firewood_and_keeps_house_warm() -> void:
	var e := _env()
	e.vs.set_outdoor_cold(0.8)
	var id := _house(e, 4, 6)
	var h := e.vs.household.home(id)
	h.stove = 4
	var v := _villager(e)
	e.vs.needs.assign_homes()
	v.set_need(NeedsDefs.WARMTH, 0.2)
	e.run(90.0)
	assert_true(h.stove < 4, "stove burned firewood")
	assert_true(h.lit(), "stove burning")
	assert_true(h.warmth > 0.6, "house warm: %f" % h.warmth)
	e.run(90.0)
	assert_true(v.need(NeedsDefs.WARMTH) > 0.5, "villager warmed at home: %f" % v.need(NeedsDefs.WARMTH))
	assert_false(NeedsDefs.warnings(v.needs, v.sick).has(NeedsDefs.WARMTH))


func test_empty_stove_means_cold() -> void:
	var e := _env()
	e.vs.set_outdoor_cold(0.9)
	var id := _house(e, 4, 6)
	var h := e.vs.household.home(id)
	assert_eq(h.stove, 0)
	var v := _villager(e)
	e.vs.needs.assign_homes()
	e.run(200.0)
	assert_false(h.lit())
	assert_true(h.warmth < NeedsDefs.COLD_WARNING, "cold house: %f" % h.warmth)
	assert_true(v.need(NeedsDefs.WARMTH) < NeedsDefs.COLD_WARNING, "villager cold: %f" % v.need(NeedsDefs.WARMTH))
	assert_true(NeedsDefs.warnings(v.needs, v.sick).has(NeedsDefs.WARMTH), "cold warning")


func test_stove_is_stoked_by_hand_from_woodpile() -> void:
	var e := _env()
	var id := _house(e)
	var hs := e.vs.household
	var h := hs.home(id)
	var v := _villager(e)
	e.vs.needs.assign_homes()
	assert_eq(hs.stove_demand(id), hs.stove_capacity(id), "empty stove wants wood")
	h.woodpile = 8
	e.run(1.0)
	assert_eq(h.stove, 0, "not instant")
	assert_eq(h.woodpile, 8, "wood still on the pile before anyone arrives")
	var saw_carry := false
	var saw_stoke := false
	for i in 300:
		e.run(0.1)
		if v.task.get("kind", &"") == &"stoke" or e.hero().task.get("kind", &"") == &"stoke":
			saw_stoke = true
			for w in [v, e.hero()]:
				if w.task.get("kind", &"") == &"stoke" and w.task.get("phase", &"") == &"deliver":
					saw_carry = true
					assert_eq(VillagerAnim.state_of(w)["load"], VillagerAnim.LOAD_FIREWOOD, "armful visible")
					assert_true(w.task["carry"] > 0 and w.task["carry"] <= TaskDefs.CARRY_CAPACITY)
					assert_eq(h.stove, 0, "stove empty while the armful is in hands")
	assert_true(saw_stoke and saw_carry, "villager walked, took an armful and carried it")
	assert_true(h.stove > 0 or h.lit(), "stove loaded after arrival")
	assert_true(h.woodpile < 8)
	hs.outdoor_cold = 0.0
	assert_eq(hs.stove_demand(id), 0, "no heat needed when warm outside")


func test_empty_woodpile_does_not_refill_stove() -> void:
	var e := _env()
	var id := _house(e)
	var h := e.vs.household.home(id)
	_villager(e)
	e.vs.needs.assign_homes()
	assert_eq(h.woodpile, 0)
	e.run(40.0)
	assert_eq(h.stove, 0)
	assert_false(h.lit())
	assert_false(e.vs.needs.stoke_wanted(id))


func test_sleep_at_night_restores_rest() -> void:
	var e := _env(23.0)
	var id := _house(e, 4, 6)
	var v := _villager(e)
	e.vs.needs.assign_homes()
	v.set_need(NeedsDefs.REST, 0.2)
	e.run(15.0)
	assert_eq(v.task.get("kind"), &"sleep", "goes to bed at night")
	e.run(45.0)
	assert_true(v.need(NeedsDefs.REST) > 0.45, "rested: %f" % v.need(NeedsDefs.REST))
	assert_true(NeedsDefs.is_night(23.0) and not NeedsDefs.is_night(12.0))
	# утром встаёт и работает/свободен
	e.set_hour(7.0)
	v.set_need(NeedsDefs.REST, 0.95)
	e.run(5.0)
	assert_true(v.task.get("kind", &"") != &"sleep", "up in the morning")


func test_homeless_sleep_is_worse_and_tiredness_grows_while_working() -> void:
	var e := _env(23.0)
	var housed := _villager(e)
	var id := _house(e, 4, 6)
	e.vs.needs.assign_homes()
	assert_eq(housed.home_id, id)
	var e2 := _env(23.0)
	var homeless := _villager(e2)
	housed.set_need(NeedsDefs.REST, 0.2)
	homeless.set_need(NeedsDefs.REST, 0.2)
	e.run(60.0)
	e2.run(60.0)
	assert_true(housed.need(NeedsDefs.REST) > homeless.need(NeedsDefs.REST) + 0.05, "homeless rests worse")
	assert_true(homeless.need(NeedsDefs.REST) > 0.2, "still rests a little")
	assert_eq(homeless.task.get("target"), 0, "sleeps under the open sky")
	# усталость на работе
	var e3 := Env.new(5000, {&"logs": 40, &"planks": 40, &"stone": 40})
	e3.sim.clock.set_day_length(400.0)
	e3.enable_needs(9.0)
	var b := e3.place_near_hub(&"dugout", 8.0, 0.0)
	var w := e3.hero()
	e3.run(40.0)
	assert_true(w.need(NeedsDefs.REST) < 0.95, "tired from work: %f" % w.need(NeedsDefs.REST))
	assert_true(b > 0)


func test_low_needs_lower_work_rate() -> void:
	var e := _env()
	var v := _villager(e, &"builder")
	var full := e.vs.work_rate(v, TaskDefs.BUILD)
	assert_true(full > 0.0)
	v.set_need(NeedsDefs.FOOD, 0.1)
	var hungry := e.vs.work_rate(v, TaskDefs.BUILD)
	assert_true(hungry < full, "hungry works slower")
	v.set_need(NeedsDefs.REST, 0.0)
	v.set_need(NeedsDefs.WATER, 0.0)
	v.set_need(NeedsDefs.WARMTH, 0.0)
	v.set_need(NeedsDefs.FOOD, 0.0)
	var worst := e.vs.work_rate(v, TaskDefs.BUILD)
	assert_true(worst < hungry)
	assert_true(worst >= full * NeedsDefs.MIN_NEEDS_RATE - 0.0001, "floor")
	v.needs = NeedsDefs.full()
	v.set_need(NeedsDefs.HEALTH, 0.2)
	assert_true(e.vs.work_rate(v, TaskDefs.BUILD) < full, "poor health slows")
	v.needs = NeedsDefs.full()
	assert_almost_eq(e.vs.work_rate(v, TaskDefs.BUILD), full, 0.00001)
	e.vs.needs_enabled = false
	v.set_need(NeedsDefs.FOOD, 0.0)
	assert_almost_eq(e.vs.work_rate(v, TaskDefs.BUILD), full, 0.00001, "needs off: no penalty")


func test_sick_villager_stops_working_and_goes_to_hospital_with_doctor() -> void:
	var e := _env()
	var hid := e.add_done(&"hospital", 14.0, -10.0)
	_house(e, 4, 6)
	var doc := _villager(e, &"doctor")
	var pat := _villager(e, &"builder")
	e.vs.needs.assign_homes()
	var events := []
	e.sim.bus.subscribe(VillagerSystem.TOPIC_SICK, func(p): events.append(["sick", p["id"]]))
	e.sim.bus.subscribe(VillagerSystem.TOPIC_RECOVERED, func(p): events.append(["ok", p["id"]]))
	pat.set_need(NeedsDefs.HEALTH, 0.4)
	e.vs.needs.fall_sick(pat)
	assert_true(pat.sick)
	assert_eq(events, [["sick", pat.id]], "sickness event")
	e.run(15.0)
	assert_eq(pat.task.get("kind"), &"heal", "patient goes to the hospital")
	assert_eq(pat.task.get("target"), hid)
	assert_eq(doc.task.get("kind"), &"treat", "doctor treats")
	assert_true(e.vs.get_hero().task.get("kind", &"") != &"treat", "hero does not take the doctor's job")
	e.run(390.0)
	assert_false(pat.sick, "healed")
	assert_true(pat.need(NeedsDefs.HEALTH) >= NeedsDefs.RECOVER_HEALTH)
	assert_true(events.has(["ok", pat.id]), "recovery event")


func test_sick_without_treatment_loses_health_and_dies() -> void:
	var e := _env()
	var hid := _house(e, 4, 6)
	var v := _villager(e, &"builder")
	e.vs.needs.assign_homes()
	var deaths := []
	e.sim.bus.subscribe(VillagerSystem.TOPIC_DIED, func(p): deaths.append(p))
	v.set_need(NeedsDefs.HEALTH, 0.15)
	e.vs.needs.fall_sick(v)
	e.run(20.0)
	assert_true(v.task.get("kind", &"") != &"build", "sick villager does not work")
	var h1 := v.need(NeedsDefs.HEALTH)
	e.run(120.0)
	assert_true(v.need(NeedsDefs.HEALTH) < h1, "health keeps dropping")
	e.run(450.0)
	assert_true(e.vs.get_villager(v.id) == null, "dead and gone")
	assert_eq(deaths.size(), 1, "death event once")
	assert_eq(deaths[0]["id"], v.id)
	assert_eq(deaths[0]["cause"], &"sickness")
	assert_false(e.vs.needs.residents(hid).any(func(x: Villager) -> bool: return x.id == v.id), "home freed")
	assert_true(e.vs.get_hero() != null)


func test_starvation_kills_and_frees_home() -> void:
	var e := _env()
	e.vs.household.heating_needed = false
	var id := _house(e, 0, 0)
	var v := _villager(e)
	e.vs.needs.assign_homes()
	assert_eq(v.home_id, id)
	v.needs[NeedsDefs.FOOD] = 0.0
	v.needs[NeedsDefs.WATER] = 0.0
	v.set_need(NeedsDefs.HEALTH, 0.4)
	var died := []
	e.sim.bus.subscribe(VillagerSystem.TOPIC_DIED, func(p): died.append(p["cause"]))
	e.run(750.0)
	assert_true(e.vs.get_villager(v.id) == null, "died of thirst/hunger")
	assert_eq(died.size(), 1)
	assert_true(died[0] == &"water" or died[0] == &"food" or died[0] == &"sickness")
	assert_true(e.vs.get_hero() != null, "hero survives the same conditions")


func test_hero_never_dies() -> void:
	var e := _env()
	var hero := e.vs.get_hero()
	hero.needs[NeedsDefs.FOOD] = 0.0
	hero.needs[NeedsDefs.WATER] = 0.0
	hero.set_need(NeedsDefs.HEALTH, 0.02)
	e.vs.needs.fall_sick(hero)
	e.run(300.0)
	assert_true(e.vs.get_villager(hero.id) != null)
	assert_true(hero.need(NeedsDefs.HEALTH) >= NeedsDefs.HERO_HEALTH_FLOOR - 0.0001)
	assert_false(e.vs.kill_villager(hero.id, &"test"))
	assert_false(e.vs.remove_villager(hero.id))


func test_outdoor_cold_and_consumption_hooks() -> void:
	assert_almost_eq(NeedsDefs.cold_factor(&"food", NeedsDefs.MILD_COLD), 1.0)
	assert_true(NeedsDefs.cold_factor(&"food", 1.0) > 1.0)
	assert_true(NeedsDefs.cold_factor(&"fuel", 1.0) > NeedsDefs.cold_factor(&"food", 1.0))
	var a := _env()
	var b := _env()
	b.vs.set_consumption_multiplier(2.0)
	assert_eq(b.vs.consumption_multiplier(), 2.0)
	var va := _villager(a)
	var vb := _villager(b)
	a.run(30.0)
	b.run(30.0)
	var da := 1.0 - va.need(NeedsDefs.WATER)
	var db := 1.0 - vb.need(NeedsDefs.WATER)
	assert_true(db > da * 1.8 and db < da * 2.2, "multiplier doubles consumption: %f vs %f" % [da, db])
	# мороз: больше еды и дров
	var c := _env()
	c.vs.set_outdoor_cold(1.0)
	assert_eq(c.vs.outdoor_cold(), 1.0)
	c.vs.set_outdoor_cold(5.0)
	assert_eq(c.vs.outdoor_cold(), 1.0, "clamped")
	var vc := _villager(c)
	c.run(30.0)
	assert_true(1.0 - vc.need(NeedsDefs.FOOD) > 1.0 - va.need(NeedsDefs.FOOD), "winter: more food needed")
	assert_true(c.vs.household.fuel_per_day() > a.vs.household.fuel_per_day(), "winter: more fuel")
	assert_true(NeedsDefs.outdoor_warmth(1.0) < NeedsDefs.outdoor_warmth(0.0))
	assert_true(a.vs.suffering(va) < 0.01)
	va.needs = {NeedsDefs.FOOD: 0.0, NeedsDefs.WATER: 0.0, NeedsDefs.WARMTH: 0.0, NeedsDefs.REST: 0.0, NeedsDefs.HEALTH: 0.1}
	assert_true(a.vs.suffering(va) > 0.8, "suffering hook")


func test_newcomer_starts_partly_tired_and_gets_home_later() -> void:
	var e := _env()
	var id := _house(e)
	var n := e.vs.spawn_newcomer()
	assert_eq(n.need(NeedsDefs.REST), NeedsDefs.NEWCOMER_START[NeedsDefs.REST])
	assert_eq(n.home_id, 0, "no home while walking in")
	e.run(60.0)
	assert_false(n.arriving)
	e.vs.needs.assign_homes()
	assert_eq(n.home_id, id)
