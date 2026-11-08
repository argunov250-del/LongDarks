class_name JoystickScheme
extends DriveScheme
## Virtual joystick: x = steering, up = gas, down = brake/reverse. Radial dead zone, rescaled outside it.

var dead := ManualDriveDefs.STICK_DEAD
var _v := Vector2.ZERO


## `v` = thumb offset from the centre in radius units, screen coordinates (y down).
func set_stick(v: Vector2) -> void:
	var m := v.length()
	if m <= dead:
		_v = Vector2.ZERO
		return
	_v = v / m * clampf((m - dead) / (1.0 - dead), 0.0, 1.0)


func steer() -> float:
	return _v.x


func throttle() -> float:
	return -_v.y


func reset() -> void:
	_v = Vector2.ZERO
