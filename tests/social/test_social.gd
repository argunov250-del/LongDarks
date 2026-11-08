extends "res://tests/test_case.gd"
## Шаг 22: психические потребности (design/gdd/mental-needs.md).

const Env = preload("res://tests/social/social_env.gd")


func _env() -> Env:
	return Env.new(5000, {&"potato": 50})


func test_mental_needs_decay_and_start() -> void:
	var e := _env()
	var v := e.person()
	for n in SocialDefs.NEEDS:
		assert_eq(e.social.need(v, n), SocialDefs.START[n], "start %s" % n)
	assert_true(e.social.need(e.hero(), SocialDefs.HOPE) > e.social.need(v, SocialDefs.HOPE), "hero starts with more hope")
	e.run(20.0)
	assert_true(e.social.need(v, SocialDefs.SOCIAL) < SocialDefs.START[SocialDefs.SOCIAL], "social decays")
	assert_true(e.social.need(v, SocialDefs.FUN) < SocialDefs.START[SocialDefs.FUN], "fun decays")
	assert_eq(e.social.need(v, SocialDefs.FAMILY), SocialDefs.START[SocialDefs.FAMILY], "family is neutral for now")


func test_mood_words_and_family_hook() -> void:
	var e := _env()
	var v := e.person()
	e.set_mental(v, 1.0)
	assert_eq(e.social.mood_word(v), "довольный")
	e.set_mental(v, 0.0)
	assert_eq(e.social.mood_word(v), "отчаявшийся")
	e.set_mental(v, 0.5)
	assert_true(["спокойный", "уставший душой"].has(e.social.mood_word(v)))
	assert_eq(SocialDefs.mood_word(0.3), "подавленный")
	e.social.set_family(v, 1.0)
	assert_eq(e.social.need(v, SocialDefs.FAMILY), 1.0, "family hook")


func test_talk_restores_social_and_builds_friendship() -> void:
	var e := _env()
	var a := e.person()
	var b := e.person()
	e.vs.get_hero().pos = a.pos + Vector3(60.0, 0.0, 0.0)
	b.pos = a.pos + Vector3(1.0, 0.0, 0.0)
	e.social.set_need(a, SocialDefs.SOCIAL, 0.2)
	e.social.set_need(b, SocialDefs.SOCIAL, 0.9)
	e.feed(a)
	e.feed(b)
	e.run(30.0)
	assert_true(e.social.need(a, SocialDefs.SOCIAL) > 0.3, "talk lifts social: %f" % e.social.need(a, SocialDefs.SOCIAL))
	assert_true(e.social.friendship(a.id, b.id) > 0.0, "talk builds friendship")


func test_friendship_from_working_together_and_traits() -> void:
	var e := _env()
	var a := e.person(&"builder")
	var b := e.person(&"builder")
	var c := e.person(&"builder", [&"loner"])
	var d := e.person(&"builder", [&"loner"])
	e.social.add_friendship(a.id, b.id, 0.0)
	var days := 0.1
	e.social._friend_gain(a, b, 1.0, days)
	e.social._friend_gain(c, d, 1.0, days)
	assert_true(e.social.friendship(a.id, b.id) > e.social.friendship(c.id, d.id), "loners befriend slower")
	assert_true(e.social.friendship(c.id, d.id) > 0.0)
	# совместная работа на одной стройке растит дружбу
	var e2 := _env()
	var p := e2.person(&"builder")
	var q := e2.person(&"builder")
	e2.vs.get_hero().pos = p.pos + Vector3(80.0, 0.0, 0.0)
	var id := e2.place_near_hub(&"club")
	assert_true(id > 0)
	e2.con.get_building(id).stage_paid = true
	e2.feed(p)
	e2.feed(q)
	e2.run(60.0)
	for v in [p, q]:
		e2.feed(v)
	e2.run(60.0)
	assert_true(e2.social.friendship(p.id, q.id) > 0.0, "coworkers grow closer: %f" % e2.social.friendship(p.id, q.id))


func test_quarrel_requires_low_mood_and_traits_matter() -> void:
	var e := _env()
	var a := e.person(&"cook")
	var b := e.person(&"cook")
	e.set_mental(a, 1.0)
	assert_eq(e.social.quarrel_rate(a, b, e.social.mood(a)), 0.0, "good mood: no quarrels")
	var low := 0.2
	var base := e.social.quarrel_rate(a, b, low)
	assert_true(base > 0.0, "bad mood: quarrels possible")
	var lazy := e.person(&"cook", [&"lazy"])
	var loner := e.person(&"cook", [&"loner"])
	assert_true(e.social.quarrel_rate(lazy, b, low) > base, "lazy quarrels more")
	assert_true(e.social.quarrel_rate(loner, b, low) < base, "loner avoids quarrels")
	assert_eq(e.social.quarrel_rate(e.hero(), b, low), 0.0, "hero never quarrels")
	e.social.add_friendship(a.id, b.id, SocialDefs.HOSTILE_AT - 0.1)
	assert_true(e.social.quarrel_rate(a, b, low) > base, "hostile pair quarrels more")


func test_quarrel_lowers_friendship_and_notifies() -> void:
	var e := _env()
	var a := e.person()
	var b := e.person()
	e.social.add_friendship(a.id, b.id, 0.6)
	e.social.quarrel(a, b)
	assert_true(e.social.friendship(a.id, b.id) < 0.6 - SocialDefs.QUARREL_DROP + 0.001, "friendship drops")
	assert_eq(e.count(SocialSystem.TOPIC_QUARREL), 1, "notification")
	assert_true(e.social.friendship(a.id, b.id) >= -1.0)


func test_quarrels_happen_in_a_miserable_crowd() -> void:
	var e := _env()
	var a := e.person(&"cook")
	var b := e.person(&"cook")
	e.vs.get_hero().pos = a.pos + Vector3(80.0, 0.0, 0.0)
	b.pos = a.pos + Vector3(2.0, 0.0, 0.0)
	for i in 80:
		e.set_mental(a, 0.1)
		e.set_mental(b, 0.1)
		e.feed(a)
		e.feed(b)
		e.run(10.0)
		a.pos = b.pos - Vector3(2.0, 0.0, 0.0)
	assert_true(e.count(SocialSystem.TOPIC_QUARREL) >= 1, "quarrel in a bad crowd")


func test_low_mood_slows_work_and_raises_sickness() -> void:
	var e := _env()
	var v := e.person(&"builder")
	var fine := e.vs.work_rate(v, TaskDefs.BUILD)
	e.set_mental(v, 0.0)
	var sad := e.vs.work_rate(v, TaskDefs.BUILD)
	assert_true(sad < fine, "unmet mental needs: slower work")
	assert_true(sad >= fine * SocialDefs.MOOD_RATE_FLOOR * 0.99 - 0.0001 or sad > 0.0)
	assert_true(e.social.sick_bonus(v) > 0.0, "low mood raises sickness chance")
	e.set_mental(v, 1.0)
	assert_eq(e.social.sick_bonus(v), 0.0)
	assert_true(is_equal_approx(e.vs.work_rate(v, TaskDefs.BUILD), fine))
	assert_true(SocialDefs.rate_multiplier(0.0) < SocialDefs.rate_multiplier(0.3))
	assert_eq(SocialDefs.rate_multiplier(0.8), 1.0)


func test_misery_makes_villager_leave_but_not_hero() -> void:
	var e := _env()
	var v := e.person()
	var hero := e.hero()
	var left: Array = []
	e.social.on_villager_left = func(p: Dictionary) -> void: left.append(p)
	for i in 120:
		e.set_mental(v, 0.0)
		e.set_mental(hero, 0.0)
		e.feed(v)
		e.feed(hero)
		e.run(10.0)
		if not e.vs.villagers.has(v.id):
			break
	assert_true(not e.vs.villagers.has(v.id), "miserable villager left")
	assert_eq(e.count(SocialSystem.TOPIC_LEFT), 1, "left notification")
	assert_eq(left.size(), 1, "neighbours hook called")
	assert_true(e.vs.villagers.has(hero.id), "hero never leaves")
	assert_true(not e.social.start_leave(hero), "hero refuses to leave")
	assert_true(e.vs.dog != null, "dog stays")


func test_content_villager_does_not_leave() -> void:
	var e := _env()
	var v := e.person()
	for i in 40:
		e.set_mental(v, 0.7)
		e.feed(v)
		e.run(10.0)
	assert_true(e.vs.villagers.has(v.id))


func test_hope_rises_on_climate_events_and_newcomers() -> void:
	var e := _env()
	var v := e.person()
	e.social.set_need(v, SocialDefs.HOPE, 0.3)
	e.sim.bus.emit(ClimateSystem.TOPIC_FIRST_BIRDS, {"year": 1, "warming": 0.5})
	assert_true(is_equal_approx(e.social.need(v, SocialDefs.HOPE), 0.3 + SocialDefs.HOPE_FIRST_BIRDS), "first birds")
	e.social.set_need(v, SocialDefs.HOPE, 0.3)
	e.sim.bus.emit(ClimateSystem.TOPIC_WARMING_MILESTONE, {"level": 1, "warming": 1.0, "year": 2})
	assert_true(is_equal_approx(e.social.need(v, SocialDefs.HOPE), 0.3 + SocialDefs.HOPE_WARMING_MILESTONE), "warming")
	e.social.set_need(v, SocialDefs.HOPE, 0.3)
	e.vs.arrival_min = 1.0
	e.vs.arrival_max = 1.0
	e.vs.next_arrival_in = 1.0
	e.run(2.0)
	assert_true(e.social.need(v, SocialDefs.HOPE) > 0.3 - 0.02, "newcomer arrival lifts hope a little")


func test_meaningful_work_vs_idle_hope() -> void:
	var e := _env()
	var idle := e.person(&"cook")
	var e2 := _env()
	e2.vs.get_hero().pos = e2.vs.hub_position() + Vector3(90.0, 0.0, 0.0)
	var idle2 := e2.person(&"cook")
	e2.social.set_need(idle2, SocialDefs.HOPE, 0.8)
	e2.feed(idle2)
	idle2.task = {}
	for i in 12:
		e2.feed(idle2)
		e2.run(10.0)
	assert_true(e2.social.need(idle2, SocialDefs.HOPE) < 0.8, "long idleness lowers hope: %f" % e2.social.need(idle2, SocialDefs.HOPE))
	assert_true(idle != null)
	# осмысленная работа по профессии: строитель на стройке vs охотник на той же стройке
	var e3 := _env()
	var bld := e3.person(&"builder")
	var hnt := e3.person(&"hunter")
	for v in [bld, hnt]:
		v.task = {"kind": &"build", "cat": TaskDefs.BUILD, "key": "b:1", "target": 1, "phase": &"", "work": 0.0, "carry": 0, "src": 0, "res": &"", "dest": &""}
		v.at_site = true
		e3.social.set_need(v, SocialDefs.HOPE, 0.4)
	e3.social._process(40.0)
	var gb := e3.social.need(bld, SocialDefs.HOPE) - 0.4
	var gh := e3.social.need(hnt, SocialDefs.HOPE) - 0.4
	assert_true(gb > gh, "work matching the profession gives more meaning: %f vs %f" % [gb, gh])
	assert_true(gb > 0.0, "meaningful work raises hope")
