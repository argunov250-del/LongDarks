class_name DriveHud
extends Control
## Step 21: driving screen — speed (km/h), fuel, exit button and the touch controls of the chosen scheme
## (joystick / buttons; tilt needs none). Multi-touch via raw InputEventScreenTouch/Drag.
## Pure layout: compute_layout(). Design: design/gdd/manual-driving.md.

signal exit_requested
signal recalibrate_requested

var joystick := JoystickScheme.new()
var buttons := ButtonsScheme.new()
var scheme: StringName = ManualDriveDefs.SCHEME_JOYSTICK
var speed_label: Label
var fuel_label: Label
var status_label: Label
var exit_button: Button
var calib_button: Button
var regions: Dictionary = {}          # name -> Rect2 (joystick, left, right, gas, brake)
var _dp := 2.6
var _stick_idx := -999
var _touch_region: Dictionary = {}    # touch index -> region name
var _stick_vec := Vector2.ZERO


## Rects of the controls for a viewport; insets = Hud.safe_insets(). Everything stays inside the screen.
static func compute_layout(vp: Vector2, dp: float, insets: Dictionary, scheme_id: StringName) -> Dictionary:
	var edge := 8.0 * dp
	var l: float = insets["left"] + edge
	var r: float = insets["right"] + edge
	var tp: float = insets["top"] + edge
	var bt: float = insets["bottom"] + edge
	var out := {}
	var touch := 48.0 * dp
	out["exit"] = Rect2(vp.x - r - 110.0 * dp, tp + touch + 2.0 * edge, 110.0 * dp, touch)
	out["calib"] = Rect2(vp.x - r - 170.0 * dp, tp + 2.0 * touch + 3.0 * edge, 170.0 * dp, touch)
	out["info"] = Rect2(l, tp + touch + 2.0 * edge, minf(220.0 * dp, vp.x * 0.5), 3.0 * touch)
	if scheme_id == ManualDriveDefs.SCHEME_JOYSTICK:
		var R := 62.0 * dp
		out["joystick"] = Rect2(l, vp.y - bt - 2.0 * R - 12.0 * dp, 2.0 * R, 2.0 * R)
	elif scheme_id == ManualDriveDefs.SCHEME_BUTTONS:
		var b := 84.0 * dp
		var g := 10.0 * dp
		out["left"] = Rect2(l, vp.y - bt - b, b, b)
		out["right"] = Rect2(l + b + g, vp.y - bt - b, b, b)
		out["gas"] = Rect2(vp.x - r - b, vp.y - bt - 2.0 * b - g, b, b)
		out["brake"] = Rect2(vp.x - r - b, vp.y - bt - b, b, b * 0.9)
	return out


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var info := VBoxContainer.new()
	info.name = "Info"
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info)
	speed_label = Label.new()
	fuel_label = Label.new()
	status_label = Label.new()
	for lb in [speed_label, fuel_label, status_label]:
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		lb.add_theme_constant_override("outline_size", 6)
		info.add_child(lb)
	exit_button = Button.new()
	exit_button.text = "Выйти"
	exit_button.focus_mode = Control.FOCUS_NONE
	exit_button.pressed.connect(func(): exit_requested.emit())
	add_child(exit_button)
	calib_button = Button.new()
	calib_button.text = "Обнулить наклон"
	calib_button.focus_mode = Control.FOCUS_NONE
	calib_button.pressed.connect(func(): recalibrate_requested.emit())
	add_child(calib_button)
	visible = false


## Re-lays out for the viewport (portrait/landscape/safe area) and the chosen scheme.
func apply_layout(vp: Vector2, dp: float, insets: Dictionary, scheme_id: StringName) -> void:
	_dp = dp
	if scheme_id != scheme:
		release_all()
	scheme = scheme_id
	regions = compute_layout(vp, dp, insets, scheme_id)
	var fs := roundi(15.0 * dp)
	for lb in [speed_label, fuel_label, status_label]:
		lb.add_theme_font_size_override("font_size", fs)
	speed_label.add_theme_font_size_override("font_size", roundi(26.0 * dp))
	var ir: Rect2 = regions["info"]
	var info := get_node("Info") as Control
	info.position = ir.position
	info.size = ir.size
	for pair in [[exit_button, "exit"], [calib_button, "calib"]]:
		var rr: Rect2 = regions[pair[1]]
		(pair[0] as Control).position = rr.position
		(pair[0] as Control).size = rr.size
		(pair[0] as Button).add_theme_font_size_override("font_size", fs)
	calib_button.visible = scheme == ManualDriveDefs.SCHEME_TILT
	queue_redraw()


## Text of the readout (set by the controller each frame).
func show_state(kmh: float, fuel: float, tank: float, status: String) -> void:
	speed_label.text = "%d км/ч" % roundi(kmh)
	fuel_label.text = "Топливо: %d/%d л" % [roundi(fuel), roundi(tank)]
	status_label.text = status
	status_label.visible = status != ""


## Drops every held touch (scheme switch, exit, focus lost): no stuck gas.
func release_all() -> void:
	_touch_region.clear()
	_stick_idx = -999
	_stick_vec = Vector2.ZERO
	joystick.reset()
	buttons.reset()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
		release_all()


func _region_at(p: Vector2) -> String:
	for k in regions:
		if k in ["joystick", "left", "right", "gas", "brake"] and (regions[k] as Rect2).has_point(p):
			return k
	return ""


func _press(idx: int, p: Vector2) -> void:
	var k := _region_at(p)
	if k == "":
		return
	_touch_region[idx] = k
	if k == "joystick":
		_stick_idx = idx
		_drag(idx, p)
	else:
		_sync_buttons()


func _drag(idx: int, p: Vector2) -> void:
	if idx != _stick_idx or not regions.has("joystick"):
		return
	var rr: Rect2 = regions["joystick"]
	var R := rr.size.x * 0.5
	_stick_vec = ((p - rr.get_center()) / R).limit_length(1.0)
	joystick.set_stick(_stick_vec)
	queue_redraw()


func _release(idx: int) -> void:
	if not _touch_region.has(idx):
		return
	_touch_region.erase(idx)
	if idx == _stick_idx:
		_stick_idx = -999
		_stick_vec = Vector2.ZERO
		joystick.reset()
	_sync_buttons()
	queue_redraw()


func _sync_buttons() -> void:
	var held := _touch_region.values()
	buttons.gas = held.has("gas")
	buttons.brake = held.has("brake")
	buttons.left = held.has("left")
	buttons.right = held.has("right")
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
	elif not OS.has_feature("mobile"):  # desktop: the mouse acts as one finger
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press(99, event.position)
			else:
				_release(99)
		elif event is InputEventMouseMotion and _touch_region.has(99):
			_drag(99, event.position)


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := roundi(16.0 * _dp)
	var base := Color(0.1, 0.1, 0.1, 0.35)
	var lit := Color(0.9, 0.9, 0.9, 0.5)
	if regions.has("joystick"):
		var rr: Rect2 = regions["joystick"]
		var R := rr.size.x * 0.5
		draw_circle(rr.get_center(), R, base)
		draw_arc(rr.get_center(), R, 0.0, TAU, 48, lit, 3.0)
		draw_circle(rr.get_center() + _stick_vec * R * 0.8, R * 0.38, lit)
	for k in ["left", "right", "gas", "brake"]:
		if not regions.has(k):
			continue
		var on: bool = buttons.get(k)
		var rr: Rect2 = regions[k]
		draw_rect(rr, lit if on else base, true)
		draw_rect(rr, Color(0.9, 0.9, 0.9, 0.6), false, 3.0)
		var txt: String = {"left": "Влево", "right": "Вправо", "gas": "Газ", "brake": "Тормоз"}[k]
		draw_string(font, rr.position + Vector2(0.0, rr.size.y * 0.5 + fs * 0.35), txt, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, fs, Color.WHITE)
