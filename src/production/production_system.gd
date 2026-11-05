class_name ProductionSystem
extends SimSystem
## Производство: каждое ЗАВЕРШЁННОЕ здание с рецептом работает циклами.
## Старт цикла: все входы списываются атомарно через EconomySystem.consume
## (нет входа — ожидание, stall &"no_input"). Выход кладётся по окончании цикла
## целиком; нет места на складах — stall &"no_space", готовый цикл ждёт, товары
## не теряются. Пауза замораживает здание целиком (готовый цикл тоже ждёт).
##
## Мастерская дополнительно ремонтирует Repairable (см. repairable.gd): пока в
## её очереди есть задания, шаги ремонта идут вместо рецепта (на границе циклов).
##
## Состояние здания: {recipe, phase, progress, paused, stall, job}
##   phase: &"idle" | &"running"; job: &"recipe" | &"repair" (при running);
##   stall: &"" | &"no_input" | &"no_space".

const TOPIC_STARTED := &"production_started"      # {id, recipe}
const TOPIC_FINISHED := &"production_finished"    # {id, recipe, outputs}
const TOPIC_STALLED := &"production_stalled"      # {id, reason} — при смене причины
const TOPIC_REPAIR_PROGRESS := &"repair_progress" # {id (мастерская), target, condition}
const TOPIC_REPAIR_DONE := &"repair_done"         # {id (мастерская), target}
const TOPIC_CHANGED := &"production_changed"      # пауза/рецепт/очередь изменились

const IDLE := &"idle"
const RUNNING := &"running"

var construction: ConstructionSystem
var economy: EconomySystem

var _states: Dictionary = {}       # int building id -> Dictionary
var _queues: Dictionary = {}       # int workshop id -> Array[StringName]
var _repairables: Dictionary = {}  # StringName -> Repairable
var _saved_cond: Dictionary = {}   # StringName -> float (для ещё не зарегистрированных)
var _sim: Simulation
## true: рецепт/ремонт идут только пока у здания есть работник (add_work от жителя);
## false (по умолчанию): плейсхолдер Recipes.WORKER_RATE.
var external_work: bool = false
var _ext_work: Dictionary = {}     # int building id -> работа за тик


func _init(construction_in: ConstructionSystem, economy_in: EconomySystem) -> void:
	construction = construction_in
	economy = economy_in


func attach(sim: Simulation) -> void:
	_sim = sim


# ---------- запросы ----------

func is_producing_building(id: int) -> bool:
	var b := construction.get_building(id)
	return b != null and b.is_done() and Recipes.is_production(b.type)


func get_state(id: int) -> Dictionary:
	if not is_producing_building(id):
		return {}
	return _state(construction.get_building(id))


func recipe_of(id: int) -> StringName:
	return get_state(id).get("recipe", &"")


func is_paused(id: int) -> bool:
	return get_state(id).get("paused", false)


func stall_reason(id: int) -> StringName:
	return get_state(id).get("stall", &"")


## Доля текущего цикла/шага [0,1].
func progress_fraction(id: int) -> float:
	var s := get_state(id)
	if s.is_empty() or s["phase"] != RUNNING:
		return 0.0
	var d := _duration(s)
	return 1.0 if d <= 0.0 else clampf(s["progress"] / d, 0.0, 1.0)


## Нужен ли сейчас работник: цикл идёт, либо можно начать (хватает входов/запчастей).
## Не нужен: пауза, ждёт склад/сырьё, цикл дошёл до конца.
func needs_worker(id: int) -> bool:
	var s := get_state(id)
	if s.is_empty() or s["paused"]:
		return false
	if s["phase"] == RUNNING:
		return s["progress"] < _duration(s)
	var queue: Array = _queues.get(id, [])
	if not queue.is_empty():
		var r := get_repairable(queue[0])
		if r != null and r.needs_repair() and economy.can_afford(r.get_repair_cost()):
			return true
	return economy.can_afford(Recipes.inputs(s["recipe"]))


## &"repair" | &"recipe": что делает (или начнёт делать) работник здания.
func active_job_kind(id: int) -> StringName:
	var s := get_state(id)
	if s.is_empty():
		return &"recipe"
	if s["phase"] == RUNNING:
		return &"repair" if s["job"] == &"repair" else &"recipe"
	var queue: Array = _queues.get(id, [])
	if not queue.is_empty():
		var r := get_repairable(queue[0])
		if r != null and r.needs_repair() and economy.can_afford(r.get_repair_cost()):
			return &"repair"
	return &"recipe"


## Работа жителя в здании (игровые секунды рецепта). Без external_work игнорируется.
func add_work(id: int, amount: float) -> void:
	if external_work and amount > 0.0:
		_ext_work[id] = _ext_work.get(id, 0.0) + amount


func available_recipes(id: int) -> Array[StringName]:
	var b := construction.get_building(id)
	return Recipes.for_building(b.type) if b != null else ([] as Array[StringName])


# ---------- управление игроком ----------

func set_paused(id: int, paused: bool) -> bool:
	if not is_producing_building(id):
		return false
	var s := _state(construction.get_building(id))
	if s["paused"] != paused:
		s["paused"] = paused
		_emit(TOPIC_CHANGED, {"id": id})
	return true


func toggle_pause(id: int) -> bool:
	return set_paused(id, not is_paused(id))


## Выбор рецепта. Нельзя, пока цикл идёт (входы уже списаны — иначе потеря товара).
func set_recipe(id: int, recipe: StringName) -> bool:
	if not is_producing_building(id):
		return false
	var b := construction.get_building(id)
	if Recipes.building_of(recipe) != b.type:
		return false
	var s := _state(b)
	if s["phase"] == RUNNING:
		return false
	s["recipe"] = recipe
	s["stall"] = &""
	_emit(TOPIC_CHANGED, {"id": id})
	return true


# ---------- ремонт ----------

func register_repairable(r: Repairable) -> void:
	if r == null or r.repair_id == &"":
		return
	if _saved_cond.has(r.repair_id):
		r.condition = clampf(float(_saved_cond[r.repair_id]), 0.0, 1.0)
		_saved_cond.erase(r.repair_id)
	_repairables[r.repair_id] = r


func unregister_repairable(repair_id: StringName) -> void:
	_repairables.erase(repair_id)
	for q in _queues.values():
		(q as Array).erase(repair_id)


func get_repairable(repair_id: StringName) -> Repairable:
	return _repairables.get(repair_id)


func repair_queue(workshop_id: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for v in _queues.get(workshop_id, []):
		out.append(v)
	return out


func is_repair_queued(repair_id: StringName) -> bool:
	for q in _queues.values():
		if (q as Array).has(repair_id):
			return true
	return false


## Ставит объект в очередь мастерской. false: нет мастерской/объекта,
## объект исправен или уже в какой-то очереди.
func queue_repair(workshop_id: int, repair_id: StringName) -> bool:
	var b := construction.get_building(workshop_id)
	if b == null or not b.is_done() or not Recipes.can_repair(b.type):
		return false
	var r := get_repairable(repair_id)
	if r == null or not r.needs_repair() or is_repair_queued(repair_id):
		return false
	var q: Array = _queues.get(workshop_id, [])
	q.append(repair_id)
	_queues[workshop_id] = q
	_emit(TOPIC_CHANGED, {"id": workshop_id})
	return true


func cancel_repair(workshop_id: int, repair_id: StringName) -> bool:
	var q: Array = _queues.get(workshop_id, [])
	var idx := q.find(repair_id)
	if idx < 0:
		return false
	# Шаг уже оплачен — голову снимаем только между шагами.
	if idx == 0 and _states.has(workshop_id) and _states[workshop_id]["phase"] == RUNNING and _states[workshop_id]["job"] == &"repair":
		return false
	q.remove_at(idx)
	_emit(TOPIC_CHANGED, {"id": workshop_id})
	return true


# ---------- тик ----------

func tick(sim: Simulation, dt: float) -> void:
	_sim = sim
	if dt <= 0.0:
		return
	var work := dt * Recipes.WORKER_RATE
	for b: Building in construction.buildings.values():
		if b.is_done() and Recipes.is_production(b.type):
			_tick_building(b, _ext_work.get(b.id, 0.0) if external_work else work)
	_ext_work.clear()


func _state(b: Building) -> Dictionary:
	if not _states.has(b.id):
		_states[b.id] = {
			"recipe": Recipes.for_building(b.type)[0], "phase": IDLE,
			"progress": 0.0, "paused": false, "stall": &"", "job": &"",
		}
	return _states[b.id]


func _duration(s: Dictionary) -> float:
	return Recipes.REPAIR_STEP_TIME if s["job"] == &"repair" else Recipes.duration(s["recipe"])


func _tick_building(b: Building, work: float) -> void:
	var s := _state(b)
	if s["paused"]:
		return
	if s["phase"] == IDLE:
		if external_work and work <= 0.0:
			return  # цикл начинает только присутствующий работник
		_try_start(b, s)
		return
	if s["progress"] < _duration(s):
		s["progress"] += work
	if s["progress"] >= _duration(s):
		_try_finish(b, s)


func _try_start(b: Building, s: Dictionary) -> void:
	var queue: Array = _queues.get(b.id, [])
	while not queue.is_empty():
		var r := get_repairable(queue[0])
		if r != null and r.needs_repair():
			break
		queue.pop_front()  # исчез или уже исправен
	var paid := false
	if not queue.is_empty():
		var r := get_repairable(queue[0])
		if economy.consume(r.get_repair_cost()):
			s["job"] = &"repair"
			paid = true
	if not paid:
		# Нет запчастей на шаг ремонта — делаем запчасти по рецепту (иначе тупик).
		if not economy.consume(Recipes.inputs(s["recipe"])):
			_set_stall(b.id, s, &"no_input")
			return
		s["job"] = &"recipe"
		_emit(TOPIC_STARTED, {"id": b.id, "recipe": s["recipe"]})
	s["phase"] = RUNNING
	s["progress"] = 0.0
	_set_stall(b.id, s, &"")


func _try_finish(b: Building, s: Dictionary) -> void:
	if s["job"] == &"repair":
		var queue: Array = _queues.get(b.id, [])
		var rid: StringName = queue[0] if not queue.is_empty() else &""
		var r := get_repairable(rid)
		if r != null:
			r.apply_repair(r.get_repair_gain())
			_emit(TOPIC_REPAIR_PROGRESS, {"id": b.id, "target": rid, "condition": r.condition})
		if r == null or not r.needs_repair():
			if not queue.is_empty():
				queue.pop_front()
			if r != null:
				_emit(TOPIC_REPAIR_DONE, {"id": b.id, "target": rid})
	else:
		var out := Recipes.outputs(s["recipe"])
		var need := 0
		for k in out:
			need += out[k]
		if economy.total_free_space() < need:
			_set_stall(b.id, s, &"no_space")
			return
		for k in out:
			economy.deposit(k, out[k])
		_emit(TOPIC_FINISHED, {"id": b.id, "recipe": s["recipe"], "outputs": out})
	s["phase"] = IDLE
	s["progress"] = 0.0
	s["job"] = &""
	_set_stall(b.id, s, &"")


func _set_stall(id: int, s: Dictionary, reason: StringName) -> void:
	if s["stall"] != reason:
		s["stall"] = reason
		if reason != &"":
			_emit(TOPIC_STALLED, {"id": id, "reason": reason})


func _emit(topic: StringName, payload: Dictionary) -> void:
	if _sim != null:
		_sim.bus.emit(topic, payload)


# ---------- сохранение ----------

func get_save_key() -> StringName:
	return &"production"


func save_state() -> Dictionary:
	var st := {}
	for id in _states:
		var s: Dictionary = _states[id]
		st[str(id)] = {
			"recipe": String(s["recipe"]), "phase": String(s["phase"]),
			"progress": s["progress"], "paused": s["paused"],
			"stall": String(s["stall"]), "job": String(s["job"]),
		}
	var qs := {}
	for id in _queues:
		var l := []
		for v in _queues[id]:
			l.append(String(v))
		qs[str(id)] = l
	var cond := {}
	for k in _saved_cond:
		cond[String(k)] = _saved_cond[k]
	for k in _repairables:
		cond[String(k)] = (_repairables[k] as Repairable).condition
	return {"states": st, "queues": qs, "conditions": cond}


func load_state(d: Dictionary) -> void:
	_states.clear()
	_queues.clear()
	_saved_cond.clear()
	if d.get("states") is Dictionary:
		for k in d["states"]:
			var e = d["states"][k]
			var b := construction.get_building(SaveManager.to_int(k, -1))
			if b == null or not (e is Dictionary) or not Recipes.is_production(b.type):
				continue
			var rec := StringName(String(e.get("recipe", "")))
			if Recipes.building_of(rec) != b.type:
				rec = Recipes.for_building(b.type)[0]
			var phase := StringName(String(e.get("phase", "idle")))
			var job := StringName(String(e.get("job", "")))
			if phase != RUNNING or (job != &"recipe" and job != &"repair"):
				phase = IDLE
				job = &""
			_states[b.id] = {
				"recipe": rec, "phase": phase,
				"progress": maxf(0.0, float(e.get("progress", 0.0))),
				"paused": bool(e.get("paused", false)),
				"stall": StringName(String(e.get("stall", ""))), "job": job,
			}
	if d.get("queues") is Dictionary:
		for k in d["queues"]:
			var q := []
			if d["queues"][k] is Array:
				for v in d["queues"][k]:
					q.append(StringName(String(v)))
			_queues[SaveManager.to_int(k, -1)] = q
	if d.get("conditions") is Dictionary:
		for k in d["conditions"]:
			var key := StringName(String(k))
			var c := clampf(float(d["conditions"][k]), 0.0, 1.0)
			if _repairables.has(key):
				(_repairables[key] as Repairable).condition = c
			else:
				_saved_cond[key] = c
	_emit(TOPIC_CHANGED, {})
