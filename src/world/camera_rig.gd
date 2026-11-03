class_name CameraRig
extends Node3D
## RTS-камера на опорной точке (pivot) на земле: yaw, дистанция, тангаж из дистанции.
## Тач: 1 палец — пан (земля следует за пальцем), 2 пальца — поворот + зум одновременно.
## Десктоп (dev): ЛКМ-драг — пан, ПКМ-драг — поворот, колесо — зум, WASD/QE.
## Ввод только через _unhandled_input: жесты, начатые на UI, сюда не попадают.
## Состояние (pivot, yaw, distance) сохраняется через SimSystem-хуки (см. CameraSave).

const MIN_DISTANCE := 5.0        ## «сесть за руль» — позже, пока константа
const MAX_DISTANCE := 160.0
const PITCH_NEAR_DEG := 14.0     ## близко — низкий угол
const PITCH_FAR_DEG := 62.0      ## далеко — почти сверху
const TERRAIN_CLEARANCE := 1.5
const SMOOTHING := 14.0          ## 1/сек, экспоненциальное сглаживание
const FLING_DECAY := 4.0         ## 1/сек
const FLING_MIN_SPEED := 0.5     ## м/с
const KEY_PAN_SPEED := 0.9       ## дистанций в секунду
const KEY_ROT_SPEED := 1.6
const WHEEL_STEP := 0.88

var world_map: WorldMap
var camera: Camera3D

# Целевое состояние (сохраняется) и отображаемое (сглаженное).
var target_pivot := Vector3.ZERO   ## x,z значимы; y считается по рельефу
var target_yaw := 0.0
var target_distance := 80.0
var _pivot := Vector3.ZERO
var _yaw := 0.0
var _distance := 80.0

var _touches := {}                 ## index -> Vector2
var _fling := Vector3.ZERO         ## м/с в мире (xz)
var _drag_vel := Vector3.ZERO
var _mouse_pan := false
var _mouse_rot := false

var save_system := CameraSave.new(self)


class CameraSave extends SimSystem:
	var rig: CameraRig

	func _init(r: CameraRig) -> void:
		rig = r

	func get_save_key() -> StringName:
		return &"camera"

	func save_state() -> Dictionary:
		return {"px": rig.target_pivot.x, "pz": rig.target_pivot.z, "yaw": rig.target_yaw, "dist": rig.target_distance}

	func load_state(d: Dictionary) -> void:
		rig.set_state(Vector3(float(d.get("px", 0.0)), 0.0, float(d.get("pz", 0.0))), float(d.get("yaw", 0.0)), float(d.get("dist", 80.0)), true)


# ---------- чистые функции ----------

static func clamp_distance(d: float) -> float:
	return clampf(d, MIN_DISTANCE, MAX_DISTANCE)


## Тангаж (радианы): ближе — ниже угол, дальше — выше.
static func pitch_for_distance(d: float) -> float:
	var t := inverse_lerp(MIN_DISTANCE, MAX_DISTANCE, clamp_distance(d))
	return deg_to_rad(lerpf(PITCH_NEAR_DEG, PITCH_FAR_DEG, t))


static func clamp_pivot(p: Vector3, bounds: Rect2) -> Vector3:
	return Vector3(clampf(p.x, bounds.position.x, bounds.end.x), p.y, clampf(p.z, bounds.position.y, bounds.end.y))


## Позиция камеры; не ниже рельефа + зазор.
static func camera_position(pivot: Vector3, yaw: float, dist: float, map: WorldMap) -> Vector3:
	var pitch := pitch_for_distance(dist)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	var pos := pivot + off
	if map != null:
		pos.y = maxf(pos.y, map.height_at(pos.x, pos.z) + TERRAIN_CLEARANCE)
	return pos


# ---------- состояние ----------

func setup(map: WorldMap, cam: Camera3D) -> void:
	world_map = map
	camera = cam
	var ws := map.get_world_size()
	set_state(Vector3(ws * 0.5, 0.0, ws * 0.5), 0.0, ws * 0.6, true)


## snap=true — без сглаживания.
func set_state(pivot: Vector3, yaw: float, dist: float, snap: bool = false) -> void:
	target_pivot = _clamped(pivot)
	target_yaw = yaw
	target_distance = clamp_distance(dist)
	_fling = Vector3.ZERO
	if snap:
		_pivot = target_pivot
		_yaw = target_yaw
		_distance = target_distance
		_apply()


func _clamped(p: Vector3) -> Vector3:
	if world_map == null:
		return p
	p = clamp_pivot(p, world_map.get_bounds())
	p.y = world_map.height_at(p.x, p.z)
	return p


func pan_pixels(delta: Vector2) -> void:
	var s := _world_per_pixel()
	var right := Vector3(cos(target_yaw), 0.0, -sin(target_yaw))
	var back := Vector3(sin(target_yaw), 0.0, cos(target_yaw))
	var k := 1.0 / maxf(sin(pitch_for_distance(target_distance)), 0.25)
	target_pivot = _clamped(target_pivot - (right * delta.x + back * delta.y * k) * s)


func rotate_by(angle: float) -> void:
	target_yaw += angle


func zoom_by(factor: float) -> void:
	target_distance = clamp_distance(target_distance * factor)


func _world_per_pixel() -> float:
	var vp := get_viewport()
	var size := vp.get_visible_rect().size if vp != null else Vector2(1080, 1920)
	var fov := camera.fov if camera != null else 55.0
	var keep_h: bool = camera != null and camera.keep_aspect == Camera3D.KEEP_HEIGHT
	var px := size.y if keep_h else size.x
	return 2.0 * target_distance * tan(deg_to_rad(fov) * 0.5) / maxf(px, 1.0)


# ---------- кадр ----------

## Продвигает сглаживание/инерцию на dt (вызывается из _process; доступно тестам).
func update(dt: float) -> void:
	if _touches.is_empty() and not _mouse_pan and _fling.length() > FLING_MIN_SPEED:
		target_pivot = _clamped(target_pivot + _fling * dt)
		_fling *= exp(-FLING_DECAY * dt)
	elif _touches.is_empty() and not _mouse_pan:
		_fling = Vector3.ZERO
	var k := 1.0 - exp(-SMOOTHING * dt)
	_pivot = _pivot.lerp(target_pivot, k)
	_yaw = lerp_angle(_yaw, target_yaw, k)
	_distance = lerpf(_distance, target_distance, k)
	_apply()


func _apply() -> void:
	var piv := _pivot
	if world_map != null:
		piv.y = world_map.height_at(piv.x, piv.z)
	position = piv
	if camera == null or not camera.is_inside_tree():
		return
	var pos := camera_position(piv, _yaw, _distance, world_map)
	camera.global_position = pos
	camera.look_at(piv, Vector3.UP)


func _ready() -> void:
	if camera == null:
		camera = get_node_or_null("Camera3D")
	set_process(true)


func _process(dt: float) -> void:
	_keyboard(dt)
	update(dt)


func _keyboard(dt: float) -> void:
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_A): mv.x -= 1
	if Input.is_key_pressed(KEY_D): mv.x += 1
	if Input.is_key_pressed(KEY_W): mv.y -= 1
	if Input.is_key_pressed(KEY_S): mv.y += 1
	if mv != Vector2.ZERO:
		var right := Vector3(cos(target_yaw), 0.0, -sin(target_yaw))
		var back := Vector3(sin(target_yaw), 0.0, cos(target_yaw))
		target_pivot = _clamped(target_pivot + (right * mv.x + back * mv.y) * KEY_PAN_SPEED * target_distance * dt)
		_fling = Vector3.ZERO
	var r := 0.0
	if Input.is_key_pressed(KEY_Q): r -= 1
	if Input.is_key_pressed(KEY_E): r += 1
	if r != 0.0:
		target_yaw += r * KEY_ROT_SPEED * dt


# ---------- ввод ----------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
			_fling = Vector3.ZERO
			_drag_vel = Vector3.ZERO
		else:
			if _touches.has(t.index):
				_touches.erase(t.index)
				if _touches.is_empty():
					_fling = _drag_vel
				_drag_vel = Vector3.ZERO
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _touches.has(d.index):
			_on_touch_drag(d)
	elif event is InputEventMouseButton and _touches.is_empty():
		var m := event as InputEventMouseButton
		match m.button_index:
			MOUSE_BUTTON_LEFT:
				_mouse_pan = m.pressed
				if m.pressed:
					_fling = Vector3.ZERO
				else:
					_fling = _drag_vel
					_drag_vel = Vector3.ZERO
			MOUSE_BUTTON_RIGHT:
				_mouse_rot = m.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if m.pressed: zoom_by(WHEEL_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if m.pressed: zoom_by(1.0 / WHEEL_STEP)
	elif event is InputEventMouseMotion and _touches.is_empty():
		var mm := event as InputEventMouseMotion
		if _mouse_pan:
			_pan_with_velocity(mm.relative)
		elif _mouse_rot:
			rotate_by(mm.relative.x * 0.006)


func _on_touch_drag(d: InputEventScreenDrag) -> void:
	var before := _touches.values()
	_touches[d.index] = d.position
	var after := _touches.values()
	if _touches.size() == 1:
		_pan_with_velocity(CameraGestures.pan_delta(before, after))
	elif _touches.size() >= 2:
		var b2 := before.slice(0, 2)
		var a2 := after.slice(0, 2)
		rotate_by(CameraGestures.rotate_angle(b2, a2))
		zoom_by(CameraGestures.zoom_factor(b2, a2))
		pan_pixels(CameraGestures.pan_delta(b2, a2))


func _pan_with_velocity(px: Vector2) -> void:
	var before := target_pivot
	pan_pixels(px)
	var dt := maxf(get_process_delta_time(), 0.001)
	var v := (target_pivot - before) / dt
	v.y = 0.0
	_drag_vel = _drag_vel.lerp(v, 0.5)
