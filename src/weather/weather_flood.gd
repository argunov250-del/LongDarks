class_name WeatherFlood
extends RefCounted
## Паводок (шаг 14): временное затопление суши у рек и озёр. Множество flooded — клетки под водой
## (индекс клетки -> true); НЕ сохраняется, а пересчитывается из уровня воды (WeatherDefs.flood_level).
## Клетка затоплена, если это суша (GROUND/FOREST), не дальше reach клеток (4-связность) от воды,
## её средняя высота ниже WATER_LEVEL + level и она связана с водой цепочкой таких же клеток.

var world: WorldMap
var reach: int = WeatherDefs.FLOOD_REACH_CELLS
var level: float = 0.0
var flooded: Dictionary = {}     # int индекс клетки -> true
var revision: int = 0

var _near: Array[int] = []       # суша не дальше reach от воды, в порядке удаления от воды (BFS)
var _dist: Dictionary = {}       # индекс -> расстояние от воды (1..reach)
var _avg_h: Dictionary = {}      # индекс -> средняя высота клетки
var _built_sig := ""


func _init(world_in: WorldMap = null) -> void:
	world = world_in


func _idx(c: Vector2i) -> int:
	return c.y * world.size + c.x


func _build_near() -> void:
	var sig := "%d:%d:%d" % [world.seed_value, world.size, reach]
	if sig == _built_sig:
		return
	_built_sig = sig
	_near.clear()
	_dist.clear()
	_avg_h.clear()
	var n := world.size
	var queue: Array[Vector2i] = []
	var seen := {}
	for cz in n:
		for cx in n:
			if WorldMap.is_water_type(world.cell_type(cx, cz)):
				seen[cz * n + cx] = 0
				queue.append(Vector2i(cx, cz))
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var d: int = seen[_idx(c)]
		if d >= reach:
			continue
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: Vector2i = c + off
			if nc.x < 0 or nc.y < 0 or nc.x >= n or nc.y >= n:
				continue
			var i := _idx(nc)
			if seen.has(i):
				continue
			seen[i] = d + 1
			queue.append(nc)
			_near.append(i)
			_dist[i] = d + 1
			_avg_h[i] = (world.node_height(nc.x, nc.y) + world.node_height(nc.x + 1, nc.y) + world.node_height(nc.x, nc.y + 1) + world.node_height(nc.x + 1, nc.y + 1)) * 0.25


func is_flooded(c: Vector2i) -> bool:
	return flooded.has(_idx(c))


func flooded_count() -> int:
	return flooded.size()


## Ставит уровень воды (м над WATER_LEVEL) и пересчитывает затопление. true — множество изменилось.
func set_level(new_level: float) -> bool:
	level = maxf(0.0, new_level)
	_build_near()
	var now := {}
	if level > 0.0:
		for i in _near:
			var c := Vector2i(i % world.size, i / world.size)
			var t := world.cell_type(c.x, c.y)
			if t != WorldMap.Terrain.GROUND and t != WorldMap.Terrain.FOREST:
				continue
			if float(_avg_h[i]) >= WorldMap.WATER_LEVEL + level:
				continue
			if _connected(c, now):
				now[i] = true
	if now.size() == flooded.size() and _same(now):
		return false
	flooded = now
	revision += 1
	return true


func _same(other: Dictionary) -> bool:
	for k in other:
		if not flooded.has(k):
			return false
	return true


## Клетка граничит с водой (расстояние 1) или с уже затопленной клеткой.
func _connected(c: Vector2i, now: Dictionary) -> bool:
	if _dist.get(_idx(c), 99) == 1:
		return true
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nc: Vector2i = c + off
		if nc.x >= 0 and nc.y >= 0 and nc.x < world.size and nc.y < world.size and now.has(_idx(nc)):
			return true
	return false


func clear() -> void:
	if not flooded.is_empty():
		flooded = {}
		revision += 1
	level = 0.0
