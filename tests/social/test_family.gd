extends "res://tests/test_case.gd"
## Шаг 23: семьи и дети (design/gdd/families.md).

const Env = preload("res://tests/social/family_env.gd")


func _env() -> Env:
	var e := Env.new(5000, {&"potato": 60})
	e.vs.get_hero().pos = e.vs.hub_position() + Vector3(90.0, 0.0, 0.0)
	return e


func test_couple_forms_only_under_conditions() -> void:
	var e := _env()
	e.house()
	var m := e.adult(&"m")
	var f := e.adult(&"f")
	e.family.roll_pass()
	assert_eq(e.family.partner_id(m.id), 0, "not friends yet")
	e.social.add_friendship(m.id, f.id, 0.9)
	for i in 100:
		e.family.roll_pass()
	assert_eq(e.family.partner_id(m.id), f.id, "close friends become a couple")
	assert_eq(e.fcount(FamilySystem.TOPIC_WEDDING), 1)
	var a := e.adult(&"m")
	var b := e.adult(&"m")
	e.social.add_friendship(a.id, b.id, 0.9)
	assert_false(e.family.can_pair(a, b), "same sex")
	var kid := e.adult(&"f")
	e.family._parents[kid.id] = [0, a.id]
	e.social.add_friendship(a.id, kid.id, 0.9)
	assert_false(e.family.can_pair(a, kid), "relatives")


func test_couple_moves_in_together() -> void:
	var e := _env()
	var h1 := e.house(10.0)
	var h2 := e.house(30.0)
	var m := e.adult(&"m")
	var f := e.adult(&"f")
	m.home_id = h1
	f.home_id = h2
	e.family.marry(m, f)
	assert_eq(m.home_id, f.home_id, "same house")
	assert_true(m.home_id > 0)


func test_pregnancy_birth_requires_housing() -> void:
	var e := _env()
	var c := e.couple(e.add_done(&"dugout", 10.0, 0.0))  # вдвоём заполняют землянку (2 места)
	assert_false(e.family.conceive(c[0], c[1]), "no room in the house")
	var e2 := _env()
	var c2 := e2.couple(e2.house())
	assert_true(e2.family.conceive(c2[0], c2[1]))
	assert_true(e2.family.is_pregnant(c2[0].id))
	e2.family.step_pass(e2.family._day_seconds() * 2.1)
	assert_eq(e2.fcount(FamilySystem.TOPIC_BORN), 1, "baby born")
	var kids := e2.family.children_of(c2[0].id)
	assert_eq(kids.size(), 1)
	assert_eq(kids[0].stage, FamilyDefs.INFANT)
	assert_eq(kids[0].home_id, c2[0].home_id)


func test_births_stop_at_population_cap() -> void:
	var e := _env()
	var c := e.couple(e.house())
	e.vs.max_population = e.vs.population()
	assert_false(e.family.conceive(c[0], c[1]), "cap reached")
	e.vs.max_population += 1
	assert_true(e.family.conceive(c[0], c[1]))
	e.vs.max_population = e.vs.population()
	e.family.step_pass(e.family._day_seconds() * 3.0)
	assert_eq(e.vs.population(), e.vs.max_population, "birth waits for room")


func test_child_grows_and_becomes_worker() -> void:
	var e := _env()
	var c := e.couple(e.house())
	e.family.conceive(c[0], c[1])
	e.family.step_pass(e.family._day_seconds() * 2.1)
	var kid: Villager = e.family.children_of(c[0].id)[0]
	var day := e.family._day_seconds()
	var stages := {}
	for i in 19:
		e.family.step_pass(day)
		kid.pos = c[0].pos
		stages[kid.stage] = true
	assert_true(stages.has(FamilyDefs.CHILD) and stages.has(FamilyDefs.TEEN), "passed stages")
	assert_eq(kid.stage, FamilyDefs.ADULT)
	assert_eq(kid.age, 18)
	assert_eq(e.fcount(FamilySystem.TOPIC_GREW), 1)
	assert_true(e.vs.family.work_multiplier(kid) > 0.9, "works as adult")


func test_minors_do_not_work_teens_do_chores() -> void:
	var e := _env()
	var kid := e.adult(&"m")
	kid.stage = FamilyDefs.CHILD
	assert_false(e.family.may_work(kid, {"tcat": TaskDefs.CHORES}))
	kid.stage = FamilyDefs.TEEN
	assert_true(e.family.may_work(kid, {"tcat": TaskDefs.CHORES}))
	assert_false(e.family.may_work(kid, {"tcat": TaskDefs.BUILD}))
	assert_eq(e.family.work_multiplier(kid), FamilyDefs.TEEN_WORK_MULT)


func test_school_raises_adult_skills() -> void:
	var e := _env()
	var a := e.family.adult_skills(&"builder", 0.0)
	var b := e.family.adult_skills(&"builder", FamilyDefs.SCHOOL_FULL_DAYS)
	for c in TaskDefs.WORK_CATEGORIES:
		assert_true(b[c] > a[c], "school raises " + String(c))
	e.add_done(&"school", 10.0, 0.0)
	e.set_hour(10.0)
	var kid := e.adult(&"m")
	kid.stage = FamilyDefs.CHILD
	assert_eq(e.family.job_for(kid, &"")["kind"], &"school")
	e.set_hour(20.0)
	assert_eq(e.family.job_for(kid, &"")["kind"], &"play")


func test_trait_inheritance_from_parents() -> void:
	var e := _env()
	var c := e.couple(e.house())
	c[0].traits.assign([&"strong", &"clever"])
	c[1].traits.assign([&"hardy"])
	var all := {}
	for i in 30:
		for t in e.family._inherit_traits([c[0], c[1]] as Array[Villager], [&"lazy"] as Array[StringName]):
			all[t] = true
	assert_true(all.has(&"strong") or all.has(&"clever") or all.has(&"hardy"), "inherits parent traits")
	assert_false(e.family._inherit_traits([c[0], c[1]], [&"lazy"] as Array[StringName]).is_empty())


func test_family_need_and_grief() -> void:
	var e := _env()
	var c := e.couple(e.house())
	var single := e.adult(&"f")
	assert_true(e.family.family_need_of(c[0].id) > e.family.family_need_of(single.id), "partner satisfies")
	e.vs.kill_villager(c[1].id, &"sickness")
	assert_eq(e.family.partner_id(c[0].id), 0)
	assert_true(e.family.grief(c[0]) > 0.9)
	assert_true(e.family.family_need_of(c[0].id) < 0.4, "loss lowers need")
	e.set_mental(c[0], 0.7)
	var m_grief := e.social.mood(c[0])
	e.family._grief.clear()
	assert_true(m_grief < e.social.mood(c[0]) - 0.3, "grief hits mood strongly")
	assert_false(e.family.can_pair(c[0], e.adult(&"m")) , "no friendship")


func test_aging_slows_elderly_and_hero_immortal() -> void:
	var e := _env()
	assert_true(FamilyDefs.elder_multiplier(75) < FamilyDefs.elder_multiplier(40))
	var old := e.adult(&"m", &"cook", 90)
	e.vs.needs_enabled = true
	assert_true(e.vs.needs_multiplier(old) < e.vs.needs_multiplier(e.adult(&"m")), "elderly slower")
	var hero := e.hero()
	hero.age = 95
	for i in 200:
		e.family.step_pass(e.family._day_seconds())
	assert_true(e.vs.villagers.has(hero.id), "hero never dies")
	assert_false(e.vs.villagers.has(old.id), "old villager died naturally")
	assert_true(e.fcount(VillagerSystem.TOPIC_DIED) >= 1)


func test_save_load_mid_pregnancy() -> void:
	var e := _env()
	var c := e.couple(e.house())
	e.family.conceive(c[0], c[1])
	e.family.add_grief(c[1].id, 0.5)
	var d := e.family.save_state()
	var e2 := _env()
	e2.family.load_state(JSON.parse_string(JSON.stringify(d)))
	assert_true(e2.family.is_pregnant(c[0].id))
	assert_eq(e2.family.partner_id(c[0].id), c[1].id)
	assert_true(absf(e2.family._grief[c[1].id] - 0.5) < 0.01)
	var v := Villager.from_dict(JSON.parse_string(JSON.stringify(c[0].to_dict())))
	assert_eq(v.stage, FamilyDefs.ADULT)
