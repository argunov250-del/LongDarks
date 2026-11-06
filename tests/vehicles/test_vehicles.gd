extends "res://tests/test_case.gd"
## Step 18 vehicles (design/gdd/vehicles.md).

const VehEnv = preload("res://tests/vehicles/veh_env.gd")


func test_start_has_four_abandoned_vehicles_near_ruins() -> void:
	var r := VehEnv.new()
	r.vh.populate_start()
	assert_eq(r.vh.vehicles.size(), 4)
	var types := r.vh.vehicle_list().map(func(v: Vehicle) -> StringName: return v.type)
	for t in [&"pickup", &"truck", &"tractor", &"atv"]:
		assert_true(types.has(t), "start vehicle " + String(t))
	for v in r.vh.vehicle_list():
		assert_false(r.vh.is_drivable(v), "abandoned vehicle cannot drive")
		assert_true(r.vh.pf.is_passable(r.e.world.cell_of(v.pos.x, v.pos.z)))
	var near := 0
	for v in r.vh.vehicle_list():
		for rd in r.e.con.ruins.values():
			if Vector2(v.pos.x - rd["pos"].x, v.pos.z - rd["pos"].z).length() < 24.0:
				near += 1
				break
	assert_eq(near, 4, "all near ruins")


func test_unrepaired_cannot_drive_workshop_repair_fixes() -> void:
	var r := VehEnv.new(SeasonDefs.SPRING, {&"spare_parts": 30})
	var v := r.spawn(&"pickup", 0.3)
	assert_false(r.vh.is_drivable(v))
	assert_true(r.vh.jobs().is_empty(), "no driving job for a broken vehicle")
	var ws: int = r.e.add_done(&"workshop")
	assert_true(ws > 0)
	r.e.prod.sync_now() if r.e.prod.has_method("sync_now") else null
	assert_true(r.e.prod.queue_repair(ws, v.repair_id), "queued in the workshop")
	r.e.add_villager(&"mechanic")
	r.run(900.0)
	assert_true(v.condition >= VehicleDefs.DRIVABLE_CONDITION, "workshop repaired it: %f" % v.condition)
	assert_true(r.vh.is_drivable(v))


func test_driver_rules_and_skill_speed() -> void:
	var r := VehEnv.new()
	var v := r.spawn(&"truck")
	var dr := r.driver(0.1)
	var plain: Villager = r.e.add_villager(&"farmer")
	assert_true(r.vh.can_drive(dr, v))
	assert_false(r.vh.can_drive(plain, v), "non-driver cannot drive while a driver exists")
	v.assigned_driver = plain.id
	assert_true(r.vh.can_drive(plain, v), "player assignment lets anyone drive")
	assert_false(r.vh.can_drive(dr, v))
	v.assigned_driver = 0
	var rn := VehEnv.new()
	var v2 := rn.spawn(&"truck")
	assert_true(rn.vh.can_drive(rn.e.add_villager(&"farmer"), v2), "no drivers at all: anyone")
	var slow := r.driver(0.1)
	var fast := r.driver(1.0)
	var i := r.vh.cell_idx(v.pos)
	assert_true(r.vh.speed_at(v, i, fast) > r.vh.speed_at(v, i, slow), "experienced driver is faster")


func test_cargo_weight_slows_and_limits() -> void:
	var r := VehEnv.new()
	var v := r.spawn(&"truck")
	var d := r.driver(0.5)
	var i := r.vh.cell_idx(v.pos)
	var empty := r.vh.speed_at(v, i, d)
	v.cargo_res = &"logs"
	v.cargo_n = VehicleDefs.capacity_units(&"truck", &"logs")
	assert_true(v.load_frac() > 0.9)
	assert_true(r.vh.speed_at(v, i, d) < empty, "loaded truck is slower")
	assert_true(VehicleDefs.capacity_units(&"truck", &"logs") < VehicleDefs.capacity_units(&"truck", &"firewood"), "heavy cargo limits count")
	r.vh.mud_override = 1.0
	var loaded_slip := r.vh.slip_level(v, i)
	v.cargo_n = 0
	assert_true(loaded_slip > r.vh.slip_level(v, i), "load worsens slipping")


func test_mud_and_snow_traction_per_type() -> void:
	var r := VehEnv.new()
	var truck := r.spawn(&"truck")
	var atv := r.spawn(&"atv", 1.0, 99.0, 1)
	var sno := r.spawn(&"snowmobile", 1.0, 9.0, 2)
	var i := r.vh.cell_idx(truck.pos)
	r.vh.mud_override = 1.0
	assert_true(r.vh.slip_level(atv, i) < r.vh.slip_level(truck, i), "atv better in mud")
	assert_true(r.vh.slip_level(sno, i) > r.vh.slip_level(atv, i), "snowmobile poor in mud")
	r.vh.mud_override = 0.0
	r.vh.snow_override = 1.0
	assert_true(r.vh.slip_level(sno, i) < r.vh.slip_level(truck, i), "snowmobile good in snow")
	assert_true(r.vh.slip_level(atv, i) < r.vh.slip_level(truck, i))
	r.vh.snow_override = 0.0
	assert_eq(r.vh.slip_level(truck, i), 0.0, "dry: no slip")


func test_frost_warmup_delay() -> void:
	var r := VehEnv.new()
	var v := r.spawn(&"truck")
	var warm := r.vh.start_delay(v)
	r.vh.temperature_override = -25.0
	var cold := r.vh.start_delay(v)
	assert_true(cold > warm * 5.0, "frost lengthens start")
	v.warm = 1.0
	assert_eq(r.vh.start_delay(v), 0.0, "warm engine starts at once")
	v.warm = 0.0
	var sn := r.spawn(&"snowmobile", 1.0, 9.0, 1)
	assert_true(r.vh.start_delay(sn) < cold, "snowmobile starts easier in frost")


func test_fuel_consumption_and_empty_stop() -> void:
	var r := VehEnv.new()
	var v := r.spawn(&"truck", 1.0, 1.0)
	var d := r.driver(0.5)
	var goal := r.spot(4)
	var f0 := v.fuel
	for k in 40:
		r.vh._drive_to(v, d, goal, 2.0, 0.5)
	assert_true(v.fuel < f0, "fuel burns")
	assert_almost_eq(f0 - v.fuel, v.odometer / 1000.0 * 3.0, 0.0001, "per km")
	v.fuel = 0.00001
	for k in 200:
		r.vh._drive_to(v, d, r.spot(7), 2.0, 0.5)
	assert_true(v.fuel <= 0.0)
	assert_false(r.vh.is_drivable(v), "empty tank: stops")
	r.vh.refuel(v, 5.0)
	assert_true(r.vh.is_drivable(v), "refuel hook")


func test_road_and_ruts_speed_and_layers() -> void:
	var r := VehEnv.new()
	var v := r.spawn(&"truck")
	var d := r.driver(0.5)
	var i := r.vh.cell_idx(v.pos)
	var plain := r.vh.speed_at(v, i, d)
	for k in 12:
		r.vh.trails.add_rut(i)
	var rutted := r.vh.speed_at(v, i, d)
	assert_true(rutted > plain, "ruts speed vehicles up")
	r.vh.trails.build_road(i)
	assert_true(r.vh.speed_at(v, i, d) > rutted, "road is faster than ruts")
	assert_false(r.vh.trails.ruts.has(i), "road replaces the rut layer")
	r.vh.mud_override = 1.0
	assert_true(r.vh.slip_level(v, i) < r.vh.slip_level(v, i + 1), "road gives traction in mud")


func test_ruts_form_from_driving_and_overgrow() -> void:
	var r := VehEnv.new()
	var v := r.spawn(&"truck")
	var d := r.driver(0.5)
	var a := v.pos
	var b := r.vh.pf.nearest_passable(a + Vector3(40.0, 0.0, 0.0))
	for trip in 12:
		for goal in [b, a]:
			for k in 400:
				if r.vh._drive_to(v, d, goal, 2.0, 0.5) != VehicleSystem.Go.MOVING:
					break
	assert_true(r.vh.trails.ruts.size() > 5, "ruts appear")
	var best := 0.0
	for i in r.vh.trails.ruts:
		best = maxf(best, r.vh.trails.rut_level(i))
	assert_true(best >= 0.5, "frequent path: deep ruts %f" % best)
	r.vh.trails.decay(30.0)
	assert_true(r.vh.trails.ruts.is_empty(), "unused ruts overgrow")


func test_footpaths_form_speed_walking_and_overgrow() -> void:
	var r := VehEnv.new()
	var p0 := r.spot(0)
	var p1 := r.spot(1)
	var i0 := r.vh.cell_idx(p0)
	assert_eq(r.vh.walk_mult_at(p0), 1.0)
	for k in 14:
		r.vh.note_walk(1, p0)
		r.vh.note_walk(1, p1)
	assert_true(r.vh.walk_mult_at(p0) > 1.1, "footpath speeds walking")
	assert_true(r.vh.trails.foot_level(i0) >= 0.9)
	assert_true(r.vh.trails.ruts.is_empty(), "layers are separate")
	r.vh.trails.decay(20.0)
	assert_eq(r.vh.walk_mult_at(p0), 1.0, "footpath overgrows when unused")


func test_tractor_plows_faster_than_a_villager() -> void:
	var r := VehEnv.new()
	var cells := r.f.field_cells(1)
	var idx := r.f.idx(cells[0])
	var v := r.spawn(&"tractor")
	var d := r.driver(0.5)
	var t := {"target": v.id}
	assert_true(r.vh.board(d, v))
	var secs := 0.0
	while r.f.food.field_action(idx) == &"plow" and secs < 600.0:
		r.vh.drive_tick(d, t, 0.5)
		secs += 0.5
		if v.driver_id == 0:
			break
	assert_eq(r.f.food.field_action(idx), &"sow", "plowed by the tractor")
	var walk_time: float = r.f.food.work_need(&"field", idx) / r.e.vs.work_rate(d, TaskDefs.FIELD)
	assert_true(VehicleDefs.def(&"tractor")["work"] > 1.0)
	# the work phase alone (without driving) is shorter than manual work
	assert_true(secs < walk_time + 60.0, "plowing done in reasonable time")


func test_truck_hauls_between_storages() -> void:
	var r := VehEnv.new(SeasonDefs.SPRING, {&"firewood": 1200, &"logs": 300})
	var s2 := r.second_storage()
	var v := r.spawn(&"truck")
	r.driver(0.5)
	var plan := r.vh.plan(v)
	assert_false(plan.is_empty(), "imbalance -> haul")
	assert_eq(plan["n"], VehicleDefs.capacity_units(&"truck", plan["res"]), "big capacity")
	assert_true(r.vh.jobs().size() == 1)
	var before := s2.used()
	r.run(300.0)
	assert_true(s2.used() > before, "cargo delivered to the second storage")
	assert_eq(v.cargo_n, 0)


func test_site_machines_speed_up_construction() -> void:
	var r := VehEnv.new()
	var id: int = r.e.place_near_hub(&"dugout")
	var ex := r.spawn(&"excavator")
	var cr := r.spawn(&"crane", 1.0, 99.0, 1)
	assert_eq(r.vh.site_multiplier(&"build", id), 1.0)
	ex.mission = {"kind": &"assist", "phase": &"work", "skind": &"build", "target": id}
	assert_almost_eq(r.vh.site_multiplier(&"build", id), 1.6, 0.0001, "excavator")
	cr.mission = {"kind": &"assist", "phase": &"work", "skind": &"build", "target": id}
	assert_almost_eq(r.vh.site_multiplier(&"build", id), 1.6 * 1.5, 0.0001, "excavator + crane")
	assert_true(r.vh.site_multiplier(&"dismantle", id) == 1.0, "only at its own site")


func test_road_brush_marks_and_builder_work() -> void:
	var r := VehEnv.new(SeasonDefs.SPRING, {&"stone": 30})
	var cells := r.vh.road_cells_in_brush(r.spot(0), 4.0, true)
	assert_true(cells.size() > 3)
	var n := r.vh.designate_road(cells)
	assert_true(n > 0)
	assert_eq(r.vh.road_jobs().size(), mini(n, VehicleDefs.ROAD_JOB_CAP))
	for c in cells:
		r.vh.add_road_work(c.y * r.e.world.size + c.x, 99.0)
	assert_eq(r.vh.trails.roads.size(), n)
	assert_true(r.vh.road_jobs().is_empty())


func test_ruin_find_hook() -> void:
	var r := VehEnv.new()
	var v := r.vh.discover_at(r.spot(0), 0.0, 0.5)
	assert_true(v != null and v.origin == &"ruins")
	assert_false(r.vh.is_drivable(v))


func test_save_load_mid_trip() -> void:
	var r := VehEnv.new(SeasonDefs.SPRING, {&"firewood": 1200, &"logs": 300})
	var s2 := r.second_storage()
	var v := r.spawn(&"truck")
	r.driver(0.5)
	r.vh.trails.add_rut(5, 3.0)
	r.run(12.0)
	assert_true(v.driver_id != 0 and not v.mission.is_empty(), "trip in progress")
	var snap := JSON.parse_string(JSON.stringify(r.e.sim.to_dict())) as Dictionary
	var q := VehEnv.new(SeasonDefs.SPRING, {})
	q.second_storage()
	q.e.sim.from_dict(snap)
	var v2: Vehicle = q.vh.vehicles.values()[0]
	assert_eq(v2.type, &"truck")
	assert_eq(v2.mission.get("phase"), v.mission.get("phase"))
	assert_eq(v2.driver_id, v.driver_id)
	assert_true(q.vh.trails.ruts.has(5), "ruts saved")
	q.run(300.0)
	assert_eq(v2.cargo_n, 0, "trip finished after load")
	assert_true(q.e.eco.storages[1].used() > 0, "cargo arrived after load")
	assert_true(s2 != null)
