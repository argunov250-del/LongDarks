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
## любая система смерти обязана проверять Villager.can_die().
##
## Шаг 11 (потребности, см. NeedsSystem/NeedsDefs): нужные дела (поесть, попить, лечь спать,
## лечиться, согреться) приоритетнее работы; нужды снижают work_rate.

const TOPIC_ARRIVED := &"villager_arrived"      # {id, name, profession}
const TOPIC_CHANGED := &"villagers_changed"     # состав/приоритеты изменились
const TOPIC_SICK := &"villager_sick"            # {id, name, profession}
const TOPIC_RECOVERED := &"villager_recovered"  # {id, name, profession}
const TOPIC_DIED := &"villager_died"            # {id, name, profession, cause}

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
var weather: WeatherSystem                # погода: пожар, паводок (шаг 14), null — нет
var household: HouseholdSystem          # запасы домов и столовых, огороды, сараи (шаг 10b)
var needs: NeedsSystem                  # потребности, расселение, болезни (шаг 11)
## Потребности и ночной сон включены (тесты старых шагов отключают).
var needs_enabled: bool = true:
	set(value):
		needs_enabled = value
		if household != null:
			household.simulate_heat = value
## ХУКИ сезонов (SeasonSystem): распутица 0..1 (ХУК для техники) и множитель шага жителей.
var mud_level: float = 0.0
var walk_speed_multiplier: float = 1.0
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
	household = HouseholdSystem.new(construction, economy)
	needs = NeedsSystem.new(self)
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
	household.load_state({})
	if _sim != null and _sim.clock.get_total_usec() == 0:
		_sim.clock.set_total_seconds(NeedsDefs.START_HOUR / 24.0 * float(_sim.clock.day_length_usec) / GameClock.USEC)
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


## Смерть жителя (болезнь, голод, холод...): событие + удаление. Герой не умирает.
func kill_villager(id: int, cause: StringName = &"") -> bool:
	var v := get_villager(id)
	if v == null or not v.can_die():
		return false
	var payload := {"id": v.id, "name": v.display_name, "profession": v.profession, "cause": cause}
	_drop_load(v)
	if not remove_villager(id):
		return false
	needs.assign_homes()
	_emit(TOPIC_DIED, payload)
	return true


## ХУК СЕЗОНОВ/ПОГОДЫ: холод снаружи 0 (тепло) .. 1 (лютый мороз).
func set_outdoor_cold(x: float) -> void:
	household.outdoor_cold = clampf(x, 0.0, 1.0)


func outdoor_cold() -> float:
	return household.outdoor_cold


## ХУК СЕЗОНОВ: общий множитель расхода (еда, вода, тепло, дрова); зима > 1.
func set_consumption_multiplier(x: float) -> void:
	household.consumption_multiplier = maxf(0.0, x)


func consumption_multiplier() -> float:
	return household.consumption_multiplier


## ХУК ссор/ухода к соседям: сводная «нужда» жителя 0..1.
func suffering(v: Villager) -> float:
	return NeedsDefs.suffering(v.needs, v.sick)


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
	for n in NeedsDefs.NEWCOMER_START:
		v.set_need(n, NeedsDefs.NEWCOMER_START[n])
	v.pos = _ground(_edge_spawn())
	v.task = {"kind": &"arrive", "cat": &"", "key": "arrive", "target": 0, "phase": &"", "work": 0.0, "carry": 0, "src": 0, "res": &"", "dest": &""}
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


# ---------- запасы жилья ----------

## Вместимость поленницы жилья.
func firewood_capacity(building_id: int) -> int:
	var b := construction.get_building(building_id)
	return BuildingDefs.firewood_capacity(b.type) if b != null and b.is_done() else 0


## Дров на поленнице (в печи — stove_stock).
func firewood_stock(building_id: int) -> int:
	var h := household.home(building_id)
	return h.woodpile if h != null else 0


func stove_stock(building_id: int) -> int:
	var h := household.home(building_id)
	return h.stove if h != null else 0


## Для шага 11: есть ли еда в доме / ближайшая столовая с едой для жителя (id здания или -1).
func house_has_food(building_id: int) -> bool:
	return household.house_has_food(building_id)


func canteen_for(v: Villager) -> int:
	return household.canteen_for(v)


# ---------- скорость и пригодность ----------

func profession_multiplier(v: Villager, cat: StringName, building_type: StringName = &"") -> float:
	if cat == TaskDefs.CHORES and building_type == &"canteen":
		return TaskDefs.CANTEEN_COOK_BONUS if v.profession == &"cook" else 1.0
	if cat == TaskDefs.CHORES and building_type == &"hospital":
		return 1.0
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
	return TaskDefs.BASE_RATE.get(cat, 1.0) * suitability(v, cat, building_type) * needs_multiplier(v)


## Множитель скорости работы от нужд (еда, вода, тепло, отдых, здоровье); 1.0 — всё в порядке.
func needs_multiplier(v: Villager) -> float:
	return NeedsDefs.rate_multiplier(v.needs) if needs_enabled else 1.0


# ---------- список задач ----------

func _ensure_jobs() -> void:
	if not _jobs_dirty and _jobs_age < TaskDefs.JOB_CACHE_TICKS:
		return
	_jobs_dirty = false
	_jobs_age = 0
	_build_jobs()


func _job(key: String, cat: StringName, kind: StringName, target: int, pos: Vector3, cap: int, pri: int, tcat: StringName, btype: StringName = &"", dest: StringName = &"") -> void:
	var j := {"key": key, "cat": cat, "kind": kind, "target": target, "pos": pos, "cap": cap, "pri": pri, "tcat": tcat, "btype": btype, "dest": dest}
	_jobs.append(j)
	_job_by_key[key] = j


func _build_jobs() -> void:
	_jobs.clear()
	_job_by_key.clear()
	var outdoor_ok := construction.build_speed_multiplier > 0.0  # погода стопорит уличную работу
	if household.shelter_required:
		return  # метель/ураган/гроза: все сидят по домам, никакой работы (нужные дела — в NeedsSystem)
	for id in construction.buildings:
		var b: Building = construction.buildings[id]
		if not b.is_done():
			var p := priority_of(TaskDefs.BUILD, b.id)
			if p > 0 and b.stage_paid and b.blocked == &"" and outdoor_ok:
				_job("b:%d" % b.id, TaskDefs.BUILD, &"build", b.id, b.position, TaskDefs.BUILD_SLOTS, p, TaskDefs.BUILD)
		elif b.damaged and not b.burning:
			var p := priority_of(TaskDefs.BUILD, b.id)
			if p > 0 and b.repair_paid and outdoor_ok:
				_job("m:%d" % b.id, TaskDefs.BUILD, &"mend", b.id, b.position, TaskDefs.BUILD_SLOTS, p, TaskDefs.BUILD)
		elif b.operational() and production.is_producing_building(b.id):
			var p := priority_of(TaskDefs.PRODUCTION, b.id)
			if p > 0 and production.needs_worker(b.id):
				var tcat := TaskDefs.REPAIR if production.active_job_kind(b.id) == &"repair" else TaskDefs.PRODUCTION
				_job("p:%d" % b.id, TaskDefs.PRODUCTION, &"produce", b.id, b.position, TaskDefs.PRODUCTION_SLOTS, p, tcat, b.type)
	var fp := priority_of(TaskDefs.FELL)
	if fp > 0 and outdoor_ok and economy.total_free_space() >= 1:
		for idx in construction.felling_indices():
			_job("f:%d" % idx, TaskDefs.FELL, &"fell", idx, world.cell_center(idx % world.size, idx / world.size), TaskDefs.FELL_SLOTS, fp, TaskDefs.FELL)
	var dp := priority_of(TaskDefs.DISMANTLE)
	if dp > 0 and outdoor_ok:
		for rid in construction.open_dismantles():
			_job("d:%d" % rid, TaskDefs.DISMANTLE, &"dismantle", rid, construction.ruins[rid]["pos"], TaskDefs.DISMANTLE_SLOTS, dp, TaskDefs.DISMANTLE)
	_build_chore_jobs()
	_build_treat_jobs()


## Больница с пациентами ждёт персонал: врач (профессия) предпочтительнее, без врачей — любой.
func _build_treat_jobs() -> void:
	if not needs_enabled:
		return
	for id in needs.hospital_ids():
		var p: int = building_priorities.get(id, NeedsDefs.TREAT_PRIORITY)
		if p > 0 and not needs.patients(id).is_empty():
			var b := construction.get_building(id)
			_job("t:%d" % id, TaskDefs.CHORES, &"treat", id, b.position, NeedsDefs.HOSPITAL_STAFF_SLOTS, p, TaskDefs.CHORES, &"hospital")


func _day() -> int:
	return _sim.clock.get_day() if _sim != null else 0


func _build_chore_jobs() -> void:
	household.sync()
	var well_ok := _has_well()
	var logs_ok := economy.total(&"logs") > TaskDefs.CHORE_LOGS_RESERVE
	var firewood_ok := economy.total(&"firewood") > 0
	var day := _day()
	for id in household.home_ids():
		var b := construction.get_building(id)
		if b == null or not b.is_done() or b.burning or b.flooded:
			continue
		var p := priority_of(TaskDefs.CHORES, id)
		if p <= 0:
			continue
		var cap := TaskDefs.CHORE_SLOTS
		if household.wood_room(id) > 0:
			if logs_ok:
				_job("c:chop:%d" % id, TaskDefs.CHORES, &"chop", id, household.chop_pos(b), cap, p, TaskDefs.CHORES)
			if firewood_ok:
				_job("c:carry:%d" % id, TaskDefs.CHORES, &"carry", id, b.position, cap, p, TaskDefs.CHORES)
		if well_ok and household.water_room(id) > 0:
			_job("c:water:%d" % id, TaskDefs.CHORES, &"water", id, b.position, cap, p, TaskDefs.CHORES, &"", &"house")
		if household.can_plant(id, day) or household.can_harvest(id, day):
			_job("c:garden:%d" % id, TaskDefs.CHORES, &"garden", id, household.garden_pos(b), cap, p, TaskDefs.CHORES)
	var food_ok := _storage_with_food(Vector3.ZERO) > 0
	for id in household.canteen_ids():
		var b := construction.get_building(id)
		if b == null or not b.is_done():
			continue
		var p := priority_of(TaskDefs.CHORES, id)
		if p <= 0:
			continue
		var h := household.canteen(id)
		if well_ok and household.water_room(id) > 0:
			_job("c:water:%d" % id, TaskDefs.CHORES, &"water", id, b.position, TaskDefs.CHORE_SLOTS, p, TaskDefs.CHORES, &"canteen", &"canteen")
		if food_ok and h.food.free_space() > 0:
			_job("c:food:%d" % id, TaskDefs.CHORES, &"food", id, b.position, TaskDefs.CHORE_SLOTS, p, TaskDefs.CHORES, &"canteen", &"canteen")


func _has_well() -> bool:
	return household.nearest_well(Vector3.ZERO) >= 0


## Ближайший склад с любой едой (id) или 0.
func _storage_with_food(from: Vector3) -> int:
	var best := 0
	var bd := INF
	for s in economy.storages:
		for res in s.contents:
			if ResourceDefs.category(res) == ResourceDefs.Category.FOOD:
				var d := Vector2(s.position.x - from.x, s.position.z - from.z).length()
				if d < bd:
					bd = d
					best = s.id
				break
	return best


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
		if job["kind"] == &"treat" and not needs.can_treat(v):
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
	if needs_enabled and not v.arriving:
		var nj := needs.job_for(v)
		if not nj.is_empty():
			if nj["key"] != v.task.get("key", ""):
				_assign(v, nj)
				_jobs_dirty = true
			return
		if NeedsSystem.is_need_kind(v.task.get("kind", &"")) and v.task.get("kind", &"") != &"treat":
			_abandon(v)
	var best := _pick(v, true)
	if best.is_empty():
		_drop_load(v)
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
	_drop_load(v)
	v.task = {"kind": job["kind"], "cat": job["cat"], "key": job["key"], "target": job["target"],
		"phase": &"", "work": 0.0, "carry": 0, "src": 0, "res": &"", "dest": job.get("dest", &"")}
	match job["kind"]:
		&"carry":
			v.task["phase"] = &"fetch"
			v.task["src"] = _nearest_storage_with(&"firewood", v.pos)
		&"chop":
			v.task["phase"] = &"fetch"
			v.task["src"] = _nearest_storage_with(&"logs", v.pos)
		&"food":
			v.task["phase"] = &"fetch"
			v.task["src"] = _storage_with_food(v.pos)
		&"water", &"extinguish":
			v.task["phase"] = &"fetch"
			v.task["src"] = household.nearest_well(v.pos)  # id здания-колодца
		&"garden":
			v.task["phase"] = &"work"
		&"stoke":
			v.task["phase"] = &"fetch"  # к поленнице за охапкой, затем к печи
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
		&"build", &"produce", &"mend":
			var b := construction.get_building(t["target"])
			return b.position if b != null else null
		&"fell":
			var c := construction.index_cell(t["target"])
			return world.cell_center(c.x, c.y)
		&"dismantle":
			return construction.ruins[t["target"]]["pos"] if construction.ruins.has(t["target"]) else null
		&"chop", &"carry", &"water", &"food", &"garden", &"stoke", &"extinguish":
			return _haul_pos(t)
		&"eat", &"drink":
			var mb := construction.get_building(t["target"])
			if mb == null:
				return null
			return household.door_pos(mb) if t["dest"] == &"home" else mb.position
		&"sleep", &"warm", &"shelter":
			if t["target"] == 0:
				return v.pos
			var hb := construction.get_building(t["target"])
			return household.door_pos(hb) if hb != null else null
		&"heal", &"treat":
			var hosp := construction.get_building(t["target"])
			return hosp.position if hosp != null else null
	return null


func _task_radius(t: Dictionary) -> float:
	match t["kind"]:
		&"arrive":
			return TaskDefs.ARRIVE_RADIUS_HUB
		&"build", &"produce", &"mend":
			var b := construction.get_building(t["target"])
			return _building_radius(b) if b != null else 1.0
		&"fell", &"dismantle":
			return 1.7
		&"chop", &"carry", &"water", &"food", &"garden", &"stoke", &"extinguish":
			return _haul_radius(t)
		&"eat", &"drink":
			if t["dest"] == &"home":
				return NeedsDefs.HOME_REACH_RADIUS
			var cb := construction.get_building(t["target"])
			return _building_radius(cb) if cb != null else 1.0
		&"sleep", &"warm", &"shelter":
			return NeedsDefs.HOME_REACH_RADIUS
		&"heal", &"treat":
			var hb := construction.get_building(t["target"])
			return _building_radius(hb) if hb != null else 1.0
	return 1.0


## Где происходит текущая фаза бытовой задачи (дрова, вода, еда, огород); null — цель потеряна.
func _haul_pos(t: Dictionary) -> Variant:
	var house := construction.get_building(t["target"])
	match t["phase"]:
		&"fetch":
			if t["kind"] == &"stoke":
				return household.woodpile_pos(house) if house != null else null
			if t["kind"] == &"water" or t["kind"] == &"extinguish":
				var w := construction.get_building(t["src"])
				return w.position if w != null else null
			var s := economy.get_storage(t["src"])
			return s.position if s != null else hub_position()
		&"chop":
			return household.chop_pos(house) if house != null else null
		&"work":
			return household.garden_pos(house) if house != null else null
		&"deliver":
			if t["kind"] == &"extinguish":
				return weather.fire.target_pos(t["dest"], t["target"]) if weather != null else null
			if house == null:
				return null
			match t["dest"]:
				&"woodpile":
					return household.woodpile_pos(house)
				&"canteen":
					return house.position
				_:
					return household.door_pos(house)
	return null


func _haul_radius(t: Dictionary) -> float:
	match t["phase"]:
		&"fetch":
			if t["kind"] == &"stoke":
				return HouseholdDefs.SPOT_RADIUS
			if t["kind"] == &"water" or t["kind"] == &"extinguish":
				var w := construction.get_building(t["src"])
				return _building_radius(w) if w != null else 1.0
			var s := economy.get_storage(t["src"])
			return _storage_radius(s) if s != null else 2.5
		&"deliver":
			if t["kind"] == &"extinguish":
				if t["dest"] == &"building":
					var fb := construction.get_building(t["target"])
					return _building_radius(fb) if fb != null else 1.7
				return 1.7
			if t["dest"] == &"canteen":
				var c := construction.get_building(t["target"])
				return _building_radius(c) if c != null else 1.0
	return HouseholdDefs.SPOT_RADIUS


## Задача уже взяла груз/дошла до дела: не пересматривается, пока не доставит.
func _committed(t: Dictionary) -> bool:
	return t.get("kind", &"") == &"arrive" or t.get("phase", &"") == &"deliver"


func _alive(t: Dictionary) -> bool:
	if t["kind"] == &"arrive":
		return true
	if t["kind"] == &"extinguish":
		return weather != null and weather.fire.is_burning(t["dest"], t["target"])
	if NeedsSystem.is_need_kind(t["kind"]) and t["kind"] != &"treat":
		return t["target"] == 0 or construction.get_building(t["target"]) != null
	if t["phase"] == &"chop" or t["phase"] == &"deliver":
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
	household.tick(sim, dt)
	if needs_enabled:
		needs.tick(dt)
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
	if not _committed(t) and v.think_cd <= 0.0:
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
	var res := _go_to(v, goal, _task_radius(t), VillagerDefs.WALK_SPEED * walk_speed_multiplier, dt)
	if res == Go.BLOCKED:
		v.banned[t["key"]] = _time + TaskDefs.BAN_TIME
		_abandon(v)
		return
	v.at_site = res == Go.ARRIVED
	if v.at_site:
		_work(v, t, dt)


## Несомое возвращается на склад (вода выливается).
func _drop_load(v: Villager) -> void:
	var t := v.task
	if int(t.get("carry", 0)) > 0 and t.get("res", &"") != &"water":
		economy.deposit(t.get("res", &"firewood"), int(t["carry"]))
		t["carry"] = 0


func _abandon(v: Villager) -> void:
	_drop_load(v)
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
		&"mend":
			construction.add_work(&"repair", t["target"], work_rate(v, TaskDefs.BUILD) * dt)
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
		&"eat", &"drink":
			_work_meal(v, t, dt)
		&"sleep", &"warm", &"heal", &"treat", &"shelter":
			pass  # восстановление и лечение — в NeedsSystem.tick, пока житель на месте
		&"chop", &"carry", &"water", &"food", &"garden", &"stoke", &"extinguish":
			t["work"] += work_rate(v, TaskDefs.CHORES) * dt
			train(v, TaskDefs.CHORES, dt)
			var need := _phase_work(t)
			if need < 0.0:
				_end_task(v)
			elif t["work"] >= need:
				_finish_phase(v, t)


## Приём пищи/воды: по единице из запаса дома или столовой (порции по EAT_UNIT_TIME).
func _work_meal(v: Villager, t: Dictionary, dt: float) -> void:
	var eating: bool = t["kind"] == &"eat"
	t["work"] += dt
	if t["work"] < (NeedsDefs.EAT_UNIT_TIME if eating else NeedsDefs.DRINK_UNIT_TIME):
		return
	t["work"] = 0.0
	var h := household.stock_of(t["target"])
	if h == null:
		_end_task(v)
		return
	var gain := 0.0
	if eating:
		var res := _meal_food(h.food)
		if res == &"":
			_end_task(v)
			return
		h.food.remove(res, 1)
		gain = NeedsDefs.FOOD_VALUE.get(res, NeedsDefs.FOOD_PER_UNIT)
	else:
		if h.water <= 0:
			_end_task(v)
			return
		h.water -= 1
		gain = NeedsDefs.WATER_PER_UNIT
	var n := NeedsDefs.FOOD if eating else NeedsDefs.WATER
	v.set_need(n, v.need(n) + gain)
	if v.need(n) >= NeedsDefs.MEAL_FULL:
		_end_task(v)


## Что съесть первым: сначала скоропортящееся.
func _meal_food(s: Storage) -> StringName:
	var best := &""
	var br := -1.0
	for res in s.contents:
		var r := ResourceDefs.spoil_rate(res)
		if s.contents[res] > 0 and (r > br or (is_equal_approx(r, br) and String(res) < String(best))):
			br = r
			best = res
	return best


func _end_task(v: Villager) -> void:
	v.task = {}
	v.think_cd = 0.0


## Работа текущей фазы бытовой задачи; -1 — делать больше нечего (задача снимается).
func _phase_work(t: Dictionary) -> float:
	match t["phase"]:
		&"fetch":
			return HouseholdDefs.WELL_DRAW_WORK * household.well_work_multiplier if (t["kind"] == &"water" or t["kind"] == &"extinguish") else TaskDefs.PICKUP_WORK
		&"chop":
			return TaskDefs.CHOP_WORK * float(int(t["carry"]))
		&"deliver":
			return TaskDefs.DELIVER_WORK
		&"work":
			var h := household.home(t["target"])
			if h == null:
				return -1.0
			match h.garden_state:
				Household.GARDEN_EMPTY:
					return HouseholdDefs.PLANT_WORK
				Household.GARDEN_RIPE:
					return HouseholdDefs.HARVEST_WORK
			return -1.0
	return -1.0


func _finish_phase(v: Villager, t: Dictionary) -> void:
	match t["phase"]:
		&"fetch":
			_finish_fetch(v, t)
		&"chop":
			t["carry"] = int(t["carry"]) * TaskDefs.FIREWOOD_PER_LOG
			t["res"] = &"firewood"
			_start_deliver(v, t)
		&"deliver":
			_finish_delivery(v, t)
		&"work":
			var id: int = t["target"]
			if household.home(id).garden_state == Household.GARDEN_EMPTY:
				household.plant(id)
				_end_task(v)
			else:
				var crop := household.harvest(id)
				if crop.is_empty():
					_end_task(v)
					return
				t["res"] = crop["res"]
				t["carry"] = crop["n"]
				t["dest"] = &"house"
				_start_deliver(v, t)


func _start_deliver(v: Villager, t: Dictionary) -> void:
	if t["res"] == &"firewood":
		t["dest"] = &"stove" if household.stove_demand(t["target"]) > 0 else &"woodpile"
	t["phase"] = &"deliver"
	t["work"] = 0.0
	v.path.clear()


## Погрузка на источнике: склад (дрова, брёвна, еда) или колодец (вода в вёдра).
func _finish_fetch(v: Villager, t: Dictionary) -> void:
	var target: int = t["target"]
	var n := 0
	match t["kind"]:
		&"stoke":
			var hh := household.home(target)
			n = mini(mini(TaskDefs.CARRY_CAPACITY, household.stove_demand(target)), hh.woodpile if hh != null else 0)
			t["res"] = &"firewood"
			if n > 0:
				hh.woodpile -= n
		&"carry":
			n = mini(mini(TaskDefs.CARRY_CAPACITY, household.wood_room(target)), economy.total(&"firewood"))
			t["res"] = &"firewood"
			if n > 0:
				economy.consume({&"firewood": n})
		&"chop":
			var spare := economy.total(&"logs") - TaskDefs.CHORE_LOGS_RESERVE
			var want := int(ceil(float(household.wood_room(target)) / float(TaskDefs.FIREWOOD_PER_LOG)))
			n = mini(mini(TaskDefs.CHOP_LOGS_PER_TRIP, spare), want)
			t["res"] = &"logs"
			if n > 0:
				economy.consume({&"logs": n})
		&"water":
			n = mini(HouseholdDefs.WATER_CARRY, household.water_room(target))
			t["res"] = &"water"
		&"extinguish":
			n = HouseholdDefs.WATER_CARRY
			t["res"] = &"water"
		&"food":
			var s := economy.get_storage(t["src"])
			var res := _best_food(s)
			if res != &"":
				n = mini(mini(TaskDefs.CARRY_CAPACITY, s.amount(res)), household.canteen(target).food.free_space())
				t["res"] = res
				if n > 0:
					s.remove(res, n)
	if n <= 0:
		_end_task(v)
		return
	t["carry"] = n
	if t["kind"] == &"chop":
		t["phase"] = &"chop"
		t["work"] = 0.0
		v.path.clear()
	else:
		if t["kind"] == &"water":
			t["dest"] = &"canteen" if household.canteen(target) != null else &"house"
		_start_deliver(v, t)


func _best_food(s: Storage) -> StringName:
	var best := &""
	var most := 0
	if s == null:
		return best
	for res in s.contents:
		if ResourceDefs.category(res) == ResourceDefs.Category.FOOD and s.contents[res] > most:
			most = s.contents[res]
			best = res
	return best


## Выгрузка: дрова в печь/на поленницу, вода и еда в запас дома или столовой.
func _finish_delivery(v: Villager, t: Dictionary) -> void:
	if t["kind"] == &"extinguish":
		var n_w := int(t["carry"])
		t["carry"] = 0
		if weather != null:
			weather.douse(t["dest"], t["target"], n_w)
		_end_task(v)
		return
	var target: int = t["target"]
	var n := int(t["carry"])
	var res: StringName = t["res"]
	var added := 0
	match res:
		&"firewood":
			added = household.add_firewood(target, n, t["dest"] == &"stove")
		&"water":
			added = household.add_water(target, n)
		_:
			added = household.add_food(target, res, n)
	if n > added and res != &"water":
		economy.deposit(res, n - added)  # не влезло — назад на склад
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
		&"mend":
			var mb := construction.get_building(t["target"])
			txt = "Чинит после пожара: " + (BuildingDefs.display_name(mb.type) if mb != null else "?")
		&"produce":
			var b := construction.get_building(t["target"])
			txt = ("Ремонт: " if production.active_job_kind(t["target"]) == &"repair" else "Работа: ") + (BuildingDefs.display_name(b.type) if b != null else "?")
		&"chop":
			if t["phase"] == &"deliver":
				txt = "Несёт дрова к печи" if t["dest"] == &"stove" else "Складывает дрова на поленницу"
			else:
				txt = "Колет дрова" if t["phase"] == &"chop" else "Берёт брёвна на складе"
		&"carry":
			if t["phase"] == &"deliver":
				txt = "Несёт дрова к печи" if t["dest"] == &"stove" else "Складывает дрова на поленницу"
			else:
				txt = "Берёт дрова на складе"
		&"water":
			txt = ("Несёт воду в столовую" if t["dest"] == &"canteen" else "Несёт воду в дом") if t["phase"] == &"deliver" else "Набирает воду из колодца"
		&"food":
			txt = "Несёт еду в столовую" if t["phase"] == &"deliver" else "Берёт еду на складе"
		&"garden":
			if t["phase"] == &"deliver":
				txt = "Несёт урожай в дом"
			else:
				var h := household.home(t["target"])
				txt = "Сажает на огороде" if h != null and h.garden_state == Household.GARDEN_EMPTY else "Собирает урожай"
	match t["kind"]:
		&"eat":
			txt = "Обедает в столовой" if t["dest"] == &"canteen" else "Ест дома"
		&"drink":
			txt = "Пьёт в столовой" if t["dest"] == &"canteen" else "Пьёт воду дома"
		&"sleep":
			if v.sick:
				txt = "Болеет, отлёживается"
			elif t["target"] == 0:
				txt = "Спит под открытым небом"
			else:
				txt = "Спит дома"
		&"warm":
			txt = "Греется дома"
		&"shelter":
			txt = "Пережидает непогоду дома" if t["target"] > 0 else "Пережидает непогоду"
		&"extinguish":
			txt = "Несёт воду тушить пожар" if t["phase"] == &"deliver" else "Набирает воду для тушения"
		&"stoke":
			txt = "Топит печь: несёт дрова" if t["phase"] == &"deliver" else "Берёт дрова на поленнице"
		&"heal":
			txt = "Лечится в больнице"
		&"treat":
			txt = "Лечит больных"
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
	return {
		"next_id": _next_id, "next_arrival_in": next_arrival_in,
		"villagers": list, "dog": dog.to_dict() if dog != null else {},
		"priorities": pr, "building_priorities": bp, "household": household.save_state(),
	}


func load_state(d: Dictionary) -> void:
	villagers.clear()
	building_priorities.clear()
	household.load_state(d.get("household", {}) if d.get("household") is Dictionary else {})
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
