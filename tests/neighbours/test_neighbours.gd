extends "res://tests/test_case.gd"
## Шаг 24: соседнее поселение (design/gdd/neighbours.md).

const Env = preload("res://tests/neighbours/neighbour_env.gd")


func _env(res: Dictionary = {}) -> Env:
	var e := Env.new(5000, res)
	e.vs.get_hero().pos = e.vs.hub_position() + Vector3(90.0, 0.0, 0.0)
	e.z()["cd_visit"] = 9999.0   # визиты торговцев не мешают
	e.z()["baseline"] = 0.1
	return e


func _snapshot(e: Env) -> String:
	return str([e.z()["pop"], e.z()["level"], snappedf(float(e.z()["mood"]), 0.0001), snappedf(float(e.z()["relation"]), 0.0001), snappedf(e.nb.food_total(e.z()), 0.01)])


func test_ai_develops_deterministically_with_seed() -> void:
	var a := _env()
	var b := _env()
	a.days(60)
	b.days(60)
	assert_eq(_snapshot(a), _snapshot(b), "same seed same development")
	var start_pop := int(NeighbourDefs.START[0]["pop"])
	assert_true(int(a.z()["pop"]) != start_pop or int(a.z()["level"]) != 2 or float(a.z()["stock"][&"planks"]) != 30.0, "the settlement changed")


func test_seasons_affect_neighbour() -> void:
	var summer := _env()
	summer.nb.set_season_override(SeasonDefs.SUMMER)
	var winter := _env()
	winter.nb.set_season_override(SeasonDefs.WINTER)
	for e in [summer, winter]:
		e.z()["stock"][&"potato"] = 0.0
		e.z()["stock"][&"fish"] = 0.0
		e.days(5)
	assert_true(summer.nb.food_total(summer.z()) > winter.nb.food_total(winter.z()), "summer farms more than winter")
	assert_true(float(winter.z()["stock"][&"firewood"]) < float(summer.z()["stock"][&"firewood"]), "winter burns wood")


func test_neighbour_can_shrink_when_starving() -> void:
	var e := _env()
	e.nb.set_season_override(SeasonDefs.WINTER)
	e.z()["stock"][&"potato"] = 0.0
	e.z()["stock"][&"fish"] = 0.0
	e.z()["pop"] = 12
	for _i in 120:
		e.z()["stock"][&"potato"] = 0.0
		e.z()["stock"][&"fish"] = 0.0
		e.nb.step_days(1.0)
	assert_true(int(e.z()["pop"]) < 12, "starving settlement shrinks")


func test_relation_changes_from_actions() -> void:
	var e := _env({&"planks": 100, &"potato": 100})
	var r0 := float(e.z()["relation"])
	assert_true(e.nb.gift(&"zarechye", &"planks", 20))
	var r1 := float(e.z()["relation"])
	assert_true(r1 > r0, "gift improves")
	e.z()["request"] = {"res": &"food", "n": 10, "left": 5.0}
	assert_true(e.nb.answer_request(&"zarechye", false))
	assert_true(float(e.z()["relation"]) < r1, "refusal worsens")
	var r2 := float(e.z()["relation"])
	e.z()["request"] = {"res": &"food", "n": 10, "left": 5.0}
	assert_true(e.nb.answer_request(&"zarechye", true))
	assert_true(float(e.z()["relation"]) > r2, "help improves")
	assert_false(e.nb.gift(&"zarechye", &"planks", 9999), "cannot gift what you lack")


func test_trend_follows_relation() -> void:
	var e := _env()
	e.z()["relation"] = -0.5
	e.z()["prev"] = -0.5
	e.z()["baseline"] = 0.5
	e.days(10)
	assert_true(float(e.z()["trend"]) > 0.0, "trend up")


func test_trade_price_by_relation_and_need() -> void:
	var e := _env()
	e.z()["relation"] = -0.5
	var cold := e.nb.quote(e.z(), &"planks", 20, &"scrap_metal")
	e.z()["relation"] = 0.8
	var warm := e.nb.quote(e.z(), &"planks", 20, &"scrap_metal")
	assert_true(warm < cold, "friends charge less: %d vs %d" % [warm, cold])
	e.nb.set_season_override(SeasonDefs.WINTER)
	e.z()["stock"][&"firewood"] = 0.0
	var need_hi := e.nb.sell_price(e.z(), &"firewood")
	e.z()["stock"][&"firewood"] = 9999.0
	var need_lo := e.nb.sell_price(e.z(), &"firewood")
	assert_true(need_hi > need_lo, "they pay more for what they need")


func test_caravan_delivers_goods() -> void:
	var e := _env({&"scrap_metal": 100, &"planks": 0})
	e.nb.refresh_offers(e.z())
	var idx := -1
	for i in (e.z()["offers"] as Array).size():
		if e.z()["offers"][i]["give"] == &"planks":
			idx = i
	assert_true(idx >= 0, "has a planks offer")
	var o: Dictionary = e.z()["offers"][idx]
	if o["want"] != &"scrap_metal":
		e.eco.deposit(o["want"], 200)
	var before := e.eco.total(&"planks")
	var scrap0 := e.eco.total(o["want"])
	assert_true(e.nb.accept_offer(&"zarechye", idx))
	assert_true(e.eco.total(o["want"]) < scrap0, "paid immediately")
	assert_eq(e.nb.parties.size(), 1, "caravan on the road")
	assert_eq(e.eco.total(&"planks"), before, "not yet delivered")
	e.nb.advance_parties(100000.0)
	assert_eq(e.eco.total(&"planks"), before + int(o["give_n"]), "delivered")
	assert_eq(e.ncount(NeighbourSystem.TOPIC_CARAVAN), 1)


func test_trade_requires_payment() -> void:
	var e := _env({})
	e.nb.refresh_offers(e.z())
	assert_false(e.nb.accept_offer(&"zarechye", 0), "nothing to pay with")
	assert_eq(e.nb.parties.size(), 0)


func test_help_request_created_and_effects() -> void:
	var e := _env({&"potato": 50})
	e.nb.set_season_override(SeasonDefs.WINTER)
	e.z()["stock"][&"potato"] = 0.0
	e.z()["stock"][&"fish"] = 0.0
	e.z()["cd_request"] = 0.0
	e.nb._social_day(e.z(), 1.0)
	assert_eq(e.ncount(NeighbourSystem.TOPIC_REQUEST), 1, "asks for help")
	var stock0 := float(e.z()["stock"][&"potato"])
	assert_true(e.nb.answer_request(&"zarechye", true))
	assert_eq(e.eco.total(&"potato"), 50 - int(NeighbourDefs.REQUEST_QTY[&"food"]), "food left the player")
	e.nb.advance_parties(100000.0)
	assert_true(float(e.z()["stock"][&"potato"]) >= stock0 + 29.0, "food reached them")
	assert_true((e.z()["request"] as Dictionary).is_empty())


func test_ignored_request_expires_and_hurts() -> void:
	var e := _env()
	e.z()["request"] = {"res": &"food", "n": 10, "left": 0.5}
	var r := float(e.z()["relation"])
	e.nb._social_day(e.z(), 1.0)
	assert_true((e.z()["request"] as Dictionary).is_empty())
	assert_true(float(e.z()["relation"]) < r, "ignored")


func test_ask_neighbour_for_help() -> void:
	var e := _env()
	e.z()["relation"] = 0.3
	var got := e.nb.ask_help(&"zarechye", &"food", 20)
	assert_eq(got, 20)
	e.nb.advance_parties(100000.0)
	assert_eq(e.eco.total(&"potato"), 20)
	e.z()["relation"] = -0.6
	assert_eq(e.nb.ask_help(&"zarechye", &"food", 20), 0, "hostile neighbours refuse")


func test_leaving_villager_joins_neighbours() -> void:
	var e := _env()
	var v := e.add_villager(&"cook")
	var pop := int(e.z()["pop"])
	e.social.finish_leave(v)
	assert_eq(int(e.z()["pop"]), pop + 1)
	assert_eq(e.ncount(NeighbourSystem.TOPIC_MIGRATE), 1)
	assert_eq(e.vs.get_villager(e.vs.get_hero().id) != null, true, "hero stays")


func test_neighbour_person_joins_when_attractive() -> void:
	var e := _env()
	e.nb.attract_override = 0.1
	var pop := e.vs.population()
	for _i in 60:
		e.nb._migration_day(e.z(), 1.0)
	assert_eq(e.vs.population(), pop, "unattractive: nobody comes")
	e.nb.attract_override = 1.0
	e.z()["pop"] = 20
	for _i in 60:
		e.nb._migration_day(e.z(), 1.0)
	assert_true(e.vs.population() > pop, "attractive: they come")
	assert_true(int(e.z()["pop"]) < 20)


func _incidents(rel: float, days: int, seed_value: int = 11) -> int:
	var e := _env({&"potato": 500, &"planks": 500, &"logs": 500})
	e.nb.rng.seed = seed_value
	e.z()["relation"] = rel
	e.z()["baseline"] = rel
	e.z()["stock"][&"potato"] = 9999.0
	var c := 0
	for _i in days:
		e.nb._social_day(e.z(), 1.0)
		e.z()["pop"] = 14
	c = int(e.z()["thefts"]) + e.nb.parties.size()
	return c


func test_low_relation_means_more_thefts_and_raids() -> void:
	var bad := _incidents(-0.9, 80)
	var good := _incidents(0.5, 80)
	assert_eq(good, 0, "friends do not steal")
	assert_true(bad > 5, "enemies steal and raid often: %d" % bad)
	assert_true(_incidents(-0.3, 80) < bad, "mild tension less often")


func test_defences_reduce_raid_success() -> void:
	var e := _env({&"potato": 100})
	var p := e.nb.raid_power(e.z())
	var base := e.nb.repel_chance(p)
	for i in 4:
		e.add_done(&"fence", 10.0 + 6.0 * i, 10.0)
	var fenced := e.nb.repel_chance(p)
	e.add_done(&"watchtower", 30.0, 10.0)
	var towered := e.nb.repel_chance(p)
	var post := e.add_done(&"guard_post", 40.0, 10.0)
	assert_true(post > 0)
	for i in 6:
		e.add_villager(&"cook")
	e.vs.set_priority(TaskDefs.GUARD, 3)
	assert_true(e.nb.guards_on_duty() >= 1)
	var guarded := e.nb.repel_chance(p)
	assert_true(base == 0.0 and fenced > base and towered > fenced and guarded > towered, "%s %s %s %s" % [base, fenced, towered, guarded])
	e.vs.set_priority(TaskDefs.GUARD, 0)
	assert_eq(e.nb.guards_on_duty(), 0, "priority 0 means no guards")


func test_raid_loot_and_injuries_without_death() -> void:
	var e := _env({&"potato": 100, &"planks": 80})
	var v := e.add_villager(&"cook")
	e.feed(v)
	var pop := e.vs.population()
	e.z()["pop"] = 14
	var r := e.nb.resolve_raid(e.z())
	assert_false(r["repelled"], "no defence")
	assert_true(e.eco.total(&"potato") < 100, "goods taken")
	assert_eq(e.vs.population(), pop, "nobody dies")
	for x: Villager in e.vs.villagers.values():
		assert_true(x.need(NeedsDefs.HEALTH) >= NeighbourDefs.RAID_HURT_FLOOR - 0.0001)


func test_strong_defence_repels_raids() -> void:
	var e := _env({&"potato": 100})
	for i in 6:
		e.add_done(&"fence", 10.0 + 6.0 * i, 10.0)
	for i in 6:
		e.add_done(&"watchtower", 10.0 + 6.0 * i, 20.0)
	var wins := 0
	for _i in 40:
		if e.nb.resolve_raid(e.z())["repelled"]:
			wins += 1
	assert_true(wins > 20, "defence mostly repels: %d" % wins)


func test_negotiation_prevents_raids() -> void:
	var e := _env({&"planks": 100, &"potato": 100})
	e.z()["relation"] = 0.0
	assert_true(e.nb.propose_pact(&"zarechye"), "pact bought")
	assert_false(e.nb.propose_pact(&"zarechye"), "already active")
	e.z()["relation"] = -0.4
	e.z()["baseline"] = -0.4
	e.z()["pop"] = 14
	for _i in 15:
		e.nb._social_day(e.z(), 1.0)
		e.z()["pop"] = 14
	assert_eq(int(e.z()["thefts"]) + e.nb.parties.size(), 0, "pact stops thefts and raids")
	e.z()["relation"] = -0.9
	e.z()["baseline"] = -0.9
	e.nb._social_day(e.z(), 1.0)
	assert_eq(e.ncount(NeighbourSystem.TOPIC_PACT_BROKEN), 1, "pact breaks on hatred")


func test_tribute_reduces_hostility_and_cancels_when_unpaid() -> void:
	var e := _env({&"potato": 100})
	e.z()["relation"] = -0.5
	assert_true(e.nb.set_tribute(&"zarechye", &"potato", 10, 2.0))
	assert_eq(e.nb.tribute_factor(e.z()), NeighbourDefs.TRIBUTE_FACTOR)
	var r := float(e.z()["relation"])
	e.nb._tribute_day(e.z(), 2.0)
	assert_eq(e.eco.total(&"potato"), 90)
	assert_true(float(e.z()["relation"]) > r)
	e.eco.consume({&"potato": 90})
	e.nb._tribute_day(e.z(), 2.0)
	assert_true((e.z()["tribute"] as Dictionary).is_empty(), "unpaid tribute cancelled")


func test_save_load_roundtrip() -> void:
	var e := _env({&"scrap_metal": 100, &"planks": 50, &"potato": 50})
	e.days(7)
	e.nb.refresh_offers(e.z())
	e.nb.accept_offer(&"zarechye", 0)
	e.nb.propose_pact(&"zarechye")
	e.nb.set_tribute(&"zarechye", &"potato", 5, 3.0)
	e.z()["request"] = {"res": &"food", "n": 7, "left": 2.5}
	var data: Dictionary = JSON.parse_string(JSON.stringify(e.nb.save_state()))
	var e2 := _env()
	for r in [&"scrap_metal", &"planks", &"potato"]:
		e2.eco.deposit(r, e.eco.total(r))
	e2.nb.load_state(data)
	assert_eq(_snapshot(e2), _snapshot(e))
	assert_eq(e2.nb.parties.size(), e.nb.parties.size())
	assert_eq(e2.z()["offers"].size(), e.z()["offers"].size())
	assert_true(float(e2.z()["pact_left"]) > 0.0)
	assert_eq(int(e2.z()["tribute"]["n"]), 5)
	assert_eq(int(e2.z()["request"]["n"]), 7)
	assert_eq(e2.nb.rng.state, e.nb.rng.state)
	e.days(5)
	e2.days(5)
	assert_eq(_snapshot(e2), _snapshot(e), "continues identically")
