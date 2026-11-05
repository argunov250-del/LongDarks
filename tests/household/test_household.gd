extends "res://tests/test_case.gd"

const Env = preload("res://tests/villagers/villager_env.gd")


func _house_env(res: Dictionary = {}) -> Array:
	var e := Env.new(5000, res)
	var id := e.add_done(&"dugout", 10.0, 0.0)
	return [e, id]


func test_housing_has_yard_stove_woodpile_garden() -> void:
	for t in [&"dugout", &"izba", &"stone_house"]:
		var kinds := []
		for p in BuildingDefs.parts(t):
			kinds.append(p["kind"])
		assert_eq(kinds, [&"body", &"yard"], "yard is part of footprint: %s" % t)
		assert_true(BuildingDefs.stove_capacity(t) > 0, "stove in house")
		assert_true(BuildingDefs.firewood_capacity(t) > 0, "woodpile capacity")
	assert_eq(BuildingDefs.parts(&"sawmill").size(), 1, "non-housing has no yard")
	var r := _house_env()
	var e: Env = r[0]
	var h := e.vs.household.home(r[1])
	assert_true(h != null, "household stock created")
	assert_eq(h.garden_state, Household.GARDEN_EMPTY)
	assert_eq(h.woodpile, 0)
	assert_eq(h.stove, 0)
	assert_true(e.vs.household.stove_capacity(r[1]) > 0)
	assert_true(e.vs.household.woodpile_capacity(r[1]) > 0)


func test_yard_moves_and_rotates_with_house() -> void:
	var w := BuildingDefs.world_parts(&"izba", Vector2(100, 100), 0.0)
	assert_eq(w[1]["kind"], &"yard")
	assert_almost_eq(w[1]["c"].x, 100.0)
	assert_almost_eq(w[1]["c"].y, 100.0 + BuildingDefs.YARD_OFFSET.y)
	var w2 := BuildingDefs.world_parts(&"izba", Vector2(100, 100), PI * 0.5)
	assert_almost_eq(w2[1]["c"].x, 100.0 + BuildingDefs.YARD_OFFSET.y, 0.001, "rotated 90 deg")
	assert_almost_eq(w2[1]["c"].y, 100.0, 0.001)


func test_yard_blocks_overlap_and_is_kept_on_upgrade() -> void:
	var r := _house_env({&"logs": 20, &"planks": 20, &"stone": 20})
	var e: Env = r[0]
	var b := e.con.get_building(r[1])
	var yard_c: Vector2 = b.world_parts()[1]["c"]
	var at := Vector3(yard_c.x, b.position.y, yard_c.y)
	assert_false(e.con.validate_placement(&"warehouse", at, 0.0)["ok"], "yard blocks other buildings")
	assert_eq(e.con.validate_placement(&"warehouse", at, 0.0)["reason"], &"overlap")
	assert_true(e.con.validate_placement(&"well", at, 0.0)["ok"], "well may stand in a yard")
	assert_eq(e.con.building_at(at, 0.0), b, "tapping the yard selects the house")
	var h := e.vs.household.home(r[1])
	h.woodpile = 5
	h.barn = true
	assert_true(e.con.upgrade(r[1]))
	assert_eq(b.type, &"izba")
	var w2 := b.world_parts()
	assert_almost_eq((w2[1]["c"] as Vector2).distance_to(yard_c), 0.0, 0.001, "yard unchanged by upgrade")
	assert_false(e.con.validate_placement(&"warehouse", at, 0.0)["ok"], "yard still blocks")
	e.run(1.0)
	assert_eq(e.vs.household.home(r[1]), h, "same stock record")
	assert_eq(h.woodpile, 5)
	assert_true(h.barn)


func test_garden_yields_into_house_stock() -> void:
	var r := _house_env()
	var e: Env = r[0]
	var h := e.vs.household.home(r[1])
	e.run(40.0)
	assert_eq(h.garden_state, Household.GARDEN_GROWING, "villager planted the garden")
	h.garden_progress = HouseholdDefs.GARDEN_GROW_TIME - 1.0
	e.run(30.0)
	assert_true(h.garden_state != Household.GARDEN_GROWING or h.food.used() > 0)
	e.run(60.0)
	var crop_first: StringName = &"potato"
	assert_eq(h.food.amount(crop_first), HouseholdDefs.GARDEN_YIELD, "potato harvested into the HOUSE stock")
	assert_eq(e.eco.total(&"potato"), 0, "not into the warehouse")
	assert_true(e.vs.house_has_food(r[1]))
	# следующий цикл — овощи
	var seen_vegetables := false
	for i in 4:
		h.garden_progress = HouseholdDefs.GARDEN_GROW_TIME if h.garden_state == Household.GARDEN_GROWING else h.garden_progress
		e.run(50.0)
		if h.food.amount(&"vegetables") > 0:
			seen_vegetables = true
	assert_true(seen_vegetables, "crops alternate: vegetables too")


func test_garden_season_hook_exists() -> void:
	assert_true(HouseholdDefs.garden_season_allows(1, &"plant"))
	assert_true(HouseholdDefs.garden_season_allows(100, &"harvest"))


func test_barn_gives_eggs_and_milk() -> void:
	var r := _house_env({&"logs": 20, &"planks": 20})
	var e: Env = r[0]
	var hs := e.vs.household
	var h := hs.home(r[1])
	assert_true(hs.can_build_barn(r[1]))
	assert_true(hs.build_barn(r[1]))
	assert_true(h.barn)
	assert_eq(e.eco.total(&"planks"), 20 - HouseholdDefs.BARN_COST[&"planks"], "cost paid")
	assert_eq(e.eco.total(&"logs"), 20 - HouseholdDefs.BARN_COST[&"logs"])
	assert_false(hs.build_barn(r[1]), "only one barn")
	e.vs.set_priority(TaskDefs.CHORES, 0)
	e.run(HouseholdDefs.MILK_PERIOD + 5.0)
	assert_true(h.food.amount(&"eggs") >= 1, "eggs")
	assert_true(h.food.amount(&"milk") >= 1, "milk")
	assert_eq(e.eco.total(&"eggs"), 0, "into house stock, not warehouse")
	var poor := _house_env({})
	assert_false(poor[0].vs.household.can_build_barn(poor[1]), "needs resources")


func test_water_only_from_well_carried_in_buckets() -> void:
	var r := _house_env()
	var e: Env = r[0]
	var h := e.vs.household.home(r[1])
	assert_eq(e.eco.deposit(&"water", 10), 0, "water is not warehouse stock")
	e.run(80.0)
	assert_eq(h.water, 0, "no well, no water")
	var well := e.add_done(&"well", 30.0, 10.0)
	assert_eq(e.vs.household.nearest_well(e.hero().pos), well)
	var steps := []
	var last := 0
	var saw_buckets := false
	var max_carry := 0
	for i in 1200:
		e.sim.advance(0.1)
		if h.water != last:
			steps.append(h.water - last)
			last = h.water
		var v := e.hero()
		if v.task.get("kind", &"") == &"water":
			max_carry = maxi(max_carry, int(v.task.get("carry", 0)))
			if VillagerAnim.load_of(v.task) == VillagerAnim.LOAD_BUCKETS:
				saw_buckets = true
	assert_true(h.water > 0, "villager hauled water from the well")
	assert_eq(h.water, h.water_cap, "house water filled")
	for s in steps:
		assert_true(s > 0 and s <= HouseholdDefs.WATER_CARRY, "delivered per bucket load: %d" % s)
	assert_true(steps.size() >= 2, "several trips")
	assert_true(max_carry <= HouseholdDefs.WATER_CARRY and max_carry > 0)
	assert_true(saw_buckets, "buckets visible")


func test_firewood_chop_stack_when_no_heat_demand_else_stove() -> void:
	# нет спроса на тепло -> всё на поленницу
	var r := _house_env({&"logs": 40})
	var e: Env = r[0]
	e.vs.household.heating_needed = false
	var h := e.vs.household.home(r[1])
	var poses := {}
	for i in 3000:
		e.sim.advance(0.1)
		var st := VillagerAnim.state_of(e.hero(), e.vs)
		poses[st["pose"]] = true
		if st["pose"] == VillagerAnim.POSE_STACK and st["load"] == VillagerAnim.LOAD_FIREWOOD:
			poses[&"stack_firewood"] = true
	assert_eq(h.woodpile, e.vs.household.woodpile_capacity(r[1]), "woodpile full")
	assert_eq(h.stove, 0, "no heat demand -> stove untouched")
	assert_true(poses.has(VillagerAnim.POSE_CHOP), "axe chop seen")
	assert_true(poses.has(&"stack_firewood"), "stacking armful seen")
	assert_true(poses.has(VillagerAnim.POSE_WALK))
	# спрос на тепло -> в печь
	var r2 := _house_env({&"logs": 40})
	var e2: Env = r2[0]
	e2.vs.household.heating_needed = true
	var h2 := e2.vs.household.home(r2[1])
	var first_dest := &""
	for i in 1500:
		e2.sim.advance(0.1)
		var t := e2.hero().task
		if first_dest == &"" and t.get("phase", &"") == &"deliver" and t.get("res", &"") == &"firewood":
			first_dest = t["dest"]
	assert_eq(first_dest, &"stove", "armful goes to the stove first")
	assert_eq(h2.stove, e2.vs.household.stove_capacity(r2[1]), "stove filled to capacity")
	assert_eq(h2.woodpile, e2.vs.household.woodpile_capacity(r2[1]), "rest stacked on woodpile")
	assert_eq(e2.vs.household.stove_demand(r2[1]), 0, "satisfied")
	# conservation: бревна -> дрова
	var chopped := 40 - e2.eco.total(&"logs")
	assert_eq(h2.stove + h2.woodpile + e2.eco.total(&"firewood"), chopped * TaskDefs.FIREWOOD_PER_LOG)


func test_canteen_stock_and_api() -> void:
	var e := Env.new(5000, {&"potato": 30, &"grain": 10})
	var house := e.add_done(&"dugout", 10.0, 0.0)
	var well := e.add_done(&"well", 30.0, 10.0)
	var canteen := e.add_done(&"canteen", 30.0, 30.0)
	assert_true(BuildingDefs.is_canteen(&"canteen"))
	assert_eq(BuildingDefs.tab_of(&"canteen"), BuildingDefs.Tab.SOCIAL)
	assert_eq(BuildingDefs.tab_of(&"well"), BuildingDefs.Tab.PRODUCTION)
	var c := e.vs.household.canteen(canteen)
	assert_true(c != null and c.kind == &"canteen")
	assert_eq(e.vs.canteen_for(e.hero()), -1, "empty canteen is not offered")
	assert_false(e.vs.house_has_food(house), "no food in the house yet")
	e.vs.set_priority(TaskDefs.CHORES, 3)
	e.run(200.0)
	assert_true(c.food.used() > 0, "food carried to the canteen")
	assert_true(c.water > 0, "water carried to the canteen from the well")
	assert_true(e.eco.total(&"potato") + e.eco.total(&"grain") < 40, "taken from storage")
	assert_eq(e.vs.canteen_for(e.hero()), canteen)
	assert_true(e.vs.household.nearest_well(Vector3.ZERO) == well)
	# повар предпочтительнее
	var cook := e.add_villager(&"cook")
	var other := e.add_villager(&"builder")
	assert_true(e.vs.suitability(cook, TaskDefs.CHORES, &"canteen") > e.vs.suitability(other, TaskDefs.CHORES, &"canteen"))
	# еда в доме
	e.vs.household.home(house).food.add(&"potato", 2)
	assert_true(e.vs.house_has_food(house))


func test_carry_capacity_is_constant() -> void:
	var e := Env.new(5000, {&"firewood": 100})
	var house := e.add_done(&"izba", 10.0, 0.0)
	e.vs.household.heating_needed = false
	var worst := 0
	for i in 1500:
		e.sim.advance(0.1)
		worst = maxi(worst, int(e.hero().task.get("carry", 0)))
	assert_true(worst > 0 and worst <= TaskDefs.CARRY_CAPACITY, "armful <= capacity: %d" % worst)
	assert_eq(e.vs.firewood_stock(house), e.vs.firewood_capacity(house))
