class_name ManualDrive
extends RefCounted
## Step 21: the player personally drives one vehicle. Design: design/gdd/manual-driving.md.
## Pure logic (no nodes): only the CONTROLS are new — speed limits, traction (mud/snow/ruts/roads), cargo weight,
## limp, night, fuel, wear, crashes and winter starts all come from VehicleSystem, exactly as for an AI driver
## (the player has no driving skill: skill 0, i.e. a novice).
## Input is two axes: steer -1 (left) .. +1 (right), throttle -1 (brake/reverse) .. +1 (gas).

enum State { OFF, WARMUP, DRIVING }

var vs: VehicleSystem
var vehicle: Vehicle = null
var state := State.OFF
var speed := 0.0               ## signed m/s along the facing
var warm_left := 0.0           ## s of start/warm-up still to wait
var refusal_text := ""         ## why the last take() was refused
var event: StringName = &""    ## last event for the HUD: crashed | stuck | no_fuel | broken | blocked | &""


func _init(vs_in: VehicleSystem) -> void:
	vs = vs_in


func is_active() -> bool:
	return state != State.OFF


## "" if the player may take the wheel, else the reason (Russian, shown as a toast).
func refusal(v: Vehicle) -> String:
	if v == null or vs.get_vehicle(v.id) != v:
		return "Машины нет"
	if v.player_driving:
		return "Вы уже за рулём"
	if not v.is_repaired():
		return vs.status_text(v)
	if v.fuel <= 0.0:
		return "Нет топлива"
	return ""


## Takes the wheel. The AI driver (if any) steps out: his task fails, the cargo stays on board.
## Engine start rolls (frost, weak battery) can still refuse; otherwise a warm-up wait follows.
func take(v: Vehicle) -> bool:
	if is_active():
		leave()
	refusal_text = refusal(v)
	if refusal_text != "":
		return false
	var fails := vs.start_failures(v, null)
	if fails >= VehicleDefs.START_MAX_TRIES:
		refusal_text = "Двигатель не заводится"
		return false
	v.driver_id = 0
	v.mission = {}
	v.path.clear()
	v.moving = false
	v.player_driving = true
	vehicle = v
	speed = 0.0
	event = &""
	warm_left = vs.start_delay(v, null) + float(fails) * VehicleDefs.START_RETRY_DELAY
	state = State.WARMUP if warm_left > 0.0 else State.DRIVING
	if state == State.DRIVING:
		v.warm = 1.0
	vs._emit()
	return true


## Steps out: the vehicle is parked (AI may use it again); cargo goes to the storages like after a mission.
func leave() -> void:
	if vehicle != null:
		vehicle.player_driving = false
		vehicle.moving = false
		if vs.get_vehicle(vehicle.id) == vehicle:
			vs.release(vehicle)
		vs._emit()
	vehicle = null
	state = State.OFF
	speed = 0.0


## Km/h shown on the HUD.
func speed_kmh() -> float:
	return absf(speed) * ManualDriveDefs.KMH


## Top speed (m/s) here and now — the same function the AI uses.
func max_speed() -> float:
	return vs.speed_at(vehicle, vs.cell_idx(vehicle.pos), null)


func warmup_fraction() -> float:
	if state != State.WARMUP:
		return 1.0
	return clampf(1.0 - warm_left / maxf(0.001, vs.start_delay_full(vehicle)), 0.0, 1.0)


## One frame. Returns true while the player is still at the wheel.
func update(dt: float, steer: float, throttle: float) -> bool:
	if state == State.OFF:
		return false
	var v := vehicle
	if vs.get_vehicle(v.id) != v:
		vehicle = null  # the game was loaded / the vehicle vanished
		state = State.OFF
		speed = 0.0
		return false
	dt = minf(dt, ManualDriveDefs.MAX_FRAME_DT)
	steer = clampf(steer, -1.0, 1.0)
	throttle = clampf(throttle, -1.0, 1.0)
	if not v.is_repaired():
		_halt(v, &"broken")
		return true
	if state == State.WARMUP:
		warm_left -= dt
		v.warm = warmup_fraction()
		v.moving = false
		if warm_left <= 0.0:
			v.warm = 1.0
			state = State.DRIVING
		return true
	v.warm = 1.0
	if v.stuck_left > 0.0:
		v.stuck_left -= dt  # a novice: no skill relief
		_halt(v, &"stuck")
		return true
	if v.fuel <= 0.0:
		throttle = minf(throttle, 0.0)
		event = &"no_fuel"
	elif event == &"no_fuel" or event == &"stuck":
		event = &""
	_drive(v, dt, steer, throttle)
	return true


func _halt(v: Vehicle, why: StringName) -> void:
	speed = 0.0
	v.moving = false
	event = why


func _drive(v: Vehicle, dt: float, steer: float, throttle: float) -> void:
	var nominal := float(VehicleDefs.def(v.type)["speed"])
	var vmax := maxf(max_speed(), 0.0)
	var target := throttle * vmax if throttle >= 0.0 else throttle * vmax * ManualDriveDefs.REVERSE_FRAC
	var rate: float
	if throttle == 0.0:
		rate = nominal / ManualDriveDefs.COAST_TIME
	elif signf(target) != signf(speed) and absf(speed) > 0.01:
		rate = nominal / ManualDriveDefs.BRAKE_TIME
	elif absf(target) > absf(speed):
		rate = nominal / ManualDriveDefs.ACCEL_TIME / (1.0 + ManualDriveDefs.LOAD_ACCEL_PENALTY * v.load_frac())
	else:
		rate = nominal / ManualDriveDefs.BRAKE_TIME * 0.5
	speed = move_toward(speed, target, rate * dt)
	if absf(speed) < 0.001:
		speed = 0.0
		v.moving = false
		return
	# steering needs motion; reversing mirrors it
	var turn := steer * ManualDriveDefs.TURN_RATE * minf(1.0, absf(speed) / ManualDriveDefs.TURN_FULL_SPEED)
	v.facing = wrapf(v.facing - turn * dt * signf(speed), -PI, PI)
	var dist := absf(speed) * dt
	var np := v.pos + Vector3(sin(v.facing), 0.0, cos(v.facing)) * speed * dt
	if not vs.pf.is_passable(vs.world.cell_of(np.x, np.z)):
		_halt(v, &"blocked")
		return
	var from_idx := vs.cell_idx(v.pos)
	var y0 := v.pos.y
	v.pos.x = np.x
	v.pos.z = np.z
	v.pos.y = vs.world.height_at(np.x, np.z)
	v.moving = true
	if event == &"blocked":
		event = &""
	var was_ok := v.is_repaired()
	var rolls := v.accident_rolls
	vs.note_moved(v, from_idx, dist, null, absf(v.pos.y - y0) / maxf(dist, 0.001))
	if v.accident_rolls != rolls and v.stuck_left > 0.0:
		event = &"stuck"
	if not v.moving:  # crash() stops the vehicle
		speed = 0.0
		event = &"crashed"
	elif was_ok and not v.is_repaired():
		_halt(v, &"broken")
