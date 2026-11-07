extends "res://tests/test_case.gd"
## Step 19 wear and breakdowns (design/gdd/vehicles.md «Износ и поломки»).

const VehEnv = preload("res://tests/vehicles/veh_env.gd")


func _p(v: Vehicle, part: StringName) -> float:
	return float(v.parts[part])


func test_wear_per_part_by_km() -> void:
	var r := VehEnv.new()
	var v := r.spawn(&"truck")
	var i := r.vh.cell_idx(v.pos)
	r.vh.apply_wear(v, i, 1000.0)
	assert_true(_p(v, &"engine") < 1.0 and _p(v, &"tires") < 1.0 and _p(v, &"battery") < 1.0, "all parts wear")
	assert_true(1.0 - _p(v, &"tires") > 1.0 - _p(v, &"engine"), "tyres wear faster than the engine by default")
	assert_true(1.0 - _p(v, &"battery") < 1.0 - _p(v, &"engine"), "battery wears slowest by km")


func test_overload_wears_engine_mud_wears_tyres() -> void:
	var r := VehEnv.new()
	var a := r.spawn(&"truck", 1.0, 999.0, 0)
	var b := r.spawn(&"truck", 1.0, 999.0, 1)
	b.cargo_res = &"logs"
	b.cargo_n = VehicleDefs.capacity_units(&"truck", &"logs")
	r.vh.apply_wear(a, r.vh.cell_idx(a.pos), 500.0)
	r.vh.apply_wear(b, r.vh.cell_idx(b.pos), 500.0)
	assert_true(_p(b, &"engine") < _p(a, &"engine"), "overloaded engine wears more")
	var c := r.spawn(&"truck", 1.0, 999.0, 2)
	var d := r.spawn(&"truck", 1.0, 999.0, 3)
	r.vh.mud_override = 1.0
	r.vh.apply_wear(c, r.vh.cell_idx(c.pos), 500.0)
	r.vh.mud_override = 0.0
	r.vh.apply_wear(d, r.vh.cell_idx(d.pos), 500.0)
	assert_true(_p(c, &"tires") < _p(d, &"tires"), "mud wears tyres more")
	r.vh.trails.build_road(r.vh.cell_idx(d.pos))
	var e := r.spawn(&"truck", 1.0, 999.0, 4)
	r.vh.trails.build_road(r.vh.cell_idx(e.pos))
	var f := r.spawn(&"truck", 1.0, 999.0, 6)
	r.vh.apply_wear(e, r.vh.cell_idx(e.pos), 500.0)
	r.vh.apply_wear(f, r.vh.cell_idx(f.pos), 500.0)
	assert_true(_p(e, &"tires") > _p(f, &"tires"), "road spares tyres versus off-road")


func test_frost_drains_parked_battery() -> void:
	var r := VehEnv.new()
	var v := r.spawn(&"pickup")
	r.vh.temperature_override = 15.0
	r.run(600.0)
	assert_almost_eq(_p(v, &"battery"), 1.0, 0.0001, "no drain in warm weather")
	r.vh.temperature_override = -25.0
	r.run(1200.0)
	assert_true(_p(v, &"battery") < 1.0, "frost drains the battery")


func test_frost_start_failures_depend_on_battery() -> void:
	var r := VehEnv.new()
	var good := r.spawn(&"truck", 1.0, 999.0, 0)
	var weak := r.spawn(&"truck", 1.0, 999.0, 1)
	weak.set_part(&"battery", 0.3)
	r.vh.temperature_override = 15.0
	assert_eq(r.vh.start_fail_chance(weak), 0.0, "no start failures when warm")
	r.vh.temperature_override = -25.0
	assert_true(r.vh.start_fail_chance(weak) > r.vh.start_fail_chance(good), "weak battery fails more in frost")
	var dr := r.driver(1.0)
	assert_true(r.vh.start_fail_chance(weak, dr) < r.vh.start_fail_chance(weak), "skilled driver fails less")
	weak.set_part(&"battery", 0.2)
	var fails := 0
	for k in 6:
		var w := r.spawn(&"truck", 1.0, 999.0, 2 + k)
		w.set_part(&"battery", 0.2)
		fails += r.vh.start_failures(w)
		assert_true(_p(w, &"battery") < 0.2, "every attempt wears the battery")
	assert_true(fails > 0, "weak battery in deep frost fails to start sometimes")
	var warm := r.spawn(&"truck", 1.0, 999.0, 9)
	warm.warm = 1.0
	assert_eq(r.vh.start_failures(warm), 0, "a warm engine starts at once")


func test_accidents_depend_on_skill_load_slope() -> void:
	var r := VehEnv.new()
	var v := r.spawn(&"truck")
	var base := r.vh.accident_chance(v, 100.0, 0.0, 0.0, 0.5)
	assert_true(base > 0.0)
	assert_true(r.vh.accident_chance(v, 100.0, 0.0, 0.0, 0.0) > r.vh.accident_chance(v, 100.0, 0.0, 0.0, 1.0), "experienced driver crashes less")
	assert_true(r.vh.accident_chance(v, 100.0, 0.5, 0.0, 0.5) > base, "steep slope is riskier")
	var flat_load := base
	v.cargo_res = &"logs"
	v.cargo_n = VehicleDefs.capacity_units(&"truck", &"logs")
	var loaded_flat := r.vh.accident_chance(v, 100.0, 0.0, 0.0, 0.5)
	assert_true(loaded_flat > flat_load, "overload is riskier")
	assert_true(r.vh.accident_chance(v, 100.0, 0.5, 0.0, 0.5) / r.vh.accident_chance(v, 100.0, 0.0, 0.0, 0.5) > r.vh.accident_chance(v, 100.0, 0.5, 0.0, 0.5) / loaded_flat * 0.0 + 1.0, "slope compounds")
	assert_true(r.vh.accident_chance(v, 100.0, 0.0, 1.0, 0.5) > loaded_flat, "slipping is riskier")


func test_crash_damages_parts_and_notifies_when_broken() -> void:
	var r := VehEnv.new()
	var v := r.spawn(&"truck")
	var got := []
	r.e.sim.bus.subscribe(VehicleSystem.TOPIC_BROKEN, func(p: Dictionary) -> void: got.append(p))
	r.vh.crash(v, 0.0)
	for part in VehicleDefs.PARTS:
		assert_true(_p(v, part) < 1.0, "crash damaged " + String(part))
	assert_true(v.is_repaired(), "a first crash alone does not break a new vehicle")
	assert_true(got.is_empty())
	var soft := r.spawn(&"truck", 1.0, 999.0, 3)
	r.vh.crash(soft, 1.0)
	assert_true(_p(soft, &"engine") >= _p(v, &"engine") - 0.0001 or _p(soft, &"tires") >= _p(v, &"tires") - 0.0001, "skill softens damage")
	r.vh.crash(v, 0.0)
	r.vh.crash(v, 0.0)
	assert_false(v.is_repaired(), "repeated crashes break a part")
	assert_eq(got.size(), 1, "one notification")
	assert_eq(got[0]["text"], "Бурун-5 сломался")


func test_broken_part_stops_vehicle_worn_part_limps() -> void:
	var r := VehEnv.new()
	var v := r.spawn(&"truck")
	var d := r.driver(0.5)
	var i := r.vh.cell_idx(v.pos)
	var fine := r.vh.speed_at(v, i, d)
	v.set_part(&"engine", 0.3)
	assert_true(r.vh.is_drivable(v), "worn engine still drives")
	assert_true(r.vh.speed_at(v, i, d) < fine, "worn engine limps")
	v.set_part(&"engine", 0.05)
	assert_false(r.vh.is_drivable(v), "broken engine stops")
	assert_true(r.vh.jobs().is_empty())
	assert_eq(r.vh.status_text(v), "Сломана: мотор")
	var words: Array = r.vh.part_summary(v).map(func(e: Dictionary) -> String: return e["word"])
	assert_eq(words, ["сломан", "исправны", "исправен"])


func test_workshop_repairs_single_part_with_parts() -> void:
	var r := VehEnv.new(SeasonDefs.SPRING, {&"spare_parts": 20, &"scrap_metal": 20})
	var v := r.spawn(&"truck")
	v.serviceable = true
	v.set_part(&"tires", 0.05)
	assert_false(v.is_repaired())
	var ws: int = r.e.add_done(&"workshop")
	var rid: StringName = v.part_repairs[&"tires"].repair_id
	assert_true(r.e.prod.queue_repair(ws, rid), "tyres queued")
	assert_false(r.e.prod.queue_repair(ws, v.part_repairs[&"engine"].repair_id), "healthy engine needs nothing")
	r.e.add_villager(&"mechanic")
	var scrap_before: int = r.e.storage.amount(&"scrap_metal")
	r.run(900.0)
	assert_true(_p(v, &"tires") > 0.5, "tyres repaired: %f" % _p(v, &"tires"))
	assert_eq(_p(v, &"engine"), 1.0, "engine untouched")
	assert_true(r.e.storage.amount(&"scrap_metal") < scrap_before, "tyres consumed scrap metal")
	assert_true(r.vh.is_drivable(v))


func _field_rig(skill: float) -> Array:
	var r := VehEnv.new(SeasonDefs.SPRING, {&"spare_parts": 20, &"scrap_metal": 20})
	var v := r.spawn(&"pickup")
	v.serviceable = true
	v.set_part(&"engine", 0.0)
	var m: Villager = r.e.add_villager(&"mechanic")
	m.skills[TaskDefs.REPAIR] = skill
	return [r, v, m]


func test_field_repair_by_mechanic_consumes_parts_capped() -> void:
	var a := _field_rig(0.0)
	var r: VehEnv = a[0]
	var v: Vehicle = a[1]
	var m: Villager = a[2]
	assert_eq(r.vh.field_repair_jobs().size(), 1, "broken vehicle offers an on-site job")
	var plain: Villager = r.e.add_villager(&"farmer")
	assert_false(r.vh.can_field_repair(plain), "only a mechanic")
	var before: int = r.e.storage.amount(&"spare_parts")
	var guard := 0
	while r.vh.field_repair_work(m, v.id, 5.0) and guard < 100:
		guard += 1
	assert_true(r.e.storage.amount(&"spare_parts") < before, "parts spent")
	assert_true(_p(v, &"engine") >= VehicleDefs.FIELD_REPAIR_CAP - 0.0001 and _p(v, &"engine") <= VehicleDefs.FIELD_REPAIR_CAP + 0.0001, "capped patch-up: %f" % _p(v, &"engine"))
	assert_true(r.vh.is_drivable(v), "limps home")
	assert_true(r.vh.field_repair_jobs().is_empty())


func test_mechanic_walks_out_and_repairs_in_simulation() -> void:
	var a := _field_rig(0.5)
	var r: VehEnv = a[0]
	var v: Vehicle = a[1]
	r.run(900.0)
	assert_true(_p(v, &"engine") > 0.3, "mechanic repaired on site: %f" % _p(v, &"engine"))


func test_skilled_mechanic_repairs_faster() -> void:
	var a := _field_rig(0.0)
	var b := _field_rig(1.0)
	var slow: Villager = a[2]
	var fast: Villager = b[2]
	assert_true(a[0].e.vs.work_rate(slow, TaskDefs.REPAIR) < b[0].e.vs.work_rate(fast, TaskDefs.REPAIR), "skill raises work rate")
	var plain: Villager = a[0].e.add_villager(&"farmer")
	assert_true(a[0].e.vs.work_rate(slow, TaskDefs.REPAIR) > a[0].e.vs.work_rate(plain, TaskDefs.REPAIR), "mechanic beats a layman")
	a[0].vh.field_repair_work(slow, a[1].id, 100.0)
	b[0].vh.field_repair_work(fast, b[1].id, 100.0)
	assert_true(_p(b[1], &"engine") > _p(a[1], &"engine"), "skilled mechanic restores more per step")


func test_save_load_mid_repair_and_wear() -> void:
	var a := _field_rig(0.3)
	var r: VehEnv = a[0]
	var v: Vehicle = a[1]
	var m: Villager = a[2]
	v.set_part(&"tires", 0.4)
	v.accident_rolls = 7
	r.vh.field_repair_work(m, v.id, 4.0)
	assert_true(v.field_paid and v.field_work > 0.0)
	var d: Dictionary = JSON.parse_string(JSON.stringify(r.vh.save_state()))
	var r2 := VehEnv.new(SeasonDefs.SPRING, {&"spare_parts": 20, &"scrap_metal": 20})
	r2.vh.load_state(d)
	var v2: Vehicle = r2.vh.get_vehicle(v.id)
	assert_almost_eq(_p(v2, &"tires"), 0.4, 0.0001)
	assert_almost_eq(_p(v2, &"engine"), _p(v, &"engine"), 0.0001)
	assert_true(v2.serviceable and v2.field_paid)
	assert_almost_eq(v2.field_work, 4.0 + 0.0, 5.0, "progress kept")
	assert_eq(v2.accident_rolls, 7)
	assert_true(r2.e.prod.get_repairable(v2.part_repairs[&"engine"].repair_id) != null, "part repairables re-registered")
	var m2: Villager = r2.e.add_villager(&"mechanic")
	var spare: int = r2.e.storage.amount(&"spare_parts")
	r2.vh.field_repair_work(m2, v2.id, 100.0)
	assert_eq(r2.e.storage.amount(&"spare_parts"), spare, "a step already paid before saving is not paid twice")
	assert_true(_p(v2, &"engine") > 0.0)


func test_panel_shows_words_not_numbers() -> void:
	var r := VehEnv.new()
	var v := r.spawn(&"truck")
	v.set_part(&"engine", 0.05)
	v.set_part(&"battery", 0.3)
	var panel := VehiclePanel.new()
	panel.setup(r.vh, r.e.sim)
	assert_eq(panel.line_text(v), "Бурун-5 — мотор: сломан · шины: исправны · аккумулятор: изношен")
	assert_eq(panel.rows.size(), 1)
	panel.free()
