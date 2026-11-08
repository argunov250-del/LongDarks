extends "res://tests/test_case.gd"
## Step 20 (design/gdd/fuel-and-upgrades.md).

const VehEnv = preload("res://tests/vehicles/veh_env.gd")


func _chain(recipe: StringName, building: StringName, inputs: Dictionary) -> Dictionary:
	var r := VehEnv.new(SeasonDefs.SPRING, inputs)
	r.e.prod.external_work = false
	var id: int = r.e.add_done(building)
	r.e.prod.set_recipe(id, recipe)
	r.run(Recipes.duration(recipe) + 5.0)
	return {"r": r, "e": r.e}


func test_biodiesel_chain_steps() -> void:
	var c := _chain(&"oil_press_oil", &"oil_press", {&"rapeseed": 3})
	assert_eq(c["e"].eco.total(&"oil"), 1, "rapeseed -> oil")
	var c2 := _chain(&"biodiesel_plant_biodiesel", &"biodiesel_plant", {&"oil": 1})
	assert_eq(c2["e"].eco.total(&"biodiesel"), 1, "oil -> biodiesel")


func test_alcohol_from_grain_or_potato_and_biogas() -> void:
	assert_eq(_chain(&"distillery_grain", &"distillery", {&"grain": 4})["e"].eco.total(&"alcohol"), 1, "grain")
	assert_eq(_chain(&"distillery_potato", &"distillery", {&"potato": 5})["e"].eco.total(&"alcohol"), 1, "potato")
	assert_eq(_chain(&"biogas_plant_biogas", &"biogas_plant", {&"manure": 3, &"waste": 2})["e"].eco.total(&"biogas"), 2, "biogas")


func test_wrong_fuel_refused_and_conversion_enables() -> void:
	var r := VehEnv.new(SeasonDefs.SPRING, {&"workshop_dummy": 0})
	var pick := r.spawn(&"pickup", 1.0, 0.0)
	assert_eq(r.vh.fuelx.refuel_with(pick, &"biodiesel", 2), 0, "petrol refuses biodiesel")
	assert_eq(r.vh.fuelx.refuel_with(pick, &"alcohol", 2), 0, "petrol refuses alcohol")
	var truck := r.spawn(&"truck", 1.0, 0.0)
	assert_true(r.vh.fuelx.refuel_with(truck, &"biodiesel", 2) > 0, "diesel burns biodiesel unconverted")
	assert_eq(r.vh.fuelx.refuel_with(truck, &"alcohol", 2), 0, "diesel refuses alcohol")
	assert_eq(r.vh.fuelx.refuel_with(truck, &"firewood", 2), 0, "diesel refuses wood")
	pick.conversion = FuelDefs.BIOFUEL
	assert_true(r.vh.fuelx.refuel_with(pick, &"alcohol", 2) > 0, "converted pickup takes alcohol")


func test_gasgen_burns_firewood_slower() -> void:
	var r := VehEnv.new()
	var a := r.spawn(&"truck", 1.0, 10.0, 0)
	var g := r.spawn(&"truck", 1.0, 10.0, 1)
	g.conversion = FuelDefs.GASGEN
	var i := r.vh.cell_idx(a.pos)
	assert_true(r.vh.speed_at(g, i, null) < r.vh.speed_at(a, i, null), "slower")
	assert_true(g.tank() < a.tank(), "small hopper")
	assert_true(r.vh.fuelx.refuel_with(g, &"firewood", 3) > 0, "wood accepted")
	assert_eq(r.vh.fuelx.refuel_with(g, &"biodiesel", 3), 0, "gasgen refuses biodiesel")
	var f0 := g.fuel
	var f1 := a.fuel
	r.vh._after_move(g, i, 1000.0)
	r.vh._after_move(a, i, 1000.0)
	assert_true(f0 - g.fuel > f1 - a.fuel, "burns more per km")


func test_refuel_trip() -> void:
	var r := VehEnv.new(SeasonDefs.SPRING, {&"biodiesel": 20})
	var v := r.spawn(&"truck", 1.0, 5.0)
	var m := r.vh.plan(v)
	assert_eq(m.get("kind", &""), &"refuel", "low tank plans a refuel trip")
	var s: Storage = r.e.eco.get_storage(int(m["store"]))
	var before: int = s.amount(&"biodiesel")
	var d := r.driver()
	v.pos = s.position
	assert_true(r.vh.board(d, v), "boarded")
	for k in 80:
		r.vh.drive_tick(d, {"target": v.id}, 1.0)
	assert_true(v.fuel > 5.0 and s.amount(&"biodiesel") < before, "tank filled from storage")


func test_upgrades_effects() -> void:
	var r := VehEnv.new()
	var a := r.spawn(&"truck", 1.0, 999.0, 0)
	var b := r.spawn(&"truck", 1.0, 999.0, 1)
	r.vh.snow_override = 1.0
	var i := r.vh.cell_idx(a.pos)
	b.upgrades.append(&"chains")
	assert_true(r.vh.slip_level(b, i) < r.vh.slip_level(a, i), "chains cut slip")
	r.vh.snow_override = 0.0
	r.vh.temperature_override = -25.0
	var c := r.spawn(&"truck", 1.0, 999.0, 2)
	c.upgrades.append(&"insulation")
	assert_true(r.vh.start_fail_chance(c) < r.vh.start_fail_chance(a), "insulation eases winter start")
	assert_true(r.vh.start_delay(c) < r.vh.start_delay(a), "shorter warm-up")
	r.vh.temperature_override = 15.0
	r.vh.night_override = 1
	var h := r.spawn(&"truck", 1.0, 999.0, 3)
	h.upgrades.append(&"headlights")
	assert_true(r.vh.speed_at(h, i, null) > r.vh.speed_at(a, i, null), "headlights faster at night")


func test_conversion_job_and_save() -> void:
	var r := VehEnv.new(SeasonDefs.SPRING, {&"spare_parts": 20, &"scrap_metal": 20})
	r.e.add_done(&"workshop")
	var v := r.spawn(&"pickup")
	assert_true(r.vh.fuelx.start_mod(v, FuelDefs.BIOFUEL), "queued")
	assert_false(r.vh.fuelx.start_mod(v, &"chains"), "one job at a time")
	r.run(25.0)
	assert_true(v.mod_job != null and v.mod_job.condition > 0.0 and v.conversion == FuelDefs.NO_CONVERSION, "mid-conversion")
	var saved := r.vh.save_state()
	var psaved: Dictionary = r.e.prod.save_state()
	var r2 := VehEnv.new(SeasonDefs.SPRING, {&"spare_parts": 20, &"scrap_metal": 20})
	r2.e.add_done(&"workshop")
	r2.e.prod.load_state(psaved)
	r2.vh.load_state(saved)
	var v2 := r2.vh.vehicle_list()[0]
	assert_true(v2.mod_job != null and v2.mod_job.condition > 0.0, "progress restored")
	r2.run(120.0)
	assert_eq(v2.conversion, FuelDefs.BIOFUEL, "conversion finished after load")
	r2.vh.fuelx.start_mod(v2, &"headlights")
	r2.run(100.0)
	assert_true(v2.has_upgrade(&"headlights"), "upgrade installed")
