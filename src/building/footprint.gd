class_name Footprint
extends RefCounted
## Ориентированный прямоугольник на плоскости XZ (чистая геометрия).
## Поворот rot — рыскание вокруг Y, как у Node3D.rotation.y:
## локальная ось X -> (cos r, -sin r), локальная ось Z -> (sin r, cos r).

static func axis_u(rot: float) -> Vector2:
	return Vector2(cos(rot), -sin(rot))


static func axis_v(rot: float) -> Vector2:
	return Vector2(sin(rot), cos(rot))


## Четыре угла (xz) прямоугольника size=(ширина по X, глубина по Z).
static func corners(center: Vector2, size: Vector2, rot: float) -> Array[Vector2]:
	var u := axis_u(rot) * (size.x * 0.5)
	var v := axis_v(rot) * (size.y * 0.5)
	return [center - u - v, center + u - v, center + u + v, center - u + v]


## Точка внутри прямоугольника (с запасом margin).
static func contains(center: Vector2, size: Vector2, rot: float, p: Vector2, margin: float = 0.0) -> bool:
	var d := p - center
	return absf(d.dot(axis_u(rot))) <= size.x * 0.5 + margin and absf(d.dot(axis_v(rot))) <= size.y * 0.5 + margin


## Пересечение двух ориентированных прямоугольников (SAT); gap — обязательный зазор.
static func overlaps(c1: Vector2, s1: Vector2, r1: float, c2: Vector2, s2: Vector2, r2: float, gap: float = 0.0) -> bool:
	var axes: Array[Vector2] = [axis_u(r1), axis_v(r1), axis_u(r2), axis_v(r2)]
	var d := c2 - c1
	for a in axes:
		var ra := _radius(s1, r1, a)
		var rb := _radius(s2, r2, a)
		if absf(d.dot(a)) >= ra + rb + gap:
			return false
	return true


static func _radius(size: Vector2, rot: float, axis: Vector2) -> float:
	return absf(axis_u(rot).dot(axis)) * size.x * 0.5 + absf(axis_v(rot).dot(axis)) * size.y * 0.5


## Локальная точка (оси здания) -> мировая XZ.
static func local_to_world(center: Vector2, rot: float, local: Vector2) -> Vector2:
	return center + axis_u(rot) * local.x + axis_v(rot) * local.y
