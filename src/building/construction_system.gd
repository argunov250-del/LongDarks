class_name ConstructionSystem
extends SimSystem
## Строительство со свободным размещением (позиция + любой угол поворота).
## Стадии: фундамент -> стены -> крыша -> готово. Цена стадии списывается из
## EconomySystem при её старте (нет ресурсов — стройка ждёт), затем стадия
## идёт по работе. Источник работы:
##  - external_work = false (по умолчанию, тесты без населения): плейсхолдер
##    BUILD_RATE * build_speed_multiplier за секунду на стройку;
##  - external_work = true (включает VillagerSystem): работа идёт ТОЛЬКО от жителей,
##    физически стоящих на объекте (add_work); BUILD_RATE — базовая скорость одного жителя.
##
## Руины: каждая клетка WorldMap.Terrain.RUINS — объект-руина (id = индекс клетки).
## ИСТОЧНИК ИСТИНЫ по металлолому руин — Deposits (клетка RUINS = месторождение
## scrap_metal). Разбор руины забирает через deposits.take весь остаток металлолома
## клетки (поэтому двойного счёта нет: добыть то же повторно нельзя), плюс камень и
## доски по детерминированному хешу. Восстановление тоже обнуляет остаток клетки
## (металлолом пропадает). Сохраняется только множество «снятых» руин и задания.

const TOPIC_PLACED := &"building_placed"
const TOPIC_STAGE_STARTED := &"building_stage_started"
const TOPIC_STAGE_DONE := &"building_stage_done"
const TOPIC_COMPLETED := &"building_completed"
const TOPIC_UPGRADED := &"building_upgraded"
const TOPIC_RUIN_RESTORED := &"ruin_restored"
const TOPIC_RUIN_DISMANTLED := &"ruin_dismantled"
const TOPIC_CANCELLED := &"building_cancelled"
const TOPIC_FELLED := &"cell_felled"  # клетка леса вырублена: {"cell": Vector2i}
const TOPIC_CHANGED := &"construction_changed"  # состав зданий/руин изменился

var world: WorldMap
var economy: EconomySystem
var buildings: Dictionary = {}      # int id -> Building
var ruins: Dictionary = {}          # int ruin id -> {"id","cell":Vector2i,"pos":Vector3}
## Хуки (сезоны/погода — позже). Не сохраняются: их выставляет внешняя система.
var ground_frozen: bool = false     # блокирует СТАРТ стадии фундамента
var build_speed_multiplier: float = 1.0
## true: плейсхолдерная работа отключена, работу вносят жители через add_work().
var external_work: bool = false

var _consumed: Dictionary = {}      # int ruin id -> true (разобрана/восстановлена)
var _jobs: Dictionary = {}          # int ruin id -> float прогресс разбора
var _fell: Dictionary = {}          # int индекс клетки леса -> float прогресс вырубки
var _fell_blocked := false          # хотя бы одна вырубка ждёт места на складах
var _next_id: int = 1
var _sim: Simulation
var _ext := {&"build": {}, &"fell": {}, &"dismantle": {}}  # вид -> {id: работа за тик}


func _init(world_in: WorldMap, economy_in: EconomySystem) -> void:
	world = world_in
	economy = economy_in
	_build_ruins()


func _build_ruins() -> void:
	ruins.clear()
	for cz in world.size:
		for cx in world.size:
			if world.cell_type(cx, cz) == WorldMap.Terrain.RUINS:
				var rid := cz * world.size + cx
				ruins[rid] = {"id": rid, "cell": Vector2i(cx, cz), "pos": world.cell_center(cx, cz)}


## Привязка к симуляции для событий (тик делает это сам).
func attach(sim: Simulation) -> void:
	_sim = sim


# ---------- запросы ----------

func get_building(id: int) -> Building:
	return buildings.get(id)


func is_ruin_active(rid: int) -> bool:
	return ruins.has(rid) and not _consumed.has(rid)


func active_ruin_ids() -> Array[int]:
	var out: Array[int] = []
	for rid in ruins:
		if not _consumed.has(rid):
			out.append(rid)
	out.sort()
	return out


func building_at(p: Vector3, margin: float = 0.3) -> Building:
	var q := Vector2(p.x, p.z)
	for b: Building in buildings.values():
		if Footprint.contains(b.xz(), b.size(), b.rot, q, margin):
			return b
	for b: Building in buildings.values():  # двор тоже относится к дому (тап по двору выбирает дом)
		for part in b.world_parts():
			if part["kind"] == &"yard" and Footprint.contains(part["c"], part["size"], b.rot, q, 0.0):
				return b
	return null


## Активная руина под точкой (клетка 1x1) или -1.
func ruin_at(p: Vector3) -> int:
	var c := world.cell_of(p.x, p.z)
	var rid := c.y * world.size + c.x
	return rid if is_ruin_active(rid) else -1


func is_dismantling(rid: int) -> bool:
	return _jobs.has(rid)


func dismantle_fraction(rid: int) -> float:
	return clampf(_jobs.get(rid, 0.0) / BuildingDefs.DISMANTLE_WORK, 0.0, 1.0)


## Что даст разбор руины.
func ruin_yield(rid: int) -> Dictionary:
	if not ruins.has(rid):
		return {}
	var cell: Vector2i = ruins[rid]["cell"]
	var out := {}
	var scrap := economy.deposits.remaining(cell)
	if scrap > 0:
		out[&"scrap_metal"] = scrap
	var stone := BuildingDefs.DISMANTLE_STONE_MIN + int(world.hash01(cell.x, cell.y, BuildingDefs.SALT_DISMANTLE_STONE) * 3.0)
	var planks := BuildingDefs.DISMANTLE_PLANKS_MIN + int(world.hash01(cell.x, cell.y, BuildingDefs.SALT_DISMANTLE_PLANKS) * 3.0)
	if stone > 0:
		out[&"stone"] = stone
	if planks > 0:
		out[&"planks"] = planks
	return out


## Двор не мешает колодцу: колодец можно ставить где угодно, в том числе внутри двора.
static func _parts_compatible(t1: StringName, k1: StringName, t2: StringName, k2: StringName) -> bool:
	return (k1 == &"yard" and BuildingDefs.is_well(t2) and k2 == &"body") or (k2 == &"yard" and BuildingDefs.is_well(t1) and k1 == &"body")


## Проверка места: {"ok": bool, "reason": &"" | &"outside" | &"water" | &"slope" | &"overlap"}. Лес не мешает: стройка ждёт вырубки.
## Проверяются все части здания (основание и двор жилья).
func validate_placement(type: StringName, pos: Vector3, rot: float, ignore_id: int = -1, host_id: int = 0) -> Dictionary:
	if not BuildingDefs.exists(type):
		return {"ok": false, "reason": &"type"}
	var c := Vector2(pos.x, pos.z)
	var parts := BuildingDefs.world_parts(type, c, rot)
	var bounds := world.get_bounds().grow(-BuildingDefs.MAP_MARGIN)
	for part in parts:
		for p in Footprint.corners(part["c"], part["size"], rot):
			if not bounds.has_point(p):
				return {"ok": false, "reason": &"outside"}
	for part in parts:
		var size: Vector2 = part["size"]
		var pts: Array[Vector2] = Footprint.corners(part["c"], size, rot)
		pts.append(part["c"])
		var lo := INF
		var hi := -INF
		for i in 4:  # середины сторон тоже: узкие здания (забор) могут пересекать воду между углами
			pts.append((pts[i] + pts[(i + 1) % 4]) * 0.5)
		for p in pts:
			if world.is_water(p.x, p.y):
				return {"ok": false, "reason": &"water"}
			var h := world.height_at(p.x, p.y)
			lo = minf(lo, h)
			hi = maxf(hi, h)
		if (hi - lo) / maxf(maxf(size.x, size.y), 0.01) > BuildingDefs.MAX_SLOPE:
			return {"ok": false, "reason": &"slope"}
	for b: Building in buildings.values():
		if b.id == ignore_id or b.id == host_id:
			continue
		if BuildingDefs.is_barn(b.type) and b.host_id == ignore_id and ignore_id > 0:
			continue  # сарай лежит в дворе улучшаемого дома
		for op in b.world_parts():
			for np in parts:
				if _parts_compatible(type, np["kind"], b.type, op["kind"]):
					continue
				if Footprint.overlaps(np["c"], np["size"], rot, op["c"], op["size"], b.rot, BuildingDefs.BUILD_GAP):
					return {"ok": false, "reason": &"overlap"}
	return {"ok": true, "reason": &""}


## Клетки леса с деревьями под основанием.
func footprint_tree_cells(c: Vector2, size: Vector2, rot: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var pts := Footprint.corners(c, size, rot)
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var a := world.cell_of(lo.x, lo.y)
	var z := world.cell_of(hi.x, hi.y)
	var cs := world.cell_size
	for cz in range(maxi(a.y, 0), mini(z.y, world.size - 1) + 1):
		for cx in range(maxi(a.x, 0), mini(z.x, world.size - 1) + 1):
			if world.cell_type(cx, cz) != WorldMap.Terrain.FOREST:
				continue
			if economy.deposits.remaining(Vector2i(cx, cz)) <= 0:
				continue
			if Footprint.overlaps(c, size, rot, Vector2((cx + 0.5) * cs, (cz + 0.5) * cs), Vector2(cs, cs), 0.0, 0.0):
				out.append(Vector2i(cx, cz))
	return out


## Клетки леса под всеми частями здания (основание и двор).
func placement_tree_cells(type: StringName, pos: Vector3, rot: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for part in BuildingDefs.world_parts(type, Vector2(pos.x, pos.z), rot):
		for cell in footprint_tree_cells(part["c"], part["size"], rot):
			if not out.has(cell):
				out.append(cell)
	return out


func _building_tree_cells(b: Building) -> Array[Vector2i]:
	return placement_tree_cells(b.type, b.position, b.rot)


func ground_height(pos: Vector3) -> float:
	return world.height_at(pos.x, pos.z)


# ---------- действия ----------

## Сарай во дворе готового дома: обычная стройка (этапы, ресурсы, жители), привязана к дому.
## Возвращает id или -1 (нет дома, сарай уже есть/строится, нет места).
func place_barn(house_id: int) -> int:
	var h := get_building(house_id)
	if h == null or not h.is_done() or not BuildingDefs.is_housing(h.type) or barn_of(house_id) != null:
		return -1
	var c := Footprint.local_to_world(h.xz(), h.rot, BuildingDefs.YARD_OFFSET + HouseholdDefs.BARN_POS)
	var pos := Vector3(c.x, 0.0, c.y)
	if not validate_placement(&"barn", pos, h.rot, -1, house_id)["ok"]:
		return -1
	var id := _create(&"barn", pos, h.rot, false)
	get_building(id).host_id = house_id
	return id


## Сарай дома (в любом состоянии) или null.
func barn_of(house_id: int) -> Building:
	for b: Building in buildings.values():
		if b.host_id == house_id and BuildingDefs.is_barn(b.type):
			return b
	return null


## Закладывает стройку. Возвращает id или -1 (место не подходит).
func place(type: StringName, pos: Vector3, rot: float) -> int:
	if not validate_placement(type, pos, rot)["ok"]:
		return -1
	return _create(type, pos, rot, false)


func _create(type: StringName, pos: Vector3, rot: float, restored: bool) -> int:
	var b := Building.new()
	b.id = _next_id
	_next_id += 1
	b.type = type
	b.position = Vector3(pos.x, world.height_at(pos.x, pos.z), pos.z)
	b.rot = rot
	b.restored = restored
	buildings[b.id] = b
	start_felling(_building_tree_cells(b))  # чертёж на лесе: сразу задания вырубки
	_emit(TOPIC_PLACED, {"id": b.id, "type": type})
	_emit(TOPIC_CHANGED, {})
	return b.id


## Отмена чертежа (ничего ещё не оплачено): снимает здание и его задания вырубки,
## которые не нужны другим чертежам. Уже вырубленное остаётся.
func cancel_building(id: int) -> bool:
	var b := get_building(id)
	if b == null or b.is_done() or b.stage != BuildingDefs.Stage.FOUNDATION or b.stage_paid or b.progress > 0.0:
		return false
	var cells := _building_tree_cells(b)
	var bn := barn_of(id)
	if bn != null:
		buildings.erase(bn.id)
	buildings.erase(id)
	var keep := {}
	for o: Building in buildings.values():
		for c in _building_tree_cells(o):
			keep[_cell_idx(c)] = true
	for c in cells:
		var i := _cell_idx(c)
		if not keep.has(i) and _fell.has(i):
			_fell.erase(i)
	_emit(TOPIC_CANCELLED, {"id": id})
	_emit(TOPIC_CHANGED, {})
	return true


func can_upgrade(id: int) -> bool:
	var b := get_building(id)
	if b == null or not b.is_done():
		return false
	var nxt := BuildingDefs.upgrade_of(b.type)
	if nxt == &"":
		return false
	return validate_placement(nxt, b.position, b.rot, b.id)["ok"]


## Улучшение на месте: тот же id и позиция, стройка идёт с фундамента нового типа.
func upgrade(id: int) -> bool:
	if not can_upgrade(id):
		return false
	var b := get_building(id)
	var old := b.type
	b.type = BuildingDefs.upgrade_of(old)
	b.stage = BuildingDefs.Stage.FOUNDATION
	b.stage_paid = false
	b.progress = 0.0
	b.restored = false
	b.blocked = &""
	_emit(TOPIC_UPGRADED, {"id": id, "from": old, "to": b.type})
	_emit(TOPIC_CHANGED, {})
	return true


## Восстановить руину в здание типа type (дешевле). Возвращает id здания или -1.
func restore_ruin(rid: int, type: StringName) -> int:
	if not is_ruin_active(rid) or _jobs.has(rid) or not BuildingDefs.is_restorable(type):
		return -1
	var r: Dictionary = ruins[rid]
	var rot := world.hash01(r["cell"].x, r["cell"].y, 77) * TAU
	if not validate_placement(type, r["pos"], rot)["ok"]:
		return -1
	_exhaust_scrap(r["cell"])
	_consumed[rid] = true
	var bid := _create(type, r["pos"], rot, true)
	_emit(TOPIC_RUIN_RESTORED, {"ruin": rid, "id": bid})
	return bid


## Начать разбор руины (занимает работу DISMANTLE_WORK).
func start_dismantle(rid: int) -> bool:
	if not is_ruin_active(rid) or _jobs.has(rid):
		return false
	_jobs[rid] = 0.0
	_emit(TOPIC_CHANGED, {})
	return true


func _exhaust_scrap(cell: Vector2i) -> int:
	return economy.deposits.take(cell, economy.deposits.remaining(cell))


## Разбор дошёл до конца, но складам не хватает места (ждёт, ничего не теряется).
func is_dismantle_blocked(rid: int) -> bool:
	return _jobs.has(rid) and _jobs[rid] >= BuildingDefs.DISMANTLE_WORK


## Атомарно: либо весь выход ложится на склады, либо ничего (работа ждёт).
func _try_finish_dismantle(rid: int) -> bool:
	var r: Dictionary = ruins[rid]
	var y := ruin_yield(rid)
	var need := 0
	for res in y:
		need += y[res]
	if need > economy.total_free_space():
		return false
	for res in y:
		economy.deposit(res, y[res])
	_exhaust_scrap(r["cell"])
	_jobs.erase(rid)
	_consumed[rid] = true
	_emit(TOPIC_RUIN_DISMANTLED, {"ruin": rid, "yield": y})
	_emit(TOPIC_CHANGED, {})
	return true


# ---------- вырубка ----------

func _cell_idx(cell: Vector2i) -> int:
	return cell.y * world.size + cell.x


func _idx_cell(idx: int) -> Vector2i:
	return Vector2i(idx % world.size, idx / world.size)


## Клетки леса с деревьями под кистью: круг (расстояние до центра клетки) или квадрат.
func fell_cells_in_brush(center: Vector3, radius: float, circle: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var a := world.cell_of(center.x - radius, center.z - radius)
	var z := world.cell_of(center.x + radius, center.z + radius)
	for cz in range(maxi(a.y, 0), mini(z.y, world.size - 1) + 1):
		for cx in range(maxi(a.x, 0), mini(z.x, world.size - 1) + 1):
			if world.cell_type(cx, cz) != WorldMap.Terrain.FOREST:
				continue
			var cell := Vector2i(cx, cz)
			if economy.deposits.remaining(cell) <= 0:
				continue
			var cc := world.cell_center(cx, cz)
			var dx := absf(cc.x - center.x)
			var dz := absf(cc.z - center.z)
			if (circle and dx * dx + dz * dz <= radius * radius) or (not circle and maxf(dx, dz) <= radius):
				out.append(cell)
	return out


## Помечает клетки на вырубку; возвращает число новых заданий.
func start_felling(cells: Array[Vector2i]) -> int:
	var n := 0
	for cell in cells:
		if economy.deposits.resource_at(cell) != &"logs" or economy.deposits.remaining(cell) <= 0:
			continue
		var i := _cell_idx(cell)
		if not _fell.has(i):
			_fell[i] = 0.0
			n += 1
	if n > 0:
		_emit(TOPIC_CHANGED, {})
	return n


## Индексы клеток с заданием вырубки (для планировщика жителей).
func felling_indices() -> Array[int]:
	var out: Array[int] = []
	for i in _fell:
		out.append(i)
	out.sort()
	return out


func index_cell(idx: int) -> Vector2i:
	return _idx_cell(idx)


## Руины с идущим разбором, где ещё нужна работа (не ждут складов).
func open_dismantles() -> Array[int]:
	var out: Array[int] = []
	for rid in _jobs:
		if _jobs[rid] < BuildingDefs.DISMANTLE_WORK:
			out.append(rid)
	out.sort()
	return out


## Работа жителя на объекте. kind: &"build" (id здания), &"fell" (индекс клетки),
## &"dismantle" (id руины). Учитывает build_speed_multiplier. Без external_work игнорируется.
func add_work(kind: StringName, id: int, amount: float) -> void:
	if not external_work or amount <= 0.0 or not _ext.has(kind):
		return
	var d: Dictionary = _ext[kind]
	d[id] = d.get(id, 0.0) + amount * maxf(build_speed_multiplier, 0.0)


func _work_for(kind: StringName, id: int, base: float) -> float:
	return _ext[kind].get(id, 0.0) if external_work else base


func is_felling(cell: Vector2i) -> bool:
	return _fell.has(_cell_idx(cell))


func felling_count() -> int:
	return _fell.size()


## Есть вырубка, ждущая места на складах.
func is_felling_blocked() -> bool:
	return _fell_blocked


func has_trees(cell: Vector2i) -> bool:
	return economy.deposits.resource_at(cell) == &"logs" and economy.deposits.remaining(cell) > 0


func _tick_felling(base_work: float) -> void:
	_fell_blocked = false
	var changed := false
	for i in _fell.keys():
		var cell := _idx_cell(i)
		var p: float = _fell[i] + _work_for(&"fell", i, base_work)
		while p >= BuildingDefs.FELL_WORK_PER_LOG and economy.deposits.remaining(cell) > 0:
			if economy.total_free_space() < 1:
				p = BuildingDefs.FELL_WORK_PER_LOG  # ждём места, прогресс не копится сверх одного бревна
				_fell_blocked = true
				break
			economy.deposit(&"logs", economy.deposits.take(cell, 1))
			p -= BuildingDefs.FELL_WORK_PER_LOG
		if economy.deposits.remaining(cell) <= 0:
			_fell.erase(i)
			_emit(TOPIC_FELLED, {"cell": cell})
			changed = true
		else:
			_fell[i] = p
	if changed:
		_emit(TOPIC_CHANGED, {})


# ---------- тик ----------

func tick(sim: Simulation, dt: float) -> void:
	_sim = sim
	if dt <= 0.0:
		return
	var work := BuildingDefs.BUILD_RATE * maxf(build_speed_multiplier, 0.0) * dt
	for b: Building in buildings.values():
		if not b.is_done():
			_advance(b, _work_for(&"build", b.id, work))  # и при 0: оплата стадии/причина простоя
	for rid in _jobs.keys():
		_jobs[rid] = minf(_jobs[rid] + _work_for(&"dismantle", rid, work), BuildingDefs.DISMANTLE_WORK)
		if _jobs[rid] >= BuildingDefs.DISMANTLE_WORK:
			_try_finish_dismantle(rid)
	_tick_felling(work)
	for k in _ext:
		(_ext[k] as Dictionary).clear()


func _advance(b: Building, work: float) -> void:
	var guard := 0
	while not b.is_done() and guard < 8:
		guard += 1
		if not b.stage_paid:
			if b.stage == BuildingDefs.Stage.FOUNDATION and not _building_tree_cells(b).is_empty():
				b.blocked = &"forest"
				start_felling(_building_tree_cells(b))
				return
			if b.stage == BuildingDefs.Stage.FOUNDATION and ground_frozen:
				b.blocked = &"frozen"
				return
			if not economy.consume(b.stage_cost()):
				b.blocked = &"resources"
				return
			b.stage_paid = true
			_emit(TOPIC_STAGE_STARTED, {"id": b.id, "stage": b.stage})
		b.blocked = &""
		var need := b.stage_work() - b.progress
		if need > work + 0.000001:
			b.progress += work
			return
		work = maxf(0.0, work - maxf(need, 0.0))
		var finished := b.stage
		b.progress = 0.0
		b.stage_paid = false
		b.stage += 1
		_emit(TOPIC_STAGE_DONE, {"id": b.id, "stage": finished})
		if b.is_done():
			_on_completed(b)


func _on_completed(b: Building) -> void:
	var cap := BuildingDefs.storage_capacity(b.type)
	if cap > 0 and b.storage_id == 0:
		var s := Storage.new(cap, b.position, BuildingDefs.is_cellar(b.type))
		economy.add_storage(s)
		b.storage_id = s.id
	_emit(TOPIC_COMPLETED, {"id": b.id, "type": b.type})
	_emit(TOPIC_CHANGED, {})


func _emit(topic: StringName, payload: Dictionary) -> void:
	if _sim != null:
		_sim.bus.emit(topic, payload)


# ---------- сохранение ----------

func get_save_key() -> StringName:
	return &"construction"


func save_state() -> Dictionary:
	var list := []
	for id in buildings:
		list.append(buildings[id].to_dict())
	var cons := []
	for rid in _consumed:
		cons.append(rid)
	cons.sort()
	var jobs := {}
	for rid in _jobs:
		jobs[str(rid)] = _jobs[rid]
	var fell := {}
	for i in _fell:
		fell[str(i)] = _fell[i]
	return {"next_id": _next_id, "buildings": list, "consumed": cons, "jobs": jobs, "felling": fell}


func load_state(d: Dictionary) -> void:
	_build_ruins()  # мир мог быть пересоздан загрузкой
	buildings.clear()
	_consumed.clear()
	_jobs.clear()
	_fell.clear()
	_fell_blocked = false
	if d.get("buildings") is Array:
		for e in d["buildings"]:
			if e is Dictionary:
				var b := Building.from_dict(e)
				if b.id > 0 and BuildingDefs.exists(b.type):
					buildings[b.id] = b
	if d.get("consumed") is Array:
		for v in d["consumed"]:
			_consumed[SaveManager.to_int(v, -1)] = true
	if d.get("jobs") is Dictionary:
		for k in d["jobs"]:
			var rid := SaveManager.to_int(k, -1)
			if ruins.has(rid) and not _consumed.has(rid):
				_jobs[rid] = float(d["jobs"][k])
	if d.get("felling") is Dictionary:
		for k in d["felling"]:
			var i := SaveManager.to_int(k, -1)
			if i >= 0 and i < world.size * world.size and economy.deposits.resource_at(_idx_cell(i)) == &"logs":
				_fell[i] = float(d["felling"][k])
	_next_id = SaveManager.to_int(d.get("next_id"), 1)
	for id in buildings:
		_next_id = maxi(_next_id, id + 1)
	_emit(TOPIC_CHANGED, {})
