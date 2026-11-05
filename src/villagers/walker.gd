class_name Walker
extends RefCounted
## Существо, идущее по рельефу вдоль пути (жители, собака). Путь строит Pathfinder.

var pos := Vector3.ZERO
var path: Array[Vector3] = []     # оставшиеся точки (не сохраняется — пересчитывается)
var path_goal := Vector2i(-1, -1) # клетка цели, для которой построен путь
var facing := 0.0                 # рыскание (рад), как Node3D.rotation.y
var moving := false


## Двигается на speed*dt вдоль пути; y — по рельефу.
func advance_along(dt: float, speed: float, world: WorldMap) -> void:
	var budget := speed * dt
	moving = false
	while budget > 0.0 and not path.is_empty():
		var t := path[0]
		var d := Vector2(t.x - pos.x, t.z - pos.z)
		var len := d.length()
		if len <= budget:
			pos.x = t.x
			pos.z = t.z
			path.pop_front()
			budget -= len
			if len > 0.001:
				facing = atan2(d.x, d.y)
			moving = true
		else:
			var step := d / len * budget
			pos.x += step.x
			pos.z += step.y
			facing = atan2(d.x, d.y)
			budget = 0.0
			moving = true
	pos.y = world.height_at(pos.x, pos.z)
