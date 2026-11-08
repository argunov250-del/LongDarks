extends "res://tests/test_case.gd"
## Шаг 26: каркас карьеры (design/gdd/career.md). Данные, условия, порядок глав, титры, сохранение.

const Env = preload("res://tests/neighbours/neighbour_env.gd")


func _data(chapters: Array) -> Dictionary:
	return CareerDefs.parse({"chapters": chapters, "credits": {"entries": [{"role": "r", "name": "n"}]}})


func _ch(id: String, objs: Array, intro := "i", outro := "o") -> Dictionary:
	return {"id": id, "title": id, "intro": intro, "outro": outro, "objectives": objs}


func _obj(id: String, type: String, params: Dictionary) -> Dictionary:
	return {"id": id, "type": type, "text": id, "params": params}


func _career(chapters: Array, e = null) -> CareerSystem:
	var c := CareerSystem.new(_data(chapters))
	if e != null:
		e.sim.register_system(c)
		c.attach(e.sim)
		c.bind(e.vs, e.seasons, e.eco, e.nb)
	return c


func test_default_data_loads_four_chapters() -> void:
	var d := CareerDefs.load_file()
	assert_eq(d["errors"].size(), 0, str(d["errors"]))
	assert_eq(d["chapters"].size(), 4)
	assert_true(d["credits"]["entries"].size() > 0)


func test_bad_data_reported_not_crash() -> void:
	assert_true(CareerDefs.parse(null)["errors"].size() > 0)
	assert_true(CareerDefs.parse({"chapters": 5})["errors"].size() > 0)
	var d := _data([_ch("a", [_obj("x", "nope", {}), _obj("y", "population", {})]), "junk",
		_ch("b", [_obj("z", "population", {"count": 2})]), _ch("b", [_obj("z2", "population", {"count": 2})])])
	assert_eq(d["chapters"].size(), 1, "only valid chapter b kept")
	assert_true(d["errors"].size() >= 4, str(d["errors"]))
	assert_true(CareerDefs.load_file("res://nope.json")["errors"].size() > 0)
	var c := CareerSystem.new(CareerDefs.parse(null))
	c.start_new()
	assert_false(c.active, "no chapters -> inactive, no crash")


func test_population_and_resource_poll() -> void:
	var e := Env.new(5000, {&"logs": 3})
	var c := _career([_ch("a", [_obj("p", "population", {"count": 2}), _obj("r", "resource", {"resource": "logs", "count": 5})], "", "")], e)
	c.start_new()
	assert_eq(c.phase, CareerSystem.ACTIVE)
	e.add_villager(&"cook")
	c.evaluate()
	assert_true(c.done.has("p"), "population >= 2")
	assert_false(c.done.has("r"))
	e.eco.deposit(&"logs", 5)
	c.evaluate()
	assert_eq(c.phase, CareerSystem.CREDITS, "single chapter without texts -> credits")


func test_survive_and_relation() -> void:
	var e := Env.new()
	e.seasons.start_at(SeasonDefs.AUTUMN, 0.5)
	var c := _career([_ch("a", [_obj("s", "survive_until", {"season": "winter", "year": 1}), _obj("n", "relation", {"min": 0.6})], "", "")], e)
	c.start_new()
	c.evaluate()
	assert_false(c.done.has("s"))
	e.seasons.start_at(SeasonDefs.WINTER, 0.1)
	e.nb.neighbours[0]["relation"] = 0.7
	c.evaluate()
	assert_true(c.done.has("s") and c.done.has("n"))


func test_event_conditions() -> void:
	var e := Env.new()
	var c := _career([_ch("a", [
		_obj("b", "build", {"building": "well", "count": 2}),
		_obj("h", "harvest", {"resource": "grain", "count": 10}),
		_obj("r", "repair", {"count": 1}),
		_obj("ev", "event", {"topic": "first_birds", "count": 1})], "", "")], e)
	c.start_new()
	e.sim.bus.emit(ConstructionSystem.TOPIC_COMPLETED, {"id": 1, "type": &"well"})
	e.sim.bus.emit(ConstructionSystem.TOPIC_COMPLETED, {"id": 2, "type": &"izba"})
	assert_false(c.done.has("b"), "other type ignored")
	e.sim.bus.emit(ConstructionSystem.TOPIC_COMPLETED, {"id": 3, "type": &"well"})
	assert_true(c.done.has("b"))
	e.sim.bus.emit(FoodSystem.TOPIC_HARVESTED, {"res": &"potato", "n": 50})
	assert_false(c.done.has("h"), "wrong resource")
	e.sim.bus.emit(FoodSystem.TOPIC_HARVESTED, {"res": &"grain", "n": 6})
	e.sim.bus.emit(FoodSystem.TOPIC_HARVESTED, {"res": &"grain", "n": 6})
	assert_true(c.done.has("h"))
	e.sim.bus.emit(ProductionSystem.TOPIC_REPAIR_DONE, {"id": 1, "target": &"v1"})
	assert_true(c.done.has("r"))
	e.sim.bus.emit(&"first_birds", {})
	assert_true(c.done.has("ev"), "custom topic")


func test_chapter_order_and_credits() -> void:
	var e := Env.new()
	var chs: Array = []
	for i in 4:
		chs.append(_ch("c%d" % i, [_obj("o%d" % i, "event", {"topic": "go", "count": 1})]))
	var c := _career(chs, e)
	var seen: Array = []
	e.sim.bus.subscribe(CareerSystem.TOPIC_CHAPTER_STARTED, func(p: Dictionary) -> void: seen.append(p["id"]))
	var credits := []
	e.sim.bus.subscribe(CareerSystem.TOPIC_CREDITS, func(_p: Dictionary) -> void: credits.append(1))
	c.start_new()
	assert_eq(c.phase, CareerSystem.INTRO)
	assert_true(e.sim.clock.is_paused(), "panel pauses")
	e.sim.bus.emit(&"go", {})
	assert_false(c.done.has("o0"), "events ignored during intro")
	c.acknowledge()
	assert_false(e.sim.clock.is_paused(), "resumed")
	for i in 4:
		e.sim.bus.emit(&"go", {})
		assert_eq(c.phase, CareerSystem.OUTRO)
		assert_eq(c.chapter, i)
		c.acknowledge()
		if i < 3:
			assert_eq(c.chapter, i + 1)
			c.acknowledge()
	assert_eq(seen, ["c0", "c1", "c2", "c3"])
	assert_eq(c.phase, CareerSystem.CREDITS)
	assert_eq(credits.size(), 1)
	c.acknowledge()
	assert_eq(c.phase, CareerSystem.DONE)


func test_save_load_mid_chapter() -> void:
	var e := Env.new()
	var chs := [_ch("a", [_obj("o", "event", {"topic": "go", "count": 3}), _obj("p", "population", {"count": 99})], "", ""), _ch("b", [_obj("q", "event", {"topic": "go", "count": 1})])]
	var c := _career(chs, e)
	c.start_new()
	e.sim.bus.emit(&"go", {})
	e.sim.bus.emit(&"go", {})
	var snap := JSON.parse_string(JSON.stringify(c.save_state())) as Dictionary
	var c2 := CareerSystem.new(_data(chs))
	c2.load_state(snap)
	assert_true(c2.active)
	assert_eq(c2.chapter, 0)
	assert_eq(c2.phase, CareerSystem.ACTIVE)
	assert_eq(float(c2.counts["o"]), 2.0)
	c2.load_state({"active": true, "chapter": 99, "phase": "bogus"})
	assert_eq(c2.chapter, 1, "clamped")
	assert_eq(c2.phase, CareerSystem.ACTIVE)


func test_inactive_career_does_not_touch_sandbox() -> void:
	var e := Env.new()
	var c := _career([_ch("a", [_obj("o", "event", {"topic": "go", "count": 1})])], e)
	e.sim.bus.emit(&"go", {})
	e.sim.advance(1.0)
	assert_false(c.active)
	assert_true(c.done.is_empty())
	assert_false(e.sim.clock.is_paused())
	var g := GameSettings.new()
	assert_eq(g.mode, ModeDefs.SANDBOX)
	assert_eq(c.current_chapter(), {})


func test_start_state_overrides() -> void:
	var e := Env.new(5000, {})
	var ch := _ch("a", [_obj("o", "event", {"topic": "go", "count": 1})], "", "")
	ch["start_state"] = {"resources": {"logs": 7}, "season": "summer", "season_progress": 0.2, "bogus": 1}
	var d := _data([ch])
	assert_true(d["errors"].size() == 1, "unknown start key reported")
	var c := CareerSystem.new(d)
	e.sim.register_system(c)
	c.attach(e.sim)
	c.bind(e.vs, e.seasons, e.eco, e.nb)
	c.start_new()
	assert_eq(e.eco.total(&"logs"), 7)
	assert_eq(e.seasons.season(), SeasonDefs.SUMMER)
