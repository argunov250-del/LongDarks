class_name CareerSystem
extends SimSystem
## Карьера (шаг 26): главы -> цели, прогресс по событиям шины и опросу состояния.
## Дизайн: design/gdd/career.md. Данные: data/career/chapters.json (CareerDefs). Часть сохранения (`career`).
## Фазы: intro -> active -> outro -> (следующая глава | credits -> done). Панели показывает UI (CareerUi).
## Вне режима «Карьера» (active == false) система ничего не делает.

const TOPIC_CHANGED := &"career_changed"            # любое изменение прогресса/фазы
const TOPIC_CHAPTER_STARTED := &"career_chapter_started"  # {index, id}
const TOPIC_OBJECTIVE_DONE := &"career_objective_done"    # {chapter, id}
const TOPIC_CHAPTER_DONE := &"career_chapter_done"        # {index, id}
const TOPIC_CREDITS := &"career_credits"
const TOPIC_FINISHED := &"career_finished"
const TOPIC_HARVESTED_SRC := &"crop_harvested"       # FoodSystem.TOPIC_HARVESTED

const INTRO := &"intro"
const ACTIVE := &"active"
const OUTRO := &"outro"
const CREDITS := &"credits"
const DONE := &"done"
const POLL_INTERVAL := 0.5   # игровых секунд между опросами состояния

var active := false
var chapter := 0
var phase: StringName = ACTIVE
var chapters: Array[Dictionary] = []
var credits: Dictionary = {}
var errors: Array[String] = []
var done: Dictionary = {}     # id цели -> true (фиксируется навсегда в рамках главы)
var counts: Dictionary = {}   # id цели -> накопленное число (event-условия)

var villagers: VillagerSystem
var seasons: SeasonSystem
var economy: EconomySystem
var neighbours: NeighbourSystem

var _sim: Simulation
var _acc := 0.0
var _resume_speed := 0
var _subscribed: Array[StringName] = []


func _init(data: Dictionary = {}) -> void:
	load_data(CareerDefs.load_file() if data.is_empty() else data)


## Подставляет разобранные данные (CareerDefs.parse). Битые данные: errors + предупреждение, без падений.
func load_data(parsed: Dictionary) -> void:
	chapters = parsed.get("chapters", [])
	credits = parsed.get("credits", {})
	errors = parsed.get("errors", [])
	for e in errors:
		push_warning("Career data: " + e)
	if _sim != null:
		_resubscribe()


func bind(villagers_in: VillagerSystem, seasons_in: SeasonSystem, economy_in: EconomySystem, neighbours_in: NeighbourSystem) -> void:
	villagers = villagers_in
	seasons = seasons_in
	economy = economy_in
	neighbours = neighbours_in


func attach(sim: Simulation) -> void:
	_sim = sim
	_resubscribe()


func _resubscribe() -> void:
	for t in _subscribed:
		_sim.bus.unsubscribe(t, _on_topic.bind(t))
	_subscribed.clear()
	var topics: Array[StringName] = [ConstructionSystem.TOPIC_COMPLETED, TOPIC_HARVESTED_SRC, ProductionSystem.TOPIC_REPAIR_DONE]
	for ch in chapters:
		for o in ch["objectives"]:
			if o["type"] == CareerDefs.T_EVENT:
				var t := StringName(o["params"]["topic"])
				if not topics.has(t):
					topics.append(t)
	for t in topics:
		_sim.bus.subscribe(t, _on_topic.bind(t))
		_subscribed.append(t)


# ---------- ход игры ----------

## Новая карьерная партия: глава 1.
func start_new() -> void:
	if chapters.is_empty():
		active = false
		return
	active = true
	_enter_chapter(0)


func is_running() -> bool:
	return active and phase == ACTIVE


func current_chapter() -> Dictionary:
	return chapters[chapter] if active and chapter >= 0 and chapter < chapters.size() else {}


func _enter_chapter(i: int) -> void:
	chapter = i
	done.clear()
	counts.clear()
	var ch := chapters[i]
	_apply_start_state(ch["start_state"])
	_acc = 0.0
	if str(ch["intro"]) != "":
		_set_phase(INTRO)
	else:
		_set_phase(ACTIVE)
	_emit(TOPIC_CHAPTER_STARTED, {"index": i, "id": ch["id"]})
	_changed()


func _apply_start_state(s: Dictionary) -> void:
	if economy != null and s.get("resources") is Dictionary:
		for res in s["resources"]:
			economy.deposit(StringName(res), int(s["resources"][res]))
	if seasons != null and s.has("season") and SeasonDefs.ORDER.has(StringName(s["season"])):
		seasons.start_at(StringName(s["season"]), float(s.get("season_progress", 0.0)))


func _set_phase(p: StringName) -> void:
	var was_panel := _is_panel(phase)
	phase = p
	if _sim != null:
		if _is_panel(p) and not was_panel:
			_resume_speed = _sim.clock.get_speed()
			_sim.clock.set_speed(0)
		elif not _is_panel(p) and was_panel and _resume_speed > 0 and _sim.clock.is_paused():
			_sim.clock.set_speed(_resume_speed)
			_resume_speed = 0


static func _is_panel(p: StringName) -> bool:
	return p == INTRO or p == OUTRO or p == CREDITS


## Игрок закрыл панель (вступление / итог / титры).
func acknowledge() -> void:
	if not active:
		return
	match phase:
		INTRO:
			_set_phase(ACTIVE)
			evaluate()
			_changed()
		OUTRO:
			_advance()
		CREDITS:
			_set_phase(DONE)
			_emit(TOPIC_FINISHED, {})
			_changed()


func _advance() -> void:
	if chapter + 1 < chapters.size():
		_enter_chapter(chapter + 1)
	else:
		_set_phase(CREDITS)
		_emit(TOPIC_CREDITS, {})
		_changed()


# ---------- прогресс ----------

func _on_topic(p: Dictionary, topic: StringName) -> void:
	if not is_running():
		return
	var changed := false
	for o in chapters[chapter]["objectives"]:
		if done.has(o["id"]) or CareerDefs.KINDS[o["type"]] != &"event":
			continue
		var add := _event_value(o, topic, p)
		if add > 0.0:
			counts[o["id"]] = float(counts.get(o["id"], 0.0)) + add
			changed = true
	if changed:
		evaluate()
		_changed()


## Сколько добавляет событие к цели (0 — не подходит).
func _event_value(o: Dictionary, topic: StringName, p: Dictionary) -> float:
	var pr: Dictionary = o["params"]
	match o["type"]:
		CareerDefs.T_BUILD:
			return 1.0 if topic == ConstructionSystem.TOPIC_COMPLETED and str(p.get("type", "")) == str(pr["building"]) else 0.0
		CareerDefs.T_HARVEST:
			if topic != TOPIC_HARVESTED_SRC:
				return 0.0
			var want := str(pr.get("resource", ""))
			return float(p.get("n", 0)) if want == "" or str(p.get("res", "")) == want else 0.0
		CareerDefs.T_REPAIR:
			return 1.0 if topic == ProductionSystem.TOPIC_REPAIR_DONE and str(p.get("target", "")).begins_with(str(pr.get("prefix", ""))) else 0.0
		CareerDefs.T_EVENT:
			if str(pr["topic"]) != str(topic):
				return 0.0
			if pr.has("field") and str(p.get(str(pr["field"]), "")) != str(pr.get("value", "")):
				return 0.0
			return 1.0
	return 0.0


## Текущее значение прогресса цели (для трекера); poll-цели считаются по состоянию игры.
func progress_of(o: Dictionary) -> float:
	var pr: Dictionary = o["params"]
	match o["type"]:
		CareerDefs.T_POPULATION:
			return float(villagers.population()) if villagers != null else 0.0
		CareerDefs.T_RESOURCE:
			return float(economy.total(StringName(pr["resource"]))) if economy != null else 0.0
		CareerDefs.T_RELATION:
			return _best_relation(str(pr.get("neighbour", "")))
		CareerDefs.T_SURVIVE:
			if seasons == null:
				return 0.0
			var cur := seasons.year() * 4 + seasons.season_index()
			var goal := int(pr["year"]) * 4 + SeasonDefs.ORDER.find(StringName(pr["season"]))
			return 1.0 if cur >= goal else 0.0
	return float(counts.get(o["id"], 0.0))


func _best_relation(nid: String) -> float:
	if neighbours == null:
		return -1.0
	var best := -1.0
	for n in neighbours.neighbours:
		if nid == "" or str(n["id"]) == nid:
			best = maxf(best, float(n["relation"]))
	return best


## Выполнена ли цель сейчас по прогрессу.
func is_met(o: Dictionary) -> bool:
	return progress_of(o) >= CareerDefs.target(o) if o["type"] != CareerDefs.T_SURVIVE else progress_of(o) >= 1.0


func is_done(o: Dictionary) -> bool:
	return done.has(o["id"])


## Проверяет цели активной главы; фиксирует выполненные, завершает главу.
func evaluate() -> void:
	if not is_running():
		return
	var ch := chapters[chapter]
	var newly := false
	for o in ch["objectives"]:
		if not done.has(o["id"]) and is_met(o):
			done[o["id"]] = true
			newly = true
			_emit(TOPIC_OBJECTIVE_DONE, {"chapter": ch["id"], "id": o["id"]})
	if not newly:
		return
	for o in ch["objectives"]:
		if not done.has(o["id"]):
			_changed()
			return
	_emit(TOPIC_CHAPTER_DONE, {"index": chapter, "id": ch["id"]})
	if str(ch["outro"]) != "":
		_set_phase(OUTRO)
		_changed()
	else:
		_advance()


func tick(_s: Simulation, dt: float) -> void:
	if not is_running():
		return
	_acc += dt
	if _acc >= POLL_INTERVAL:
		_acc = 0.0
		var before := done.size()
		evaluate()
		if done.size() != before:
			return
		_changed()  # обновить числа в трекере


func _emit(topic: StringName, payload: Dictionary) -> void:
	if _sim != null:
		_sim.bus.emit(topic, payload)


func _changed() -> void:
	_emit(TOPIC_CHANGED, {})


# ---------- сохранение ----------

func get_save_key() -> StringName:
	return &"career"


func save_state() -> Dictionary:
	return {"active": active, "chapter": chapter, "phase": String(phase), "done": done.duplicate(), "counts": counts.duplicate()}


func load_state(d: Dictionary) -> void:
	active = bool(d.get("active", false)) and not chapters.is_empty()
	chapter = clampi(SaveManager.to_int(d.get("chapter"), 0), 0, maxi(chapters.size() - 1, 0))
	var p := StringName(str(d.get("phase", "active")))
	phase = p if [INTRO, ACTIVE, OUTRO, CREDITS, DONE].has(p) else ACTIVE
	done = d["done"].duplicate() if d.get("done") is Dictionary else {}
	counts = d["counts"].duplicate() if d.get("counts") is Dictionary else {}
	_resume_speed = 0
	_acc = 0.0
	_changed()
