class_name Pathfinder
extends RefCounted
## Поиск пути по клеткам карты: A* (AStarGrid2D) в 8 направлениях без срезания
## углов, вода — непроходимая. Путь сглаживается по линии видимости и кэшируется
## по паре (клетка старта, клетка цели). Карта статична (вода не меняется).

const CACHE_MAX := 4096

var world: WorldMap
var _grid: AStarGrid2D
var _sig := ""
## Временно непроходимые клетки (паводок): индекс клетки -> true. Меняется set_blocked_cells.
var blocked: Dictionary = {}
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
			if not _walkable(cx, cz) or blocked.has(cz * world.size + cx):
				_grid.set_point_solid(Vector2i(cx, cz), true)


func _walkable(cx: int, cz: int) -> bool:
	return not WorldMap.is_water_type(world.cell_type(cx, cz))


## Задаёт временно закрытые клетки (индекс -> true); кэш путей сбрасывается.
func set_blocked_cells(cells: Dictionary) -> void:
	if _grid != null:
		for i in blocked:
			if not cells.has(i):
				var c := Vector2i(i % world.size, i / world.size)
				_grid.set_point_solid(c, not _walkable(c.x, c.y))
		for i in cells:
			_grid.set_point_solid(Vector2i(i % world.size, i / world.size), true)
	blocked = cells.duplicate()
	_cache.clear()


func is_walkable_cell(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < world.size and c.y < world.size and _walkable(c.x, c.y) and not blocked.has(c.y * world.size + c.x)


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


## Прямая между центрами клеток не пересекает воду (обход клеток DDA; при прохождении
## ровно через угол проверяются обе соседние клетки).
func line_clear(a: Vector2i, b: Vector2i) -> bool:
	var dx := float(b.x - a.x)
	var dy := float(b.y - a.y)
	var cx := a.x
	var cy := a.y
	var sx := 1 if dx > 0.0 else -1
	var sy := 1 if dy > 0.0 else -1
	var tdx := INF if dx == 0.0 else absf(1.0 / dx)
	var tdy := INF if dy == 0.0 else absf(1.0 / dy)
	var tmx := INF if dx == 0.0 else 0.5 * tdx
	var tmy := INF if dy == 0.0 else 0.5 * tdy
	if not is_walkable_cell(a):
		return false
	var guard := absi(b.x - a.x) + absi(b.y - a.y) + 2
	while (cx != b.x or cy != b.y) and guard > 0:
		guard -= 1
		if absf(tmx - tmy) < 0.000001:
			if not is_walkable_cell(Vector2i(cx + sx, cy)) or not is_walkable_cell(Vector2i(cx, cy + sy)):
				return false
			cx += sx
			cy += sy
			tmx += tdx
			tmy += tdy
		elif tmx < tmy:
			cx += sx
			tmx += tdx
		else:
			cy += sy
			tmy += tdy
		if not is_walkable_cell(Vector2i(cx, cy)):
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
