class_name VillagerAnim
extends RefCounted
## Процедурная анимация низкополигональных фигур (без костей): поза выбирается из
## активности жителя (state_of), узлы фигуры (см. VillagerFigures.make_villager)
## двигаются синусами (apply). Видимая ноша: вёдра, охапка брёвен/дров, корзина овощей.

const WALK_SPEED := 9.0
const WORK_SPEED := 6.0

const POSE_IDLE := &"idle"
const POSE_WALK := &"walk"
const POSE_WORK := &"work"        # общая работа (стройка, производство)
const POSE_CHOP := &"chop"        # колка дров топором
const POSE_CRANK := &"crank"      # колодец: ворот/журавль, вёдра вниз-вверх
const POSE_STACK := &"stack"      # сложить дрова на поленницу / в печь / поставить ношу
const POSE_PICKUP := &"pickup"    # взять груз
const POSE_DIG := &"dig"          # копать огород
const POSE_PLANT := &"plant"      # сажать
const POSE_HARVEST := &"harvest"  # собирать урожай

const LOAD_NONE := &""
const LOAD_LOGS := &"logs"
const LOAD_FIREWOOD := &"firewood"
const LOAD_BASKET := &"basket"
const LOAD_BUCKETS := &"buckets"


## Что несёт житель.
static func load_of(task: Dictionary) -> StringName:
	if task.is_empty():
		return LOAD_NONE
	if task.get("kind", &"") == &"water" or task.get("kind", &"") == &"extinguish":
		return LOAD_BUCKETS  # вёдра в руках: пустые по пути к колодцу, полные обратно
	if int(task.get("carry", 0)) <= 0:
		return LOAD_NONE
	match task.get("res", &""):
		&"logs":
			return LOAD_LOGS
		&"firewood":
			return LOAD_FIREWOOD
		&"water":
			return LOAD_BUCKETS
	return LOAD_BASKET


## Поза и ноша из активности жителя: {"pose": StringName, "load": StringName}.
static func state_of(v: Villager, vs: VillagerSystem = null) -> Dictionary:
	var load := load_of(v.task)
	if v.moving:
		return {"pose": POSE_WALK, "load": load}
	if v.task.is_empty() or not v.at_site:
		return {"pose": POSE_IDLE, "load": load}
	var t := v.task
	var phase: StringName = t.get("phase", &"")
	var pose := POSE_WORK
	match t.get("kind", &""):
		&"chop":
			pose = POSE_CHOP if phase == &"chop" else (POSE_STACK if phase == &"deliver" else POSE_PICKUP)
		&"carry", &"food", &"stoke":
			pose = POSE_STACK if phase == &"deliver" else POSE_PICKUP
		&"water", &"extinguish":
			pose = POSE_STACK if phase == &"deliver" else POSE_CRANK
		&"field", &"hunt", &"fish", &"forage", &"gfuel", &"gpick":
			# step 16 placeholders: hoe = dig, sowing = plant, reaping/gathering = harvest; rod/bow reuse work pose
			if phase == &"deliver":
				pose = POSE_STACK
			elif phase == &"fetch":
				pose = POSE_PICKUP
			else:
				var fa: StringName = vs.food.field_action(int(t.get("target", 0))) if (vs != null and vs.food != null and t["kind"] == &"field") else &""
				match t["kind"]:
					&"field":
						pose = POSE_DIG if fa == &"plow" else (POSE_PLANT if fa == &"sow" else POSE_HARVEST)
					&"forage", &"gpick":
						pose = POSE_HARVEST
					_:
						pose = POSE_WORK
		&"garden":
			if phase == &"deliver":
				pose = POSE_STACK
			else:
				var h: Household = vs.household.home(int(t.get("target", 0))) if vs != null else null
				if h != null and h.garden_state == Household.GARDEN_RIPE:
					pose = POSE_HARVEST
				else:
					var need := HouseholdDefs.PLANT_WORK
					pose = POSE_DIG if float(t.get("work", 0.0)) < need * 0.5 else POSE_PLANT
	if pose == POSE_CHOP:
		load = LOAD_NONE  # брёвна лежат на колоде, в руках топор
	return {"pose": pose, "load": load}


## Фаза вращения ворота/рук у колодца: общая для жителя и колодца (синхронно).
static func crank_phase(t: float, seed_value: float) -> float:
	return t * WORK_SPEED + seed_value


## Общие часы (сек): VillagersView обновляет каждый кадр, колодцы берут отсюда.
static var clock := 0.0


static func _set_vis(n: Node, path: String, vis: bool) -> void:
	var c := n.get_node_or_null(path)
	if c != null:
		c.visible = vis


## Применяет позу к фигуре в момент t (сек); seed разводит фазы разных жителей.
static func apply(n: Node3D, st: Dictionary, t: float, seed_value: float) -> void:
	var body := n.get_node("Body") as Node3D
	var legl := n.get_node("LegL") as Node3D
	var legr := n.get_node("LegR") as Node3D
	var arml := body.get_node_or_null("ArmL") as Node3D
	var armr := body.get_node_or_null("ArmR") as Node3D
	var pose: StringName = st.get("pose", POSE_IDLE)
	var load: StringName = st.get("load", LOAD_NONE)
	body.position.y = 0.0
	body.rotation.x = 0.0
	legl.rotation.x = 0.0
	legr.rotation.x = 0.0
	if arml == null or armr == null:
		return
	arml.rotation = Vector3.ZERO
	armr.rotation = Vector3.ZERO
	# реквизит
	_set_vis(body, "ArmR/Axe", pose == POSE_CHOP)
	_set_vis(body, "ArmR/Hoe", pose == POSE_DIG or pose == POSE_PLANT)
	var buckets := load == LOAD_BUCKETS
	_set_vis(body, "ArmL/BucketL", buckets)
	_set_vis(body, "ArmR/BucketR", buckets)
	var armful := load == LOAD_LOGS or load == LOAD_FIREWOOD or load == LOAD_BASKET
	_set_vis(body, "Armful", armful)
	_set_vis(body, "Armful/Logs", load == LOAD_LOGS)
	_set_vis(body, "Armful/Firewood", load == LOAD_FIREWOOD)
	_set_vis(body, "Armful/Basket", load == LOAD_BASKET)
	var ph := crank_phase(t, seed_value)
	match pose:
		POSE_WALK:
			var w := t * WALK_SPEED + seed_value
			body.position.y = absf(sin(w)) * 0.06
			legl.rotation.x = sin(w) * 0.6
			legr.rotation.x = -sin(w) * 0.6
			if armful:
				arml.rotation.x = -1.1  # охапка перед грудью
				armr.rotation.x = -1.1
			elif load == LOAD_BUCKETS:
				arml.rotation.z = 0.18  # вёдра оттягивают руки
				armr.rotation.z = -0.18
				arml.rotation.x = sin(w) * 0.1
				armr.rotation.x = -sin(w) * 0.1
			else:
				arml.rotation.x = -sin(w) * 0.5
				armr.rotation.x = sin(w) * 0.5
		POSE_WORK:
			body.rotation.x = 0.25 + sin(ph) * 0.25
		POSE_CHOP:
			var s := sin(ph * 1.3) * 0.5 + 0.5  # 0 — замах, 1 — удар
			body.rotation.x = 0.1 + s * 0.35
			armr.rotation.x = -2.7 + s * 2.3
			arml.rotation.x = armr.rotation.x * 0.85
		POSE_CRANK:
			body.rotation.x = 0.25
			arml.rotation.x = -1.2 + sin(ph) * 0.9
			armr.rotation.x = -1.2 + cos(ph) * 0.9
			body.position.y = -absf(sin(ph * 0.5)) * 0.04
		POSE_STACK, POSE_PICKUP:
			var b := sin(ph) * 0.5 + 0.5
			body.rotation.x = 0.3 + b * 0.5
			arml.rotation.x = -0.9 - b * 0.5
			armr.rotation.x = -0.9 - b * 0.5
		POSE_DIG:
			var d := sin(ph * 1.4) * 0.5 + 0.5
			body.rotation.x = 0.35 + d * 0.2
			armr.rotation.x = -2.0 + d * 1.6
			arml.rotation.x = armr.rotation.x
		POSE_PLANT:
			body.rotation.x = 0.85
			armr.rotation.x = -0.5 + sin(ph * 2.0) * 0.25
			arml.rotation.x = -0.5 - sin(ph * 2.0) * 0.25
		POSE_HARVEST:
			var hv := sin(ph) * 0.5 + 0.5
			body.rotation.x = 0.7 + hv * 0.25
			arml.rotation.x = -0.4 - hv * 0.8
			armr.rotation.x = -0.4 - hv * 0.8
