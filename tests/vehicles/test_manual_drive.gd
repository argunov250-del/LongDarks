extends "res://tests/test_case.gd"
## Step 21 manual driving (design/gdd/manual-driving.md): schemes, take/leave rules, same physics as AI,
## crashes, fuel, settings persistence.

const VehEnv = preload("res://tests/vehicles/veh_env.gd")
const TMP_CFG := "user://test_drive_settings.cfg"


func _driving(r: VehEnv, type: StringName = &"truck") -> Array:
	var v := r.spawn(type)
	v.warm = 1.0
	var md := ManualDrive.new(r.vh)
	assert_true(md.take(v), "take: " + md.refusal_text)
	return [md, v]


## Distance covered in `secs` of full gas (heading fixed, 60 fps).
func _run_gas(md: ManualDrive, secs: float, steer := 0.0) -> float:
	var v := md.vehicle
	var p0 := v.pos
	var t := 0.0
	while t < secs:
		md.update(1.0 / 60.0, steer, 1.0)
		t += 1.0 / 60.0
	return Vector2(v.pos.x - p0.x, v.pos.z - p0.z).length()


# ---------- input schemes ----------

func test_joystick_maps_and_dead_zone() -> void:
	var j := JoystickScheme.new()
	j.set_stick(Vector2(0.0, -1.0))
	assert_almost_eq(j.throttle(), 1.0)
	assert_almost_eq(j.steer(), 0.0)
	j.set_stick(Vector2(1.0, 0.0))
	assert_almost_eq(j.steer(), 1.0)
	j.set_stick(Vector2(0.0, 1.0))
	assert_almost_eq(j.throttle(), -1.0)
	j.set_stick(Vector2(0.05, -0.05))
	assert_eq(j.axes(), Vector2.ZERO, "inside the dead zone")
	j.set_stick(Vector2(3.0, 0.0))
	assert_almost_eq(j.steer(), 1.0, 0.0001, "clamped to 1")
	j.set_stick(Vector2(0.0, -0.56))
	assert_true(j.throttle() > 0.0 and j.throttle() < 1.0, "analogue")
	j.reset()
	assert_eq(j.axes(), Vector2.ZERO)


func test_buttons_map() -> void:
	var b := ButtonsScheme.new()
	b.gas = true
	assert_eq(b.axes(), Vector2(0, 1))
	b.brake = true
	assert_eq(b.throttle(), 0.0, "gas+brake cancel")
	b.gas = false
	b.left = true
	assert_eq(b.axes(), Vector2(-1, -1))
	b.right = true
	assert_eq(b.steer(), 0.0)
	b.reset()
	assert_eq(b.axes(), Vector2.ZERO)


func _tilt_sample(roll_deg: float, pitch_deg: float) -> Vector3:
	var g := 9.81
	return Vector3(sin(deg_to_rad(roll_deg)) * g, cos(deg_to_rad(pitch_deg)) * g, sin(deg_to_rad(pitch_deg)) * g)


func test_tilt_calibration_and_dead_zone() -> void:
	var t := TiltScheme.new()
	t.feed(_tilt_sample(0.0, 40.0))  # first sample = neutral (held comfortably at 40 deg)
	assert_true(t.is_calibrated())
	assert_eq(t.axes(), Vector2.ZERO, "neutral pose = no input")
	t.feed(_tilt_sample(2.0, 41.0))
	assert_eq(t.axes(), Vector2.ZERO, "inside the dead zone")
	t.feed(_tilt_sample(30.0, 40.0))
	assert_almost_eq(t.steer(), 1.0, 0.0001)
	t.feed(_tilt_sample(-30.0, 40.0))
	assert_almost_eq(t.steer(), -1.0, 0.0001)
	t.feed(_tilt_sample(0.0, 40.0 + 12.0))
	assert_true(t.throttle() > 0.0 and t.throttle() < 1.0, "partial gas")
	t.feed(_tilt_sample(0.0, 40.0 - 30.0))
	assert_almost_eq(t.throttle(), -1.0, 0.0001, "tilt back = brake")
	# recalibrate to a new pose
	t.feed(_tilt_sample(10.0, 70.0))
	t.calibrate()
	assert_eq(t.axes(), Vector2.ZERO)
	# stored neutral is honoured
	var t2 := TiltScheme.new()
	t2.set_neutral(_tilt_sample(0.0, 40.0))
	t2.feed(_tilt_sample(0.0, 40.0))
	assert_eq(t2.axes(), Vector2.ZERO)


# ---------- take / leave ----------

func test_take_refused_when_not_drivable() -> void:
	var r := VehEnv.new()
	var wreck := r.spawn(&"truck", 0.25)
	var md := ManualDrive.new(r.vh)
	assert_false(md.take(wreck), "wreck needs repair")
	assert_true(md.refusal_text.contains("ремонт"))
	assert_false(wreck.player_driving)
	var dry := r.spawn(&"pickup", 1.0, 0.0, 1)
	assert_false(md.take(dry), "no fuel")
	assert_eq(md.refusal_text, "Нет топлива")
	var broken := r.spawn(&"atv", 1.0, 50.0, 2)
	broken.set_part(&"engine", 0.05)
	broken.serviceable = true
	assert_false(md.take(broken), "a broken part")
	assert_false(md.is_active())


func test_take_and_leave_returns_control() -> void:
	var r := VehEnv.new(SeasonDefs.SPRING, {&"spare_parts": 50, &"logs": 200})
	var v := r.spawn(&"truck")
	var d := r.driver()
	v.assigned_driver = d.id
	v.driver_id = d.id
	v.mission = {"kind": &"haul", "phase": &"to_src"}
	var md := ManualDrive.new(r.vh)
	assert_true(md.take(v))
	assert_true(v.player_driving)
	assert_eq(v.driver_id, 0, "the driver stepped out")
	assert_true(r.vh.jobs().filter(func(j): return j["target"] == v.id).is_empty(), "AI is not offered this vehicle")
	assert_false(r.vh.board(d, v), "AI cannot board")
	assert_eq(r.vh.status_text(v), "Вы за рулём")
	md.leave()
	assert_false(v.player_driving)
	assert_false(md.is_active())
	assert_eq(v.assigned_driver, d.id, "assignment is kept")
	assert_false(md.update(0.1, 0.0, 1.0), "no longer driving")


func test_warmup_before_moving_and_frost_start() -> void:
	var r := VehEnv.new()
	r.vh.temperature_override = -20.0
	var v := r.spawn(&"truck")
	v.warm = 0.0
	var md := ManualDrive.new(r.vh)
	assert_true(md.take(v))
	assert_eq(md.state, ManualDrive.State.WARMUP)
	assert_true(md.warm_left > 5.0, "frost lengthens the start")
	var p0 := v.pos
	for i in 120:
		md.update(0.05, 0.0, 1.0)
	assert_eq(v.pos, p0, "does not move while warming up")
	for i in 2000:
		md.update(0.05, 0.0, 0.0)
	assert_eq(md.state, ManualDrive.State.DRIVING)
	assert_almost_eq(v.warm, 1.0)
	# dead battery in deep frost: the engine will not start
	r.vh.temperature_override = -45.0
	var w := r.spawn(&"truck", 1.0, 99.0, 1)
	w.warm = 0.0
	w.set_part(&"battery", 0.2)
	var md2 := ManualDrive.new(r.vh)
	var started := false
	for k in 12:
		started = started or md2.take(w)
		if started:
			break
	assert_true(started or md2.refusal_text != "", "either it starts or the player is told why not")


# ---------- same physics as AI ----------

func test_motion_and_steering() -> void:
	var r := VehEnv.new()
	var a := _driving(r)
	var md: ManualDrive = a[0]
	var v: Vehicle = a[1]
	v.facing = 0.0
	var d := _run_gas(md, 2.0)
	assert_true(d > 1.0, "moves forward")
	assert_true(md.speed_kmh() > 0.0)
	var f0 := v.facing
	md.update(0.05, 1.0, 1.0)
	md.update(0.05, 1.0, 1.0)
	assert_true(v.facing < f0, "steer right turns clockwise seen from above (facing decreases)")
	# standing still: steering does nothing
	var b := _driving(r, &"pickup")
	var f1: float = b[1].facing
	b[0].update(0.1, 1.0, 0.0)
	assert_eq(b[1].facing, f1)


func test_speed_never_exceeds_ai_speed() -> void:
	var r := VehEnv.new()
	var a := _driving(r)
	var md: ManualDrive = a[0]
	_run_gas(md, 6.0)
	var cap := r.vh.speed_at(md.vehicle, r.vh.cell_idx(md.vehicle.pos), null)
	assert_true(absf(md.speed) <= cap + 0.001, "same top speed as the AI formula")
	assert_true(absf(md.speed) > cap * 0.8 or md.event == &"blocked" or md.event == &"stuck", "reaches it")


func test_mud_slows_cargo_slows_road_speeds_up() -> void:
	var r := VehEnv.new()
	var base := _driving(r)
	var cap0: float = base[0].max_speed()
	r.vh.mud_override = 1.0
	assert_true(base[0].max_speed() < cap0, "mud: slower")
	r.vh.mud_override = 0.0
	base[1].cargo_res = &"logs"
	base[1].cargo_n = VehicleDefs.capacity_units(&"truck", &"logs")
	assert_true(base[0].max_speed() < cap0, "cargo: slower")
	base[1].cargo_n = 0
	r.vh.trails.build_road(r.vh.cell_idx(base[1].pos))
	assert_true(base[0].max_speed() > cap0, "road: faster")
	# heavy cargo also accelerates slower
	var light := _driving(r, &"pickup")
	var heavy := _driving(r, &"pickup")
	heavy[1].cargo_res = &"logs"
	heavy[1].cargo_n = VehicleDefs.capacity_units(&"pickup", &"logs")
	light[1].pos = r.spot(3)
	heavy[1].pos = r.spot(3)
	light[0].update(0.1, 0.0, 1.0)
	heavy[0].update(0.1, 0.0, 1.0)
	assert_true(absf(heavy[0].speed) < absf(light[0].speed), "weight: slower acceleration")


func test_fuel_consumed_by_distance() -> void:
	var r := VehEnv.new()
	var a := _driving(r)
	var v: Vehicle = a[1]
	var f0 := v.fuel
	var d := _run_gas(a[0], 3.0)
	assert_true(v.fuel < f0, "fuel burns")
	assert_almost_eq(f0 - v.fuel, d / 1000.0 * float(VehicleDefs.def(v.type)["fuel_km"]), 0.01, "same L/km as AI")
	assert_true(v.odometer > 0.0)


func test_out_of_fuel_stops_gas() -> void:
	var r := VehEnv.new()
	var a := _driving(r, &"pickup")
	var md: ManualDrive = a[0]
	a[1].fuel = 0.0
	md.update(0.05, 0.0, 1.0)
	assert_eq(md.event, &"no_fuel")
	assert_true(md.speed <= 0.0, "no gas without fuel")
	assert_true(md.update(0.05, 0.0, 0.0), "the player may still step out")


func test_crash_wears_parts_and_stops() -> void:
	var r := VehEnv.new()
	var a := _driving(r)
	var md: ManualDrive = a[0]
	var v: Vehicle = a[1]
	_run_gas(md, 1.5)
	var before := v.parts.duplicate()
	r.vh.crash(v, 0.0)
	assert_true(float(v.parts[&"engine"]) < float(before[&"engine"]), "crash damages")
	md.update(0.05, 0.0, 1.0)
	assert_true(md.update(0.05, 0.0, 1.0))
	# repeated driving over a stretch with a forced accident chance: parts only ever go down
	var w := _driving(r, &"pickup")
	var wv: Vehicle = w[1]
	wv.accident_rolls = 0
	var e0 := float(wv.parts[&"engine"])
	_run_gas(w[0], 4.0)
	assert_true(float(wv.parts[&"engine"]) <= e0, "wear never repairs")
	assert_true(float(wv.parts[&"tires"]) < 1.0, "tyres wear while driving")


func test_broken_vehicle_halts_the_player() -> void:
	var r := VehEnv.new()
	var a := _driving(r)
	var v: Vehicle = a[1]
	_run_gas(a[0], 1.0)
	v.set_part(&"engine", 0.0)
	a[0].update(0.05, 0.0, 1.0)
	assert_eq(a[0].event, &"broken")
	assert_eq(a[0].speed, 0.0)


func test_stuck_vehicle_waits() -> void:
	var r := VehEnv.new()
	var a := _driving(r)
	var v: Vehicle = a[1]
	v.stuck_left = 1.0
	var p0 := v.pos
	a[0].update(0.05, 0.0, 1.0)
	assert_eq(v.pos, p0)
	assert_eq(a[0].event, &"stuck")
	for i in 40:
		a[0].update(0.05, 0.0, 0.0)
	assert_true(v.stuck_left <= 0.0)


func test_loading_a_save_ends_manual_driving() -> void:
	var r := VehEnv.new()
	var a := _driving(r)
	var snap: Dictionary = r.vh.save_state()
	r.vh.load_state(snap)
	assert_false(a[0].update(0.1, 0.0, 1.0), "the old vehicle object is gone")
	assert_false(a[0].is_active())


# ---------- settings ----------

func test_setting_persists_outside_the_save() -> void:
	DirAccess.remove_absolute(TMP_CFG)
	var s := DriveSettings.new(TMP_CFG)
	assert_eq(s.scheme, ManualDriveDefs.SCHEME_JOYSTICK, "default")
	assert_true(s.set_scheme(ManualDriveDefs.SCHEME_TILT))
	assert_false(s.set_scheme(&"warp"), "unknown refused")
	s.tilt_neutral = Vector3(0.0, 6.0, 7.5)
	assert_eq(s.save(), OK)
	var s2 := DriveSettings.new(TMP_CFG)
	assert_eq(s2.load(), OK)
	assert_eq(s2.scheme, ManualDriveDefs.SCHEME_TILT)
	assert_eq(s2.tilt_neutral, Vector3(0.0, 6.0, 7.5))
	assert_false(DriveSettings.DEFAULT_PATH.begins_with(SaveManager.SAVE_DIR), "not in the game save folder")
	var bad := FileAccess.open(TMP_CFG, FileAccess.WRITE)
	bad.store_string("[driving]\nscheme=\"nonsense\"\n")
	bad.close()
	var s3 := DriveSettings.new(TMP_CFG)
	s3.load()
	assert_eq(s3.scheme, ManualDriveDefs.DEFAULT_SCHEME, "corrupt value -> default")
	DirAccess.remove_absolute(TMP_CFG)
