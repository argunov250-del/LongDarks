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
		WorldMap.Terrain.RUINS:
			return &"scrap_metal"
	return &""


## Исходный запас (до добычи).
func initial_amount(cell: Vector2i) -> int:
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
	return got


func to_dict() -> Dictionary:
	var t := {}
	for k in _taken:
		t[str(k)] = _taken[k]
	return {"taken": t}


func from_dict(d: Dictionary) -> void:
	_taken.clear()
	if d.get("taken") is Dictionary:
		for k in d["taken"]:
			var n := SaveManager.to_int(d["taken"][k], 0)
			if n > 0:
				_taken[SaveManager.to_int(k, -1)] = n
