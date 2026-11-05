extends "res://tests/test_case.gd"

const Env = preload("res://tests/villagers/villager_env.gd")
const B := TaskDefs.BUILD


func _site_with_workers(e: Env, a: Villager, b: Villager = null) -> int:
	var id := e.place_near_hub(&"dugout")
	var bd := e.con.get_building(id)
	bd.stage_paid = true
	for v in [a, b]:
		if v != null:
			v.pos = bd.position
			v.task = {"kind": &"build", "cat": B, "key": "b:%d" % id, "target": id, "phase": &"", "work": 0.0, "carry": 0, "src": 0}
			v.at_site = true
	return id


func test_profession_start_level() -> void:
	var e := Env.new()
	var b := e.add_villager(&"builder")
	var c := e.add_villager(&"cook")
	assert_true(b.skill(B) > c.skill(B), "builder starts higher in build")
	assert_almost_eq(b.skill(B), SkillDefs.PROFESSION_START[&"builder"][B])
	assert_true(e.add_villager(&"mechanic").skill(TaskDefs.REPAIR) >= 0.5)
	assert_almost_eq(c.skill(TaskDefs.FELL), SkillDefs.BASE_SKILL)


func test_growth_with_work_time_and_diminishing() -> void:
	var e := Env.new()
	var v := e.add_villager(&"cook")
	var s0 := v.skill(B)
	e.vs.train(v, B, 100.0)
	var d1 := v.skill(B) - s0
	assert_true(d1 > 0.0, "grows")
	var s1 := v.skill(B)
	e.vs.train(v, B, 100.0)
	assert_true(v.skill(B) - s1 < d1, "second equal period gives less")
	assert_almost_eq(v.skill(TaskDefs.FELL), SkillDefs.BASE_SKILL)  # другая категория не растёт
	for i in 200:
		e.vs.train(v, B, 5000.0)
	assert_true(v.skill(B) <= 1.0 and v.skill(B) > 0.99, "caps at 1")


func test_growth_during_real_work_only() -> void:
	var e := Env.new(5000, {&"logs": 50, &"planks": 50, &"stone": 50})
	var h := e.hero()
	var before := h.skill(B)
	e.run(5.0)
	assert_almost_eq(h.skill(B), before, 1e-9)  # без работы навык не растёт
	var id := e.place_near_hub(&"dugout")
	assert_true(id > 0)
	e.run(60.0)
	assert_true(h.skill(B) > before, "build skill grew from building")


func test_skill_raises_work_rate() -> void:
	var e := Env.new()
	var v := e.add_villager(&"cook")
	var r0 := e.vs.work_rate(v, B)
	v.skills[B] = 1.0
	var r1 := e.vs.work_rate(v, B)
	assert_true(r1 > r0 * 1.5, "skilled much faster")
	v.skills[TaskDefs.REPAIR] = 0.0
	var a := e.vs.work_rate(v, TaskDefs.REPAIR)
	v.skills[TaskDefs.REPAIR] = 1.0
	assert_true(e.vs.work_rate(v, TaskDefs.REPAIR) > a, "repair speed too")
	assert_almost_eq(SkillDefs.rate_multiplier(0.0), SkillDefs.RATE_MULT_MIN)
	assert_almost_eq(SkillDefs.rate_multiplier(1.0), SkillDefs.RATE_MULT_MAX)


func test_trait_learning_speed() -> void:
	var e := Env.new()
	var smart := e.add_villager(&"cook", [&"clever"])
	var dull := e.add_villager(&"cook", [&"absentminded"])
	var norm := e.add_villager(&"cook")
	for v in [smart, dull, norm]:
		e.vs.train(v, B, 100.0)
	assert_true(smart.skill(B) > norm.skill(B) and norm.skill(B) > dull.skill(B))


func test_coworking_teaching_bonus() -> void:
	var e := Env.new()
	var master := e.add_villager(&"builder")
	master.skills[B] = 0.8
	var pupil := e.add_villager(&"cook")
	var loner := e.add_villager(&"cook")
	_site_with_workers(e, master, pupil)
	var base_master := master.skill(B)
	e.vs.train(pupil, B, 100.0)
	e.vs.train(loner, B, 100.0)
	var taught: float = pupil.skill(B) - SkillDefs.initial(&"cook")[B]
	var alone: float = loner.skill(B) - SkillDefs.initial(&"cook")[B]
	assert_almost_eq(taught / alone, SkillDefs.TEACH_BONUS, 1e-6)
	e.vs.train(master, B, 100.0)
	var master_gain := master.skill(B) - base_master
	assert_true(master_gain > 0.0)
	# учитель не замедлен: прирост такой же, как без ученика
	pupil.at_site = false
	var m2 := e.add_villager(&"builder")
	m2.skills[B] = 0.8
	e.vs.train(m2, B, 100.0)
	assert_almost_eq(master_gain, m2.skill(B) - 0.8, 1e-9)
	# малая разница навыков — бонуса нет
	pupil.at_site = true
	pupil.skills[B] = 0.7
	assert_almost_eq(e.vs.teach_multiplier(pupil, B), 1.0)


func test_save_load_skills() -> void:
	var e := Env.new()
	var v := e.add_villager(&"carpenter")
	e.vs.train(v, TaskDefs.FELL, 3000.0)
	var d := e.vs.save_state()
	var e2 := Env.new()
	e2.vs.load_state(JSON.parse_string(JSON.stringify(d)))
	var w := e2.vs.get_villager(v.id)
	for c in TaskDefs.WORK_CATEGORIES:
		assert_almost_eq(w.skill(c), v.skill(c), 1e-9)
	# старый формат (по профессиям) не ломает загрузку
	var old := Villager.from_dict({"id": 5, "profession": "builder", "skills": {"builder": 1.0}})
	assert_almost_eq(old.skill(B), SkillDefs.PROFESSION_START[&"builder"][B])


func test_ui_card_and_sort() -> void:
	var e := Env.new()
	var a := e.add_villager(&"builder")
	var c := e.add_villager(&"cook")
	var order := e.vs.sorted_by_skill(B)
	assert_eq(order[0].id, a.id)
	assert_true(SkillDefs.card_lines(a.skills).contains("Стройка"))
	assert_eq(SkillDefs.bar(0.5), "█████░░░░░")
	var ui := VillagersUi.new()
	ui.bind(e.vs, null)
	ui.show_panel(VillagersUi.MODE_VILLAGERS)
	ui.cycle_sort()
	assert_eq(ui.sort_cat, TaskDefs.WORK_CATEGORIES[0])
	assert_eq(ui._rows.keys()[0], e.vs.sorted_by_skill(ui.sort_cat)[0].id)
	assert_true(c != null)
	ui.free()
