class_name DriveScheme
extends RefCounted
## Base of the manual-driving input schemes (pure logic, no nodes). Both axes are -1..1:
## steer: -1 left .. +1 right; throttle: -1 brake/reverse .. +1 gas.

func steer() -> float:
	return 0.0


func throttle() -> float:
	return 0.0


func axes() -> Vector2:
	return Vector2(steer(), throttle())


## Drops all held input (screen left, scheme switched, wheel left).
func reset() -> void:
	pass


## Sum of two inputs (selected scheme + keyboard fallback), clamped to the valid range.
static func merge(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(clampf(a.x + b.x, -1.0, 1.0), clampf(a.y + b.y, -1.0, 1.0))
