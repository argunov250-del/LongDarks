class_name TiltScheme
extends DriveScheme
## Phone tilt: roll steers, pitch = gas/brake, relative to a calibrated neutral pose with a dead zone.
## Input is the raw Input.get_accelerometer() vector (device axes; unverified on hardware -> signs in ManualDriveDefs).
## `landscape` remaps the device axes to screen axes (assumption, to be checked on a phone).

var landscape := false
var dead_deg := ManualDriveDefs.TILT_DEAD_DEG
var steer_full_deg := ManualDriveDefs.TILT_STEER_FULL_DEG
var throttle_full_deg := ManualDriveDefs.TILT_THROTTLE_FULL_DEG
var neutral := Vector3.ZERO            # Vector3.ZERO = not calibrated yet (first sample becomes the neutral)
var _smooth := Vector3.ZERO
var _has_sample := false
var _roll := 0.0                       # deg relative to neutral
var _pitch := 0.0


func is_calibrated() -> bool:
	return neutral != Vector3.ZERO


## Feeds one accelerometer sample; dt smooths it (dt <= 0 = no smoothing, tests).
func feed(accel: Vector3, dt: float = 0.0) -> void:
	var a := _to_screen(accel)
	if not _has_sample or dt <= 0.0:
		_smooth = a
	else:
		_smooth = _smooth.lerp(a, 1.0 - exp(-ManualDriveDefs.TILT_SMOOTH * dt))
	_has_sample = true
	if not is_calibrated():
		calibrate()
	_recompute()


## Current pose becomes the neutral one.
func calibrate() -> void:
	if _has_sample:
		neutral = _smooth
		_recompute()


func set_neutral(n: Vector3) -> void:
	neutral = n
	_recompute()


func _to_screen(a: Vector3) -> Vector3:
	return Vector3(a.y, -a.x, a.z) if landscape else a


## Roll (about the screen's vertical axis) and pitch (about its horizontal axis), degrees.
static func angles(a: Vector3) -> Vector2:
	return Vector2(rad_to_deg(atan2(a.x, sqrt(a.y * a.y + a.z * a.z))), rad_to_deg(atan2(a.z, a.y)))


func _recompute() -> void:
	if not _has_sample or not is_calibrated():
		_roll = 0.0
		_pitch = 0.0
		return
	var cur := angles(_smooth)
	var ref := angles(neutral)
	_roll = cur.x - ref.x
	_pitch = wrapf(cur.y - ref.y, -180.0, 180.0)


func _axis(deg: float, full: float) -> float:
	var m := absf(deg)
	if m <= dead_deg:
		return 0.0
	return signf(deg) * clampf((m - dead_deg) / maxf(full - dead_deg, 0.001), 0.0, 1.0)


func steer() -> float:
	return _axis(_roll, steer_full_deg) * ManualDriveDefs.TILT_STEER_SIGN


func throttle() -> float:
	return _axis(_pitch, throttle_full_deg) * ManualDriveDefs.TILT_THROTTLE_SIGN


func reset() -> void:
	_has_sample = false
	_roll = 0.0
	_pitch = 0.0
