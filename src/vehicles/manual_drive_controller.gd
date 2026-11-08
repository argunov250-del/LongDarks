class_name ManualDriveController
extends Node
## Step 21: wires ManualDrive to the scene — reads the chosen input scheme (+ WASD/arrows on desktop),
## steps ManualDrive every frame, drives the chase camera and the driving HUD.
## Design: design/gdd/manual-driving.md.

signal driving_changed(active: bool)

var vs: VehicleSystem
var md: ManualDrive
var rig: CameraRig
var hud: Hud
var settings: DriveSettings
var pad: DriveHud
var tilt := TiltScheme.new()
var kb := ButtonsScheme.new()
var accel_provider: Callable = func() -> Vector3: return Input.get_accelerometer()
var _scheme: StringName = &""
var _landscape := false


func setup(vs_in: VehicleSystem, rig_in: CameraRig, hud_in: Hud, settings_in: DriveSettings) -> void:
	vs = vs_in
	rig = rig_in
	hud = hud_in
	settings = settings_in
	md = ManualDrive.new(vs)
	tilt.set_neutral(settings.tilt_neutral)
	pad = DriveHud.new()
	pad.name = "DriveHud"
	hud.get_parent().add_child(pad)
	pad.exit_requested.connect(leave)
	pad.recalibrate_requested.connect(_recalibrate)
	set_process(true)


## "" = the player took the wheel, else the refusal reason (also shown as a toast).
func try_take(vehicle_id: int) -> String:
	var v := vs.get_vehicle(vehicle_id)
	if not md.take(v):
		hud.villagers_ui.show_toast(md.refusal_text)
		return md.refusal_text
	hud.set_driving(true)
	rig.set_chase(true)
	rig.chase_follow(v.pos, v.facing)
	pad.visible = true
	_scheme = &""
	_apply_layout()
	driving_changed.emit(true)
	return ""


func leave() -> void:
	var was := md.is_active()
	md.leave()
	_finish_ui(was)


func _finish_ui(was: bool) -> void:
	pad.release_all()
	pad.visible = false
	rig.set_chase(false)
	hud.set_driving(false)
	kb.reset()
	if was:
		driving_changed.emit(false)


func _recalibrate() -> void:
	tilt.calibrate()
	settings.tilt_neutral = tilt.neutral
	settings.save()


func _apply_layout() -> void:
	var vp := hud.get_viewport().get_visible_rect().size if hud.is_inside_tree() else Vector2(1080, 2400)
	pad.apply_layout(vp, hud.ui_scale(), hud.safe_insets(), settings.scheme)
	_scheme = settings.scheme
	_landscape = hud.mode == LayoutMode.Mode.LANDSCAPE


## Selected scheme + keyboard fallback -> Vector2(steer, throttle).
func read_input(dt: float) -> Vector2:
	kb.left = Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
	kb.right = Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
	kb.gas = Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	kb.brake = Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
	var a := Vector2.ZERO
	match settings.scheme:
		ManualDriveDefs.SCHEME_JOYSTICK:
			a = pad.joystick.axes()
		ManualDriveDefs.SCHEME_BUTTONS:
			a = pad.buttons.axes()
		ManualDriveDefs.SCHEME_TILT:
			tilt.feed(accel_provider.call(), dt)
			a = tilt.axes()
	return DriveScheme.merge(a, kb.axes())


func _process(dt: float) -> void:
	if md == null or not md.is_active():
		return
	if settings.scheme != _scheme or (hud.mode == LayoutMode.Mode.LANDSCAPE) != _landscape:
		tilt.landscape = hud.mode == LayoutMode.Mode.LANDSCAPE
		if tilt.landscape != _landscape:
			tilt.neutral = Vector3.ZERO  # axes were remapped: the old neutral pose is meaningless
		_apply_layout()
	var input := read_input(dt)
	var v := md.vehicle
	if not md.update(dt, input.x, input.y):
		_finish_ui(true)  # the game was loaded / the vehicle vanished
		return
	rig.chase_follow(v.pos, v.facing)
	pad.show_state(md.speed_kmh(), v.fuel, v.tank(), status_text())


func status_text() -> String:
	if md.state == ManualDrive.State.WARMUP:
		return "Прогрев: %d с" % ceili(md.warm_left)
	match md.event:
		&"crashed":
			return "Авария!"
		&"stuck":
			return "Застряли"
		&"no_fuel":
			return "Нет топлива"
		&"broken":
			return "Сломана"
	return ""
