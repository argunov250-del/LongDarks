extends "res://tests/test_case.gd"

const Env = preload("res://tests/villagers/villager_env.gd")
const SLOT := "__test_household"


func test_household_round_trip_through_save_file() -> void:
	var e := Env.new(5000, {&"logs": 30, &"planks": 20, &"potato": 10}, 11)
	var house := e.add_done(&"izba", 10.0, 0.0)
	e.add_done(&"well", 30.0, 10.0)
	var canteen := e.add_done(&"canteen", 30.0, 30.0)
	e.vs.household.build_barn(house)
	e.run(150.0)
	var h := e.vs.household.home(house)
	h.food.add(&"eggs", 2)
	h.garden_state = Household.GARDEN_GROWING
	h.garden_progress = 77.0
	h.garden_crop = &"vegetables"
	e.vs.household.canteen(canteen).food.add(&"potato", 3)
	var before := e.vs.household.save_state()
	assert_true(before["homes"].size() == 1 and before["canteens"].size() == 1)
	assert_eq(SaveManager.save(e.sim, SLOT), OK)
	var e2 := Env.new(5000, {}, 11)
	assert_eq(SaveManager.load_slot(e2.sim, SLOT), OK)
	assert_eq(JSON.stringify(e2.vs.household.save_state()), JSON.stringify(before), "households round-trip")
	var h2 := e2.vs.household.home(house)
	assert_true(h2 != null and h2.barn)
	assert_eq(h2.garden_state, Household.GARDEN_GROWING)
	assert_almost_eq(h2.garden_progress, 77.0)
	assert_eq(h2.garden_crop, &"vegetables")
	assert_eq(h2.food.amount(&"eggs"), h.food.amount(&"eggs"))
	assert_eq(e2.vs.household.canteen(canteen).food.amount(&"potato"), e.vs.household.canteen(canteen).food.amount(&"potato"))
	assert_true(e2.con.get_building(house).world_parts().size() == 2, "yard restored with the house")
	# in-flight carrying survives
	e.run(30.0)
	e2.run(30.0)
	assert_eq(e2.vs.household.save_state()["homes"][0]["stove"] + e2.vs.household.save_state()["homes"][0]["woodpile"], e.vs.household.save_state()["homes"][0]["stove"] + e.vs.household.save_state()["homes"][0]["woodpile"], "same continuation")
	SaveManager.delete_slot(SLOT)


func test_bad_household_data_is_tolerated() -> void:
	var e := Env.new()
	e.vs.household.load_state({"homes": [{"id": 5, "woodpile": "x", "garden": "weird", "crop": "gold", "food": 3}, 7, {"id": 0}], "canteens": "no"})
	var h: Household = e.vs.household.homes.get(5)
	assert_true(h != null)
	assert_eq(h.garden_state, Household.GARDEN_EMPTY)
	assert_eq(h.garden_crop, &"potato")
	assert_eq(e.vs.household.homes.size(), 1)
