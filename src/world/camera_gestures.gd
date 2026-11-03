class_name CameraGestures
extends RefCounted
## Чистая математика жестов камеры (без узлов и ввода) — легко тестируется.
## Точки — позиции пальцев в пикселях экрана (y вниз).


## Сдвиг центра жеста между кадрами (пиксели). Для одного пальца — просто его смещение.
static func pan_delta(before: Array, after: Array) -> Vector2:
	if before.is_empty() or before.size() != after.size():
		return Vector2.ZERO
	return _centroid(after) - _centroid(before)


## Знаковый поворот линии между двумя пальцами (радианы, по часовой на экране > 0, y вниз).
static func rotate_angle(before: Array, after: Array) -> float:
	if before.size() < 2 or after.size() < 2:
		return 0.0
	var a0: float = (before[1] - before[0]).angle()
	var a1: float = (after[1] - after[0]).angle()
	return angle_difference(a0, a1)


## Множитель дистанции камеры: пальцы разводятся (щипок наружу) -> < 1 (приближение).
static func zoom_factor(before: Array, after: Array) -> float:
	if before.size() < 2 or after.size() < 2:
		return 1.0
	var d0: float = (before[1] - before[0]).length()
	var d1: float = (after[1] - after[0]).length()
	if d0 < 1.0 or d1 < 1.0:
		return 1.0
	return d0 / d1


static func _centroid(pts: Array) -> Vector2:
	var s := Vector2.ZERO
	for p in pts:
		s += p
	return s / float(pts.size())
