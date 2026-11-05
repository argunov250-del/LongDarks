class_name VillagerSystem
extends SimSystem
## Жители: население, автономный выбор задач, ходьба, работа, повседневные дела.
##
## Игрок задаёт только ПРИОРИТЕТЫ категорий (0 выкл .. 3) глобально и, по желанию,
## отдельным зданиям. Каждый житель сам выбирает лучшую задачу по
## score = приоритет*W + (пригодность-1)*W - расстояние*W (см. TaskDefs).
## Работа идёт ТОЛЬКО когда житель физически на объекте: сам он зовёт
## ConstructionSystem.add_work / ProductionSystem.add_work (плейсхолдерные глобальные
## скорости при этом отключаются: external_work = true).
##
## Герой (is_hero) и собака не умирают: remove_villager отказывает бессмертным,
## любая будущая система смерти обязана проверять Villager.can_die().

const TOPIC_ARRIVED := &"villager_arrived"      # {id, name, profession}
const TOPIC_CHANGED := &"villagers_changed"     # состав/приоритеты изменились

enum Go { ARRIVED, MOVING, BLOCKED }

var world: WorldMap
var economy: EconomySystem
var construction: ConstructionSystem
var production: ProductionSystem
var pathfinder: Pathfinder

var villagers: Dictionary = {}          # int id -> Villager (в порядке появления)
var dog: Dog
var priorities: Dictionary = {}         # StringName категория -> int 0..3
var building_priorities: Dictionary = {} # int id здания -> int 0..3 (перекрывает категорию)
var house_stock: Dictionary = {}        # int id жилья -> int дров (расход — шаг 11)
var next_arrival_in: float = 0.0
## Экземплярные копии констант (тесты их подменяют).
var arrival_min: float = VillagerDefs.ARRIVAL_MIN
var arrival_max: float = VillagerDefs.ARRIVAL_MAX
var max_population: int = VillagerDefs.MAX_POPULATION

var _next_id: int = 1
var _sim: Simulation
var _fallback_rng := RandomNumberGenerator.new()
var _time := 0.0
var _jobs: Array = []
var _job_by_key: Dictionary = {}
var _jobs_age := 1000
var _jobs_dirty := true
var _claims: Dictionary = {}


func _init(world_in: WorldMap, economy_in: EconomySystem, construction_in: ConstructionSystem, production_in: ProductionSystem) -> void:
	world = world_in
	economy = economy_in
	construction = construction_in
	production = production_in
	pathfinder = Pathfinder.new(world)
	construction.external_work = true
	production.external_work = true
	reset_priorities()


func attach(sim: Simulation) -> void:
	_sim = sim


func _rng() -> RandomNumberGenerator:
	return _sim.rng if _sim != null else _fallback_rng


func _emit(topic: StringName, payload: Dictionary) -> void:
	if _sim != null:
		_sim.bus.emit(topic, payload)


# ---------- старт и население ----------

## Центр посёлка: первый склад или завод.
func hub_position() -> Vector3:
	var p: Vector3 = economy.storages[0].position if not economy.storages.is_empty() else world.cell_center(world.factory_cell.x, world.factory_cell.y)
	return pathfinder.nearest_walkable(p)


## Новая игра: только герой (мужчина) и его собака.
func start_new_game() -> void:
	villagers.clear()
	_next_id = 1
	reset_priorities()
	building_priorities.clear()
	house_stock.clear()
	var hero := Villager.generate(_rng(), {"sex": &"m", "profession": &"mechanic", "hero": true, "age": VillagerDefs.HERO_AGE})
	hero.id = _next_id
	_next_id += 1
	hero.pos = _ground(pathfinder.nearest_walkable(hub_position() + Vector3(3.0, 0.0, 3.0)))
	villagers[hero.id] = hero
	dog = Dog.new()
	dog.pos = _ground(pathfinder.nearest_walkable(hero.pos + Vector3(-2.0, 0.0, -1.0)))
	_roll_arrival()
	_jobs_dirty = true
	_emit(TOPIC_CHANGED, {})


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, world.height_at(p.x, p.z), p.z)


func population() -> int:
	return villagers.size()


func get_villager(id: int) -> Villager:
	return villagers.get(id)


func get_hero() -> Villager:
	for v: Villager in villagers.values():
		if v.is_hero:
			return v
	return null


func villager_list() -> Array[Villager]:
	var out: Array[Villager] = []
	for id in villagers:
		out.append(villagers[id])
	return out


## Единственный путь удаления жителя. Герой (и любой immortal) не удаляется.
func remove_villager(id: int) -> bool:
	var v := get_villager(id)
	if v == null or not v.can_die():
		return false
	villagers.erase(id)
	_jobs_dirty = true
	_emit(TOPIC_CHANGED, {})
	return true


func villager_near(p: Vector3, radius: float) -> Villager:
	var best: Villager = null
	var best_d := radius
	for v: Villager in villagers.values():
		var d := Vector2(v.pos.x - p.x, v.pos.z - p.z).length()
		if d <= best_d:
			best_d = d
			best = v
	return best


func _roll_arrival() -> void:
	next_arrival_in = _rng().randf_range(arrival_min, maxf(arrival_min, arrival_max))


## Новичок приходит с случайного края карты и идёт к центру посёлка.
## null — достигнут лимит населения.
func spawn_newcomer() -> Villager:
	if population() >= max_population:
		return null
	var v := Villager.generate(_rng())
	v.id = _next_id
	_next_id += 1
	v.arriving = true
	v.pos = _ground(_edge_spawn())
	v.task = {"kind": &"arrive", "cat": &"", "key": "arrive", "target": 0, "phase": &"", "work": 0.0, "carry": 0, "src": 0}
	v.think_cd = float(v.id % 10) * 0.1
	villagers[v.id] = v
	_emit(TOPIC_ARRIVED, {"id": v.id, "name": v.display_name, "profession": v.profession})
	_emit(TOPIC_CHANGED, {})
	return v


func _edge_spawn() -> Vector3:
	var n := world.size
	var hub := hub_position()
	var rng := _rng()
	for _i in 60:
		var side := rng.randi_range(0, 3)
		var t := rng.randi_range(1, n - 2)
		var c := Vector2i(t, 0)
		match side:
			1: c = Vector2i(t, n - 1)
			2: c = Vector2i(0, t)
			3: c = Vector2i(n - 1, t)
		if not pathfinder.is_walkable_cell(c):
			continue
		var p := world.cell_center(c.x, c.y)
		if not pathfinder.find_path(p, hub).is_empty():
			return p
	return hub


# ---------- приоритеты ----------

func reset_priorities() -> void:
	priorities = TaskDefs.DEFAULT_PRIORITY.duplicate()
	_jobs_dirty = true


func get_priority(cat: StringName) -> int:
	return priorities.get(cat, TaskDefs.DEFAULT_PRIORITY.get(cat, 1))


func set_priority(cat: StringName, value: int) -> void:
	if not TaskDefs.CATEGORIES.has(cat):
		return
	priorities[cat] = clampi(value, TaskDefs.PRIORITY_MIN, TaskDefs.PRIORITY_MAX)
	_jobs_dirty = true
	_emit(TOPIC_CHANGED, {})


func change_priority(cat: StringName, delta: int) -> void:
	set_priority(cat, get_priority(cat) + delta)


## Приоритет здания: -1 — нет (берётся категория), иначе 0..3.
func building_priority(id: int) -> int:
	return building_priorities.get(id, -1)


func set_building_priority(id: int, value: int) -> void:
	if value < 0:
		building_priorities.erase(id)
	else:
		building_priorities[id] = clampi(value, TaskDefs.PRIORITY_MIN, TaskDefs.PRIORITY_MAX)
	_jobs_dirty = true
	_emit(TOPIC_CHANGED, {})


func priority_of(cat: StringName, building_id: int = -1) -> int:
	if building_id >= 0 and building_priorities.has(building_id):
		return building_priorities[building_id]
	return get_priority(cat)


# ---------- дрова в жилье ----------

func firewood_capacity(building_id: int) -> int:
	var b := construction.get_building(building_id)
	return BuildingDefs.firewood_capacity(b.type) if b != null and b.is_done() else 0


func firewood_stock(building_id: int) -> int:
	return house_stock.get(building_id, 0)


# ---------- скорость и пригодность ----------

func profession_multiplier(v: Villager, cat: StringName, building_type: StringName = &"") -> float:
	if cat == TaskDefs.PRODUCTION:
		return TaskDefs.PRODUCTION_MATCH_BONUS if TaskDefs.PRODUCTION_PROFESSION.get(building_type, &"") == v.profession else 1.0
	return (TaskDefs.PROFESSION_BONUS.get(cat, {}) as Dictionary).get(v.profession, 1.0)


## Множитель скорости от навыка жителя в категории (SkillDefs).
func skill_multiplier(v: Villager, cat: StringName) -> float:
	return SkillDefs.rate_multiplier(v.skill(cat))


## Учитель на том же объекте: лучший навык среди работающих рядом (-1 — никого).
func _best_coworker_skill(v: Villager, cat: StringName) -> float:
	var key: String = v.task.get("key", "")
	var best := -1.0
	for o: Villager in villagers.values():
		if o != v and o.at_site and o.task.get("key", "") == key:
			best = maxf(best, o.skill(cat))
	return best


## Множитель роста от обучения: ученик (на TEACH_GAP слабее соседа по объекту) учится быстрее.
func teach_multiplier(v: Villager, cat: StringName) -> float:
	return SkillDefs.TEACH_BONUS if _best_coworker_skill(v, cat) - v.skill(cat) >= SkillDefs.TEACH_GAP else 1.0


## Опыт: dt секунд реальной работы в категории.
func train(v: Villager, cat: StringName, dt: float) -> void:
	v.skills[cat] = minf(SkillDefs.MAX_SKILL, v.skill(cat) + SkillDefs.gain(v.skill(cat), dt, TraitDefs.learn_multiplier(v.traits), teach_multiplier(v, cat)))


## Жители по убыванию навыка категории (стабильно по id).
func sorted_by_skill(cat: StringName) -> Array[Villager]:
	var out := villager_list()
	out.sort_custom(func(a: Villager, b: Villager) -> bool:
		if not is_equal_approx(a.skill(cat), b.skill(cat)):
			return a.skill(cat) > b.skill(cat)
		return a.id < b.id)
	return out


## Пригодность: профессия * черты * навык (без базовой скорости). 1.0 — среднее.
func suitability(v: Villager, cat: StringName, building_type: StringName = &"") -> float:
	return profession_multiplier(v, cat, building_type) * TraitDefs.rate_multiplier(v.traits, cat) * skill_multiplier(v, cat)


## Работа в секунду жителя в категории (REPAIR — ремонт в мастерской).
func work_rate(v: Villager, cat: StringName, building_type: StringName = &"") -> float:
	return TaskDefs.BASE_RATE.get(cat, 1.0) * suitability(v, cat, building_type)


# ---------- список задач ----------

func _ensure_jobs() -> void:
	if not _jobs_dirty and _jobs_age < TaskDefs.JOB_CACHE_TICKS:
		return
	_jobs_dirty = false
	_jobs_age = 0
	_build_jobs()


func _job(key: String, cat: StringName, kind: StringName, target: int, pos: Vector3, cap: int, pri: int, tcat: StringName, btype: StringName = &"") -> void:
	var j := {"key": key, "cat": cat, "kind": kind, "target": target, "pos": pos, "cap": cap, "pri": pri, "tcat": tcat, "btype": btype}
	_jobs.append(j)
	_job_by_key[key] = j


func _build_jobs() -> void:
	_jobs.clear()
	_job_by_key.clear()
	for id in construction.buildings:
		var b: Building = construction.buildings[id]
		if not b.is_done():
			var p := priority_of(TaskDefs.BUILD, b.id)
			if p > 0 and b.stage_paid and b.blocked == &"":
				_job("b:%d" % b.id, TaskDefs.BUILD, &"build", b.id, b.position, TaskDefs.BUILD_SLOTS, p, TaskDefs.BUILD)
		elif production.is_producing_building(b.id):
			var p := priority_of(TaskDefs.PRODUCTION, b.id)
			if p > 0 and production.needs_worker(b.id):
				var tcat := TaskDefs.REPAIR if production.active_job_kind(b.id) == &"repair" else TaskDefs.PRODUCTION
				_job("p:%d" % b.id, TaskDefs.PRODUCTION, &"produce", b.id, b.position, TaskDefs.PRODUCTION_SLOTS, p, tcat, b.type)
	var fp := priority_of(TaskDefs.FELL)
	if fp > 0 and economy.total_free_space() >= 1:
		for idx in construction.felling_indices():
			_job("f:%d" % idx, TaskDefs.FELL, &"fell", idx, world.cell_center(idx % world.size, idx / world.size), TaskDefs.FELL_SLOTS, fp, TaskDefs.FELL)
	var dp := priority_of(TaskDefs.DISMANTLE)
	if dp > 0:
		for rid in construction.open_dismantles():
			_job("d:%d" % rid, TaskDefs.DISMANTLE, &"dismantle", rid, construction.ruins[rid]["pos"], TaskDefs.DISMANTLE_SLOTS, dp, TaskDefs.DISMANTLE)
	_build_chore_jobs()


func _build_chore_jobs() -> void:
	var cp := priority_of(TaskDefs.CHORES)
	if cp > 0 and economy.total(&"logs") > TaskDefs.CHORE_LOGS_RESERVE \
			and economy.total(&"firewood") < TaskDefs.FIREWOOD_STORAGE_TARGET \
			and economy.total_free_space() >= TaskDefs.FIREWOOD_PER_LOG - 1:
		for s in economy.storages:
			if s.amount(&"logs") > 0:
				_job("c:chop:%d" % s.id, TaskDefs.CHORES, &"chop", s.id, s.position, TaskDefs.CHORE_SLOTS, cp, TaskDefs.CHORES)
	if economy.total(&"firewood") > 0:
		for id in construction.buildings:
			var b: Building = construction.buildings[id]
			if not b.is_done() or not BuildingDefs.is_housing(b.type):
				continue
			var p := priority_of(TaskDefs.CHORES, b.id)
			if p > 0 and firewood_stock(b.id) < firewood_capacity(b.id):
				_job("c:carry:%d" % b.id, TaskDefs.CHORES, &"carry", b.id, b.position, TaskDefs.CHORE_SLOTS, p, TaskDefs.CHORES)


func _recount_claims() -> void:
	_claims.clear()
	for v: Villager in villagers.values():
		var k: String = v.task.get("key", "")
		if k != "":
			_claims[k] = _claims.get(k, 0) + 1


func _score(v: Villager, job: Dictionary) -> float:
	var suit := suitability(v, job["tcat"], job["btype"])
	var dist := Vector2(job["pos"].x - v.pos.x, job["pos"].z - v.pos.z).length()
	return float(job["pri"]) * TaskDefs.PRIORITY_WEIGHT + (suit - 1.0) * TaskDefs.SUITABILITY_WEIGHT - dist * TaskDefs.DISTANCE_WEIGHT


## Лучшая задача для жителя без учёта занятости слотов (для тестов/подсказок).
func best_job_for(v: Villager) -> Dictionary:
	_ensure_jobs()
	return _pick(v, false)


func _pick(v: Villager, use_claims: bool) -> Dictionary:
	var cur: String = v.task.get("key", "")
	var best := {}
	var best_score := -INF
	for job: Dictionary in _jobs:
		var key: String = job["key"]
		if v.banned.get(key, 0.0) > _time:
			continue
		if use_claims and _claims.get(key, 0) - (1 if key == cur else 0) >= job["cap"]:
			continue
		var s := _score(v, job) + (TaskDefs.STICKY_BONUS if key == cur else 0.0)
		if s > best_score:
			best_score = s
			best = job
	return best


func _think(v: Villager) -> void:
	_ensure_jobs()
	_recount_claims()
	var best := _pick(v, true)
	if best.is_empty():
		v.task = {}
		return
	if best["key"] != v.task.get("key", ""):
		_assign(v, best)


## Назначает задачу немедленно (тесты, отладка).
func assign_now(v: Villager) -> void:
	v.think_cd = TaskDefs.ASSIGN_INTERVAL
	_jobs_dirty = true
	_think(v)


func _assign(v: Villager, job: Dictionary) -> void:
	v.task = {"kind": job["kind"], "cat": job["cat"], "key": job["key"], "target": job["target"],
		"phase": &"", "work": 0.0, "carry": 0, "src": 0}
	if job["kind"] == &"carry":
		v.task["phase"] = &"fetch"
		v.task["src"] = _nearest_storage_with(&"firewood", v.pos)
	v.path.clear()
	v.at_site = false


func _nearest_storage_with(res: StringName, from: Vector3) -> int:
	var best := 0
	var bd := INF
	for s in economy.storages:
		if s.amount(res) > 0:
			var d := Vector2(s.position.x - from.x, s.position.z - from.z).length()
			if d < bd:
				bd = d
				best = s.id
	return best


# ---------- место и радиус задачи ----------

func _building_radius(b: Building) -> float:
	return maxf(b.size().x, b.size().y) * 0.5 + 0.9


func _storage_radius(s: Storage) -> float:
	for b: Building in construction.buildings.values():
		if b.storage_id == s.id:
			return _building_radius(b)
	return 2.5


## Куда идти; null — задача потеряла цель.
func _task_pos(v: Villager, t: Dictionary) -> Variant:
	match t["kind"]:
		&"arrive":
			return hub_position()
		&"build", &"produce":
			var b := construction.get_building(t["target"])
			return b.position if b != null else null
		&"fell":
			var c := construction.index_cell(t["target"])
			return world.cell_center(c.x, c.y)
		&"dismantle":
			return construction.ruins[t["target"]]["pos"] if construction.ruins.has(t["target"]) else null
		&"chop":
			var s := economy.get_storage(t["target"])
			return s.position if s != null else null
		&"carry":
			if t["phase"] == &"deliver":
				var h := construction.get_building(t["target"])
				return h.position if h != null else null
			var s := economy.get_storage(t["src"])
			if s == null:
				return hub_position()
			return s.position
	return null


func _task_radius(t: Dictionary) -> float:
	match t["kind"]:
		&"arrive":
			return TaskDefs.ARRIVE_RADIUS_HUB
		&"build", &"produce":
			var b := construction.get_building(t["target"])
			return _building_radius(b) if b != null else 1.0
		&"fell", &"dismantle":
			return 1.7
		&"chop":
			var s := economy.get_storage(t["target"])
			return _storage_radius(s) if s != null else 2.5
		&"carry":
			if t["phase"] == &"deliver":
				var h := construction.get_building(t["target"])
				return _building_radius(h) if h != null else 1.0
			var s := economy.get_storage(t["src"])
			return _storage_radius(s) if s != null else 2.5
	return 1.0


func _alive(t: Dictionary) -> bool:
	if t["kind"] == &"arrive":
		return true
	if t["kind"] == &"carry" and t["phase"] == &"deliver":
		var h := construction.get_building(t["target"])
		return h != null and h.is_done()
	_ensure_jobs()
	return _job_by_key.has(t["key"])


# ---------- тик ----------

func tick(sim: Simulation, dt: float) -> void:
	_sim = sim
	if dt <= 0.0:
		return
	_time += dt
	_jobs_age += 1
	next_arrival_in -= dt
	if next_arrival_in <= 0.0:
		spawn_newcomer()
		_roll_arrival()
	for v: Villager in villagers.values():
		_tick_villager(v, dt)
	_tick_dog(dt)


func _tick_villager(v: Villager, dt: float) -> void:
	v.think_cd -= dt
	var t := v.task
	var carrying: bool = t.get("kind", &"") == &"carry" and t.get("phase", &"") == &"deliver"
	if t.get("kind", &"") != &"arrive" and not carrying and v.think_cd <= 0.0:
		v.think_cd = TaskDefs.ASSIGN_INTERVAL
		_think(v)
		t = v.task
	if t.is_empty():
		v.moving = false
		v.at_site = false
		return
	if not _alive(t):
		_abandon(v)
		return
	var goal = _task_pos(v, t)
	if goal == null:
		_abandon(v)
		return
	var res := _go_to(v, goal, _task_radius(t), VillagerDefs.WALK_SPEED, dt)
	if res == Go.BLOCKED:
		v.banned[t["key"]] = _time + TaskDefs.BAN_TIME
		_abandon(v)
		return
	v.at_site = res == Go.ARRIVED
	if v.at_site:
		_work(v, t, dt)


func _abandon(v: Villager) -> void:
	var t := v.task
	if t.get("kind", &"") == &"carry" and int(t.get("carry", 0)) > 0:
		economy.deposit(&"firewood", int(t["carry"]))  # несомое возвращается на склад
	v.task = {}
	v.think_cd = 0.0
	v.at_site = false
	v.moving = false


func _go_to(w: Walker, goal: Vector3, radius: float, speed: float, dt: float) -> int:
	if Vector2(goal.x - w.pos.x, goal.z - w.pos.z).length() <= radius:
		w.path.clear()
		w.moving = false
		return Go.ARRIVED
	var gc := world.cell_of(goal.x, goal.z)
	if w.path.is_empty() or w.path_goal != gc:
		if not pathfinder.is_walkable(w.pos):
			w.pos = _ground(pathfinder.nearest_walkable(w.pos))
		w.path = pathfinder.find_path(w.pos, goal)
		w.path_goal = gc
		if w.path.is_empty():
			return Go.BLOCKED
	w.advance_along(dt, speed, world)
	return Go.MOVING


func _tick_dog(dt: float) -> void:
	var hero := get_hero()
	if dog == null or hero == null:
		return
	var d := Vector2(hero.pos.x - dog.pos.x, hero.pos.z - dog.pos.z).length()
	if d > VillagerDefs.DOG_TELEPORT_DIST:
		dog.pos = _ground(pathfinder.nearest_walkable(hero.pos + Vector3(-2.0, 0.0, -1.0)))
		dog.path.clear()
	elif d > VillagerDefs.DOG_FOLLOW_DIST or not dog.path.is_empty():
		if _go_to(dog, hero.pos, 2.0, VillagerDefs.DOG_SPEED, dt) == Go.BLOCKED:
			dog.moving = false
	else:
		dog.moving = false


# ---------- работа на объекте ----------

func _work(v: Villager, t: Dictionary, dt: float) -> void:
	match t["kind"]:
		&"arrive":
			v.arriving = false
			v.task = {}
			v.think_cd = 0.0
		&"build":
			construction.add_work(&"build", t["target"], work_rate(v, TaskDefs.BUILD) * dt)
			train(v, TaskDefs.BUILD, dt)
		&"fell":
			construction.add_work(&"fell", t["target"], work_rate(v, TaskDefs.FELL) * dt)
			train(v, TaskDefs.FELL, dt)
		&"dismantle":
			construction.add_work(&"dismantle", t["target"], work_rate(v, TaskDefs.DISMANTLE) * dt)
			train(v, TaskDefs.DISMANTLE, dt)
		&"produce":
			var b := construction.get_building(t["target"])
			var cat := TaskDefs.REPAIR if production.active_job_kind(b.id) == &"repair" else TaskDefs.PRODUCTION
			production.add_work(b.id, work_rate(v, cat, b.type) * dt)
			train(v, cat, dt)
		&"chop":
			t["work"] += work_rate(v, TaskDefs.CHORES) * dt
			train(v, TaskDefs.CHORES, dt)
			if t["work"] >= TaskDefs.CHOP_WORK:
				_finish_chop(v, t)
		&"carry":
			t["work"] += work_rate(v, TaskDefs.CHORES) * dt
			train(v, TaskDefs.CHORES, dt)
			if t["phase"] == &"fetch" and t["work"] >= TaskDefs.PICKUP_WORK:
				_finish_pickup(v, t)
			elif t["phase"] == &"deliver" and t["work"] >= TaskDefs.DELIVER_WORK:
				_finish_delivery(v, t)


func _end_task(v: Villager) -> void:
	v.task = {}
	v.think_cd = 0.0


## Бревно -> дрова. Атомарно: либо оба шага, либо ничего.
func _finish_chop(v: Villager, _t: Dictionary) -> void:
	if economy.total(&"logs") >= 1 and economy.total_free_space() + 1 >= TaskDefs.FIREWOOD_PER_LOG:
		economy.consume({&"logs": 1})
		economy.deposit(&"firewood", TaskDefs.FIREWOOD_PER_LOG)
	_end_task(v)


func _finish_pickup(v: Villager, t: Dictionary) -> void:
	var room := firewood_capacity(t["target"]) - firewood_stock(t["target"])
	var n := mini(mini(TaskDefs.CARRY_CAPACITY, room), economy.total(&"firewood"))
	if n <= 0:
		_end_task(v)
		return
	economy.consume({&"firewood": n})
	t["carry"] = n
	t["phase"] = &"deliver"
	t["work"] = 0.0
	v.path.clear()


func _finish_delivery(v: Villager, t: Dictionary) -> void:
	var cap := firewood_capacity(t["target"])
	var add := mini(int(t["carry"]), maxi(0, cap - firewood_stock(t["target"])))
	house_stock[t["target"]] = firewood_stock(t["target"]) + add
	if int(t["carry"]) > add:
		economy.deposit(&"firewood", int(t["carry"]) - add)
	t["carry"] = 0
	_emit(TOPIC_CHANGED, {})
	_end_task(v)


# ---------- описание ----------

func task_text(v: Villager) -> String:
	var t := v.task
	if t.is_empty():
		return "Свободен"
	var txt := ""
	match t["kind"]:
		&"arrive":
			txt = "Идёт в посёлок"
		&"build":
			var b := construction.get_building(t["target"])
			txt = "Стройка: " + (BuildingDefs.display_name(b.type) if b != null else "?")
		&"fell":
			txt = "Вырубка леса"
		&"dismantle":
			txt = "Разбор руин"
		&"produce":
			var b := construction.get_building(t["target"])
			txt = ("Ремонт: " if production.active_job_kind(t["target"]) == &"repair" else "Работа: ") + (BuildingDefs.display_name(b.type) if b != null else "?")
		&"chop":
			txt = "Колет дрова"
		&"carry":
			txt = "Несёт дрова в дом" if t["phase"] == &"deliver" else "Берёт дрова на складе"
	if t["kind"] != &"arrive" and not v.at_site:
		txt = "Идёт: " + txt
	return txt


# ---------- сохранение ----------

func get_save_key() -> StringName:
	return &"villagers"


func save_state() -> Dictionary:
	var list := []
	for id in villagers:
		list.append((villagers[id] as Villager).to_dict())
	var pr := {}
	for k in priorities:
		pr[String(k)] = priorities[k]
	var bp := {}
	for k in building_priorities:
		bp[str(k)] = building_priorities[k]
	var hs := {}
	for k in house_stock:
		hs[str(k)] = house_stock[k]
	return {
		"next_id": _next_id, "next_arrival_in": next_arrival_in,
		"villagers": list, "dog": dog.to_dict() if dog != null else {},
		"priorities": pr, "building_priorities": bp, "house_stock": hs,
	}


func load_state(d: Dictionary) -> void:
	villagers.clear()
	building_priorities.clear()
	house_stock.clear()
	reset_priorities()
	if d.get("villagers") is Array:
		for e in d["villagers"]:
			if e is Dictionary:
				var v := Villager.from_dict(e)
				if v.id > 0:
					villagers[v.id] = v
	if d.get("priorities") is Dictionary:
		for k in d["priorities"]:
			if TaskDefs.CATEGORIES.has(StringName(String(k))):
				priorities[StringName(String(k))] = clampi(SaveManager.to_int(d["priorities"][k], 1), TaskDefs.PRIORITY_MIN, TaskDefs.PRIORITY_MAX)
	if d.get("building_priorities") is Dictionary:
		for k in d["building_priorities"]:
			building_priorities[SaveManager.to_int(k, -1)] = clampi(SaveManager.to_int(d["building_priorities"][k], 1), TaskDefs.PRIORITY_MIN, TaskDefs.PRIORITY_MAX)
	if d.get("house_stock") is Dictionary:
		for k in d["house_stock"]:
			house_stock[SaveManager.to_int(k, -1)] = maxi(0, SaveManager.to_int(d["house_stock"][k], 0))
	dog = Dog.new()
	if d.get("dog") is Dictionary and not (d["dog"] as Dictionary).is_empty():
		dog.load_dict(d["dog"])
	elif get_hero() != null:
		dog.pos = get_hero().pos
	_next_id = SaveManager.to_int(d.get("next_id"), 1)
	for id in villagers:
		_next_id = maxi(_next_id, id + 1)
	next_arrival_in = float(d.get("next_arrival_in", 0.0))
	if next_arrival_in <= 0.0:
		_roll_arrival()
	_jobs_dirty = true
	_emit(TOPIC_CHANGED, {})
