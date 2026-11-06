extends "res://tests/test_case.gd"

const Env = preload("res://tests/villagers/villager_env.gd")
const SLOT := "__test_needs"


func _fresh() -> Env:
	var e := Env.new(5000, {}, 5)
	e.sim.clock.set_day_length(400.0)
	e.sim.clock.set_rate_day_length(400.0)
	e.enable_needs(10.0)
	return e


func _snap(e: Env) -> Array:
	var out := []
	for v: Villager in e.vs.villager_list():
		var nd := {}
		for n in v.needs:
			nd[n] = snappedf(v.needs[n], 0.0001)
		out.append([v.id, v.sick, v.home_id, nd, snappedf(v.sick_acc, 0.0001), v.task.get("kind", &""), snappedf(v.pos.x, 0.001)])
	var hh := []
	for id in e.vs.household.home_ids():
		var h := e.vs.household.home(id)
		hh.append([id, snappedf(h.warmth, 0.0001), snappedf(h.burn_left, 0.0001), h.stove, h.woodpile])
	return [out, hh, e.vs.outdoor_cold(), e.vs.consumption_multiplier()]


func test_save_load_mid_sickness_continues_identically() -> void:
	var e := _fresh()
	var hid := e.add_done(&"hospital", 14.0, -10.0)
	var house := e.add_done(&"dugout", 10.0, 0.0)
	e.vs.household.add_food(house, &"potato", 5)
	e.vs.household.add_water(house, 6)
	e.vs.household.home(house).stove = 3
	e.vs.set_outdoor_cold(0.6)
	e.vs.set_consumption_multiplier(1.3)
	var doc := e.add_villager(&"doctor")
	var pat := e.add_villager(&"farmer")
	e.vs.needs.assign_homes()
	pat.set_need(NeedsDefs.HEALTH, 0.45)
	e.vs.needs.fall_sick(pat)
	e.run(30.0)
	assert_true(pat.sick)
	assert_true(hid > 0 and doc != null)
	var before := _snap(e)
	assert_eq(SaveManager.save(e.sim, SLOT), OK)

	var e2 := _fresh()
	assert_eq(SaveManager.load_slot(e2.sim, SLOT), OK)
	var p2 := e2.vs.get_villager(pat.id)
	assert_true(p2 != null and p2.sick, "still sick after load")
	assert_almost_eq(p2.need(NeedsDefs.HEALTH), pat.need(NeedsDefs.HEALTH), 0.0001)
	assert_eq(p2.home_id, pat.home_id)
	assert_eq(_snap(e2), before, "needs, homes, stoves restored")
	assert_eq(e2.vs.outdoor_cold(), 0.6)
	e.run(60.0)
	e2.run(60.0)
	assert_eq(_snap(e2), _snap(e), "same continuation (incl. sickness RNG)")
	SaveManager.delete_slot(SLOT)


func test_death_is_saved_consistently() -> void:
	var e := _fresh()
	var v := e.add_villager(&"builder")
	e.vs.needs.fall_sick(v)
	v.set_need(NeedsDefs.HEALTH, 0.01)
	e.run(30.0)
	assert_true(e.vs.get_villager(v.id) == null)
	var n := e.vs.population()
	assert_eq(SaveManager.save(e.sim, SLOT), OK)
	var e2 := _fresh()
	assert_eq(SaveManager.load_slot(e2.sim, SLOT), OK)
	assert_eq(e2.vs.population(), n)
	assert_true(e2.vs.get_villager(v.id) == null, "dead stay dead")
	for o: Villager in e2.vs.villager_list():
		assert_true(o.home_id == 0 or e2.con.get_building(o.home_id) != null)
	SaveManager.delete_slot(SLOT)
