class_name Pathfinder
extends RefCounted
## Поиск пути по клеткам карты: A* (AStarGrid2D) в 8 направлениях без срезания
## углов, вода — непроходимая. Путь сглаживается по линии видимости и кэшируется
## по паре (клетка старта, клетка цели). Карта статична (вода не меняется).

const CACHE_MAX := 4096
const LOS_STEP := 0.25   # шаг проверки луча, клеток

var world: WorldMap
var _grid: AStarGrid2D
var _sig := ""
var _cache: Dictionary = {}   # int ключ -> Array[Vector2i] (пустой — недостижимо)


func _init(world_in: WorldMap) -> void:
	world = world_in


func _ensure() -> void:
	var sig := "%d:%d:%f" % [world.seed_value, world.size, world.cell_size]
	if _grid != null and sig == _sig:
		return
	_sig = sig
	_cache.clear()
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, world.size, world.size)
	_grid.cell_size = Vector2.ONE
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()
	for cz in world.size:
		for cx in world.size:
			if not _walkable(cx, cz):
				_grid.set_point_solid(Vector2i(cx, cz), true)


func _walkable(cx: int, cz: int) -> bool:
	return not WorldMap.is_water_type(world.cell_type(cx, cz))


func is_walkable_cell(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < world.size and c.y < world.size and _walkable(c.x, c.y)


func is_walkable(p: Vector3) -> bool:
	return is_walkable_cell(world.cell_of(p.x, p.z))


## Ближайшая проходимая клетка (кольцами); возвращает центр клетки.
func nearest_walkable(p: Vector3) -> Vector3:
	var c := world.cell_of(p.x, p.z)
	if is_walkable_cell(c):
		return p
	for r in range(1, world.size):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var n := c + Vector2i(dx, dz)
				if is_walkable_cell(n):
					return world.cell_center(n.x, n.y)
	return p


## Путь от from до to: точки (центры клеток, последняя — точная цель). Пусто — недостижимо.
func find_path(from: Vector3, to: Vector3) -> Array[Vector3]:
	_ensure()
	var a := world.cell_of(from.x, from.z)
	var b := world.cell_of(to.x, to.z)
	var out: Array[Vector3] = []
	if not is_walkable_cell(a) or not is_walkable_cell(b):
		return out
	if a == b:
		out.append(Vector3(to.x, world.height_at(to.x, to.z), to.z))
		return out
	var key := (a.y * world.size + a.x) * world.size * world.size + b.y * world.size + b.x
	var cells: Array
	if _cache.has(key):
		cells = _cache[key]
	else:
		cells = _smooth(_grid.get_id_path(a, b))
		if _cache.size() >= CACHE_MAX:
			_cache.clear()
		_cache[key] = cells
	if cells.is_empty():
		return out
	for i in cells.size() - 1:
		var c: Vector2i = cells[i + 1]
		var cc := world.cell_center(c.x, c.y)
		out.append(cc)
	# последняя точка — точная цель
	if out.is_empty():
		out.append(Vector3(to.x, world.height_at(to.x, to.z), to.z))
	else:
		out[out.size() - 1] = Vector3(to.x, world.height_at(to.x, to.z), to.z)
	return out


func cache_size() -> int:
	return _cache.size()


## Прямая между центрами клеток не пересекает воду.
func line_clear(a: Vector2i, b: Vector2i) -> bool:
	var pa := Vector2(a.x + 0.5, a.y + 0.5)
	var pb := Vector2(b.x + 0.5, b.y + 0.5)
	var n := maxi(1, int(pa.distance_to(pb) / LOS_STEP))
	for i in n + 1:
		var q := pa.lerp(pb, float(i) / n)
		if not is_walkable_cell(Vector2i(int(floorf(q.x)), int(floorf(q.y)))):
			return false
	return true


func _smooth(ids: Array[Vector2i]) -> Array:
	if ids.size() <= 2:
		return ids
	var out: Array = [ids[0]]
	var i := 0
	while i < ids.size() - 1:
		var j := ids.size() - 1
		while j > i + 1 and not line_clear(ids[i], ids[j]):
			j -= 1
		out.append(ids[j])
		i = j
	return out
