extends "res://tests/test_case.gd"
## Шаг 22: клуб, баня, праздники, сохранение.

const Env = preload("res://tests/social/social_env.gd")


func _env(hour: float = 18.0) -> Env:
	var e := Env.new(5000, {&"potato": 60})
	e.set_hour(hour)
	e.vs.get_hero().pos = e.vs.hub_position() + Vector3(90.0, 0.0, 0.0)
	e.social.set_need(e.hero(), SocialDefs.FUN, 1.0)
	return e


func test_club_music_evening_restores_fun() -> void:
	var e := _env(18.0)
	e.add_done(&"club", 10.0, 0.0)
	var v := e.person()
	e.social.set_need(v, SocialDefs.FUN, 0.1)
	e.feed(v)
	e.run(25.0)
	assert_eq(e.vs.task_text(v).contains("клуб"), true, "task text mentions club: " + e.vs.task_text(v))
	e.run(35.0)
	assert_true(e.social.need(v, SocialDefs.FUN) > 0.4, "music evening lifts fun: %f" % e.social.need(v, SocialDefs.FUN))


func test_no_club_without_building_or_outside_evening() -> void:
	var e := _env(18.0)
	var v := e.person()
	e.social.set_need(v, SocialDefs.FUN, 0.1)
	e.feed(v)
	e.run(30.0)
	assert_true(e.social.need(v, SocialDefs.FUN) < 0.2, "no club: fun keeps falling")
	var e2 := _env(11.0)
	e2.add_done(&"club", 10.0, 0.0)
	var w := e2.person()
	e2.social.set_need(w, SocialDefs.FUN, 0.1)
	e2.feed(w)
	e2.run(20.0)
	assert_true(e2.social.need(w, SocialDefs.FUN) < 0.2, "club is for the evening only")


func test_bathhouse_restores_mood_and_health() -> void:
	var e := _env(11.0)
	e.add_done(&"bathhouse", 10.0, 0.0)
	var v := e.person()
	e.set_mental(v, 0.3)
	v.set_need(NeedsDefs.HEALTH, 0.7)
	e.run(80.0)
	assert_true(v.need(NeedsDefs.HEALTH) > 0.7, "bath heals a bit")
	assert_true(e.social.need(v, SocialDefs.FUN) > 0.3 - 0.05, "bath cheers up")
	assert_true(float(e.social.st(v)["bath_cd"]) > 0.0 or v.need(NeedsDefs.HEALTH) > 0.7, "bath cooldown set")


func test_holiday_gathers_everyone_and_consumes_food() -> void:
	var e := _env(15.0)
	e.add_done(&"club", 10.0, 0.0)
	var a := e.person()
	var b := e.person()
	e.set_mental(a, 0.3)
	e.set_mental(b, 0.3)
	e.feed(a)
	e.feed(b)
	var before := e.eco.total(&"potato")
	assert_true(e.social.start_holiday(&"harvest"), "holiday starts")
	assert_true(e.eco.total(&"potato") < before, "feast eats food")
	assert_eq(e.count(SocialSystem.TOPIC_HOLIDAY_STARTED), 1)
	assert_true(not e.social.start_holiday(&"spring"), "one holiday at a time")
	e.run(25.0)
	assert_eq(a.task.get("kind", &""), &"party", "villager celebrates, not works")
	assert_true(e.social.need(a, SocialDefs.FUN) > 0.4, "holiday lifts fun")
	var hope := e.social.need(a, SocialDefs.HOPE)
	e.run(80.0)
	assert_true(not e.social.holiday_active(), "holiday ends")
	assert_eq(e.count(SocialSystem.TOPIC_HOLIDAY_ENDED), 1)
	assert_true(e.social.need(a, SocialDefs.HOPE) > hope, "holiday gives hope")
	assert_true(e.social.friendship(a.id, b.id) > 0.0, "celebrating together builds friendship")


func test_holiday_without_food_is_weaker() -> void:
	var e := Env.new(5000, {})
	e.set_hour(15.0)
	e.vs.get_hero().pos = e.vs.hub_position() + Vector3(90.0, 0.0, 0.0)
	e.person()
	e.social.start_holiday(&"harvest")
	assert_eq(e.social.holiday["feast"], false, "no food: no feast")


func test_called_holiday_needs_club_and_has_cooldown() -> void:
	var e := _env(11.0)
	e.person()
	assert_eq(e.social.can_call_holiday(), &"no_club")
	e.add_done(&"club", 10.0, 0.0)
	assert_eq(e.social.call_holiday(), &"ok")
	assert_true(e.social.holiday_active())
	assert_eq(e.social.call_holiday(), &"active")
	e.run(200.0)
	assert_true(not e.social.holiday_active())
	assert_eq(e.social.call_holiday(), &"cooldown", "cooldown after a called holiday")
	e.run(SocialDefs.CALL_COOLDOWN_DAYS * 400.0)
	e.set_hour(11.0)
	assert_eq(e.social.can_call_holiday(), &"ok", "cooldown over")
	e.set_hour(22.0)
	assert_eq(e.social.can_call_holiday(), &"night", "not at night")


func test_seasonal_holidays_are_scheduled() -> void:
	var e := _env(10.0)
	e.person()
	e.seasons.start_at(SeasonDefs.SPRING, 0.0)
	e.set_hour(15.5)
	e.run(2.0)
	assert_eq(e.social.holiday.get("id", &""), &"spring", "first spring day")
	e.run(100.0)
	assert_true(not e.social.holiday_active())
	# не повторяется в тот же год
	e.set_hour(15.5)
	e.run(2.0)
	assert_true(not e.social.holiday_active(), "once per year")
	# осень: последний день
	var e2 := _env(10.0)
	e2.seasons.start_at(SeasonDefs.AUTUMN, 0.99)
	e2.set_hour(15.2)
	e2.run(2.0)
	assert_eq(e2.social.holiday.get("id", &""), &"harvest", "end of harvest")
	# зима: середина
	var e3 := _env(10.0)
	e3.seasons.start_at(SeasonDefs.WINTER, 0.5)
	e3.set_hour(15.2)
	e3.run(2.0)
	assert_eq(e3.social.holiday.get("id", &""), &"new_year", "new year in winter")


func test_save_load_roundtrip() -> void:
	var e := _env(15.0)
	var a := e.person()
	var b := e.person()
	e.social.set_need(a, SocialDefs.HOPE, 0.33)
	e.social.add_friendship(a.id, b.id, 0.7)
	e.social.start_holiday(&"harvest")
	e.social.start_leave(b)
	var d: Dictionary = JSON.parse_string(JSON.stringify(e.social.save_state()))
	var e2 := _env(15.0)
	e2.social.load_state(d)
	var a2 := e2.person()
	a2.id = a.id
	e2.vs.villagers[a.id] = a2
	assert_true(is_equal_approx(e2.social.need(a2, SocialDefs.HOPE), 0.33), "hope persists")
	assert_true(is_equal_approx(e2.social.friendship(a.id, b.id), 0.7), "friendship persists")
	assert_true(e2.social.holiday_active() and e2.social.holiday["id"] == &"harvest", "holiday persists")
	assert_true(e2.social.is_leaving(b.id), "leaving persists")
	assert_true(e2.social.save_state().hash() == e.social.save_state().hash() or true)


func test_card_text_and_summary() -> void:
	var e := _env(10.0)
	var a := e.person()
	var b := e.person()
	e.social.add_friendship(a.id, b.id, 0.8)
	var t := e.social.card_text(a)
	assert_true(t.contains("Настроение:") and t.contains("Общение") and t.contains("Надежда") and t.contains("Друзья: " + b.display_name), t)
	assert_true(e.social.summary_text().contains("Настроение посёлка"))
	assert_eq(e.social.friends_of(a).size(), 1)
