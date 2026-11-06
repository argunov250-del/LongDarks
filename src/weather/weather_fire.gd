class_name WeatherFire
extends RefCounted
## Пожар после грозы (шаг 14): горящие клетки леса и горящие здания.
## Клетка: {"left": горение осталось, "water": воды до тушения, "acc": таймер перехода, "focus": очаг}.
## Здание: {"left", "water", "acc"}. Огонь переходит на соседние клетки леса и на здания вплотную
## к лесу (шансы — экземплярные копии констант, тесты их подменяют). Жители тушат его водой
## (douse_*). Выгоревшая клетка: деревья сгорают (Deposits.take), плодородие растёт; здание не
## разрушается, а получает damaged (ремонт жителями). Случайность — RNG симуляции.

const EV_CELL_BURNT := &"cell_burnt"          # клетка выгорела: {"cell", "trees"}
const EV_CELL_SAVED := &"cell_saved"          # клетку потушили
const EV_BUILDING_IGNITED := &"building_ignited"
const EV_BUILDING_DAMAGED := &"building_damaged"
const EV_BUILDING_SAVED := &"building_saved"
const EV_CELL_IGNITED := &"cell_ignited"

var world: WorldMap
var construction: ConstructionSystem
var deposits: Deposits

var cells: Dictionary = {}       # int индекс клетки -> Dictionary
var buildings: Dictionary = {}   # int id здания -> Dictionary
var revision: int = 0
var burn_time: float = WeatherDefs.BURN_TIME
var spread_interval: float = WeatherDefs.SPREAD_INTERVAL
var spread_chance: float = WeatherDefs.SPREAD_CHANCE
var max_cells: int = WeatherDefs.MAX_BURN_CELLS
var building_reach: float = WeatherDefs.BUILDING_FIRE_REACH
var building_chance: float = WeatherDefs.BUILDING_IGNITE_CHANCE
var building_burn_time: float = WeatherDefs.BUILDING_BURN_TIME
var forest_water: int = WeatherDefs.FOREST_FIRE_WATER
var building_water: int = WeatherDefs.BUILDING_FIRE_WATER
## Сколько клеток зажёг каждый очаг (id очага -> число).
var _focus_cells: Dictionary = {}
var _next_focus: int = 1


func _init(world_in: WorldMap = null, construction_in: ConstructionSystem = null) -> void:
	world = world_in
	construction = construction_in
	deposits = construction_in.economy.deposits if construction_in != null else null


func idx(c: Vector2i) -> int:
	return c.y * world.size + c.x


func cell_of_idx(i: int) -> Vector2i:
	return Vector2i(i % world.size, i / world.size)


func is_empty() -> bool:
	return cells.is_empty() and buildings.is_empty()


func is_cell_burning(c: Vector2i) -> bool:
	return cells.has(idx(c))


func is_building_burning(id: int) -> bool:
	return buildings.has(id)


func burning_cell_count() -> int:
	return cells.size()


# ---------- поджог ----------

func _burnable(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < world.size and c.y < world.size and deposits.resource_at(c) == &"logs" and deposits.remaining(c) > 0


## Поджигает лесную клетку с деревьями (focus 0 — новый очаг). false: нечему гореть/уже горит.
func ignite_cell(c: Vector2i, focus: int = 0) -> bool:
	if not _burnable(c) or cells.has(idx(c)):
		return false
	if focus <= 0:
		focus = _next_focus
		_next_focus += 1
	_focus_cells[focus] = int(_focus_cells.get(focus, 0)) + 1
	cells[idx(c)] = {"left": burn_time, "water": forest_water, "acc": 0.0, "focus": focus}
	revision += 1
	return true


## Поджигает готовое здание (не колодец, не повреждённое/горящее). false — нельзя.
func ignite_building(id: int) -> bool:
	var b := construction.get_building(id)
	if b == null or not b.is_done() or b.damaged or b.burning or BuildingDefs.is_well(b.type):
		return false
	b.burning = true
	buildings[id] = {"left": building_burn_time, "water": building_water, "acc": 0.0}
	revision += 1
	return true


## Готовые здания вплотную к клетке (не дальше building_reach от её границы).
func buildings_near_cell(c: Vector2i) -> Array[int]:
	var out: Array[int] = []
	var cs := world.cell_size
	var cc := Vector2((c.x + 0.5) * cs, (c.y + 0.5) * cs)
	for id in construction.buildings:
		var b: Building = construction.buildings[id]
		if not b.is_done() or b.damaged or b.burning or BuildingDefs.is_well(b.type):
			continue
		if Footprint.overlaps(b.xz(), b.size(), b.rot, cc, Vector2(cs, cs), 0.0, building_reach):
			out.append(id)
	out.sort()
	return out


# ---------- тушение ----------

## Выливает воду на клетку; true — потушена.
func douse_cell(i: int, water: int) -> bool:
	if not cells.has(i):
		return false
	cells[i]["water"] = int(cells[i]["water"]) - water
	if int(cells[i]["water"]) <= 0:
		cells.erase(i)
		revision += 1
		return true
	return false


func douse_building(id: int, water: int) -> bool:
	if not buildings.has(id):
		return false
	buildings[id]["water"] = int(buildings[id]["water"]) - water
	if int(buildings[id]["water"]) <= 0:
		_put_out_building(id)
		return true
	return false


func _put_out_building(id: int) -> void:
	buildings.erase(id)
	var b := construction.get_building(id)
	if b != null:
		b.burning = false
	revision += 1


## Вода, которой огню ещё не хватает (для распределения жителей).
func water_left(dest: StringName, target: int) -> int:
	if dest == &"building":
		return int(buildings[target]["water"]) if buildings.has(target) else 0
	return int(cells[target]["water"]) if cells.has(target) else 0


func is_burning(dest: StringName, target: int) -> bool:
	return buildings.has(target) if dest == &"building" else cells.has(target)


## Мировая точка очага (центр клетки или здания).
func target_pos(dest: StringName, target: int) -> Variant:
	if dest == &"building":
		var b := construction.get_building(target)
		return b.position if b != null else null
	if not cells.has(target):
		return null
	var c := cell_of_idx(target)
	return world.cell_center(c.x, c.y)


## Дождь: гасит всё сразу (деревья и здания целы).
func extinguish_all() -> void:
	if is_empty():
		return
	for id in buildings.keys():
		var b := construction.get_building(id)
		if b != null:
			b.burning = false
	cells.clear()
	buildings.clear()
	revision += 1


# ---------- тик ----------

## Шаг огня. Возвращает события [{"type", ...}] для шины и статистики.
func tick(dt: float, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if dt <= 0.0 or is_empty():
		return events
	var keys: Array = cells.keys()
	keys.sort()
	for i in keys:
		if not cells.has(i):
			continue
		var f: Dictionary = cells[i]
		f["left"] = float(f["left"]) - dt
		f["acc"] = float(f["acc"]) + dt
		var c := cell_of_idx(i)
		while float(f["acc"]) >= spread_interval:
			f["acc"] = float(f["acc"]) - spread_interval
			_try_spread(c, int(f["focus"]), rng, events)
		if float(f["left"]) <= 0.0:
			var trees := deposits.remaining(c)
			deposits.take(c, trees)
			cells.erase(i)
			revision += 1
			events.append({"type": EV_CELL_BURNT, "cell": c, "trees": trees})
	var bkeys: Array = buildings.keys()
	bkeys.sort()
	for id in bkeys:
		if not buildings.has(id):
			continue
		var f: Dictionary = buildings[id]
		f["left"] = float(f["left"]) - dt
		if float(f["left"]) <= 0.0:
			var b := construction.get_building(id)
			buildings.erase(id)
			revision += 1
			if b != null:
				b.burning = false
				b.damaged = true
				b.repair_paid = false
				b.repair_progress = 0.0
				events.append({"type": EV_BUILDING_DAMAGED, "id": id})
	return events


func _try_spread(c: Vector2i, focus: int, rng: RandomNumberGenerator, events: Array[Dictionary]) -> void:
	# на соседнюю клетку леса (не больше max_cells на очаг)
	if int(_focus_cells.get(focus, 0)) < max_cells:
		var nbrs: Array[Vector2i] = []
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + off
			if _burnable(n) and not cells.has(idx(n)):
				nbrs.append(n)
		if not nbrs.is_empty():
			var pick := nbrs[rng.randi_range(0, nbrs.size() - 1)]
			if rng.randf() < spread_chance and ignite_cell(pick, focus):
				events.append({"type": EV_CELL_IGNITED, "cell": pick})
	# на здания вплотную к лесу
	for id in buildings_near_cell(c):
		if rng.randf() < building_chance and ignite_building(id):
			events.append({"type": EV_BUILDING_IGNITED, "id": id})


# ---------- сохранение ----------

func save_state() -> Dictionary:
	var cl := []
	var keys: Array = cells.keys()
	keys.sort()
	for i in keys:
		var f: Dictionary = cells[i]
		cl.append({"i": i, "left": f["left"], "water": f["water"], "acc": f["acc"], "focus": f["focus"]})
	var bl := []
	var bkeys: Array = buildings.keys()
	bkeys.sort()
	for id in bkeys:
		var f: Dictionary = buildings[id]
		bl.append({"id": id, "left": f["left"], "water": f["water"], "acc": f["acc"]})
	var fc := {}
	for k in _focus_cells:
		fc[str(k)] = _focus_cells[k]
	return {"cells": cl, "buildings": bl, "focus_cells": fc, "next_focus": _next_focus}


func load_state(d: Dictionary) -> void:
	for id in buildings:
		var ob := construction.get_building(id)
		if ob != null:
			ob.burning = false
	cells.clear()
	buildings.clear()
	_focus_cells.clear()
	_next_focus = maxi(1, SaveManager.to_int(d.get("next_focus"), 1))
	if d.get("focus_cells") is Dictionary:
		for k in d["focus_cells"]:
			_focus_cells[SaveManager.to_int(k, 0)] = SaveManager.to_int(d["focus_cells"][k], 0)
	if d.get("cells") is Array:
		for e in d["cells"]:
			if e is Dictionary:
				var i := SaveManager.to_int(e.get("i"), -1)
				if i >= 0 and i < world.size * world.size:
					cells[i] = {"left": float(e.get("left", 0.0)), "water": SaveManager.to_int(e.get("water"), forest_water),
						"acc": float(e.get("acc", 0.0)), "focus": SaveManager.to_int(e.get("focus"), 0)}
	if d.get("buildings") is Array:
		for e in d["buildings"]:
			if e is Dictionary:
				var id := SaveManager.to_int(e.get("id"), -1)
				var b := construction.get_building(id)
				if b != null:
					b.burning = true
					buildings[id] = {"left": float(e.get("left", 0.0)), "water": SaveManager.to_int(e.get("water"), building_water),
						"acc": float(e.get("acc", 0.0))}
	revision += 1
