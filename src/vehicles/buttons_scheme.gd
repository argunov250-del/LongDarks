class_name ButtonsScheme
extends DriveScheme
## On-screen buttons (gas/brake/left/right). Also used for the WASD/arrows desktop fallback.

var gas := false
var brake := false
var left := false
var right := false


func steer() -> float:
	return (1.0 if right else 0.0) - (1.0 if left else 0.0)


func throttle() -> float:
	return (1.0 if gas else 0.0) - (1.0 if brake else 0.0)


func reset() -> void:
	gas = false
	brake = false
	left = false
	right = false
