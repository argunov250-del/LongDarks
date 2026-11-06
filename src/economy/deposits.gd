class_name Deposits
extends RefCounted
## Конечные месторождения, выводимые из WorldMap детерминированно:
## лес — деревья (logs), руины — металлолом. Сохраняются только отличия
## (сколько уже взято). Возобновления нет.

const TREES_MIN := 3
const TREES_MAX := 7
const SCRAP_MIN := 20
const SCRAP_MAX := 60
const SALT_FOREST := 101
const SALT_RUINS := 202

var world: WorldMap
var _taken: Dictionary = {}  # int индекс клетки -> int взято
var _grown: Dictionary = {}  # int индекс не-лесной клетки -> int деревьев (посадка, шаг 17)
## Растёт при любом изменении запасов (дешёвая проверка для визуала).
var revision: int = 0


func _init(world_in: WorldMap = null) -> void:
	world = world_in


func _index(cell: Vector2i) -> int:
	return cell.y * world.size + cell.x


func _in_bounds(cell: Vector2i) -> bool:
	return world != null and cell.x >= 0 and cell.y >= 0 and cell.x < world.size and cell.y < world.size


## Ресурс месторождения клетки или &"" если его нет.
func resource_at(cell: Vector2i) -> StringName:
	if not _in_bounds(cell):
		return &""
	match world.cell_type(cell.x, cell.y):
		WorldMap.Terrain.FOREST:
			return &"logs"
		WorldMap.Terrain.GROUND:
			return &"logs" if _grown.has(_index(cell)) else &""
		WorldMap.Terrain.RUINS:
			return &"scrap_metal"
	return &""


## Исходный запас (до добычи).
func initial_amount(cell: Vector2i) -> int:
	if _in_bounds(cell) and _grown.has(_index(cell)):
		return _grown[_index(cell)]
	match resource_at(cell):
		&"logs":
			return TREES_MIN + int(world.hash01(cell.x, cell.y, SALT_FOREST) * (TREES_MAX - TREES_MIN + 1))
		&"scrap_metal":
			return SCRAP_MIN + int(world.hash01(cell.x, cell.y, SALT_RUINS) * (SCRAP_MAX - SCRAP_MIN + 1))
	return 0


func remaining(cell: Vector2i) -> int:
	if not _in_bounds(cell):
		return 0
	return maxi(0, initial_amount(cell) - _taken.get(_index(cell), 0))


func is_depleted(cell: Vector2i) -> bool:
	return resource_at(cell) != &"" and remaining(cell) == 0


## Добывает не больше остатка; возвращает фактически взятое.
func take(cell: Vector2i, amount: int) -> int:
	if amount <= 0:
		return 0
	var got := mini(amount, remaining(cell))
	if got > 0:
		var i := _index(cell)
		_taken[i] = _taken.get(i, 0) + got
		revision += 1
	return got


## Выросшие посаженные деревья (design/gdd/land-restoration.md): на вырубленной клетке леса возвращает до n деревьев,
## на голой земле создаёт новое месторождение logs. Возвращает число деревьев клетки после роста.
func plant_trees(cell: Vector2i, n: int) -> int:
	if not _in_bounds(cell) or n <= 0:
		return 0
	var i := _index(cell)
	match world.cell_type(cell.x, cell.y):
		WorldMap.Terrain.FOREST:
			var want := mini(n, initial_amount(cell))
			_taken[i] = maxi(initial_amount(cell) - want, 0) if remaining(cell) < want else _taken.get(i, 0)
		WorldMap.Terrain.GROUND:
			_grown[i] = n
			_taken.erase(i)
		_:
			return 0
	revision += 1
	return remaining(cell)


func to_dict() -> Dictionary:
	var t := {}
	for k in _taken:
		t[str(k)] = _taken[k]
	var g := {}
	for k in _grown:
		g[str(k)] = _grown[k]
	return {"taken": t, "grown": g}


func from_dict(d: Dictionary) -> void:
	_taken.clear()
	_grown.clear()
	revision += 1
	if d.get("grown") is Dictionary:
		for k in d["grown"]:
			var n := SaveManager.to_int(d["grown"][k], 0)
			if n > 0:
				_grown[SaveManager.to_int(k, -1)] = n
	if d.get("taken") is Dictionary:
		for k in d["taken"]:
			var n := SaveManager.to_int(d["taken"][k], 0)
			if n > 0:
				_taken[SaveManager.to_int(k, -1)] = n
