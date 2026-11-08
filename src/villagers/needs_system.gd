class_name NeedsSystem
extends RefCounted
## Физические потребности жителей (шаг 11): расселение, убыль и восполнение нужд, болезни,
## лечение, смерть и выбор «нужных дел» (поесть, попить, лечь, лечиться), которые
## приоритетнее работы. Принадлежит VillagerSystem (vs.needs). Баланс — NeedsDefs.

const KINDS: Array[StringName] = [&"eat", &"drink", &"sleep", &"warm", &"heal", &"treat", &"stoke", &"shelter", &"extinguish"]

var vs: VillagerSystem
var _home_acc := 1.0e9


func _init(vs_in: VillagerSystem) -> void:
	vs = vs_in


# ---------- время ----------

func hour() -> float:
	return vs._sim.clock.get_hour() if vs._sim != null else 12.0


func is_night() -> bool:
	return NeedsDefs.is_night(hour())


## Игровые сутки (все скорости потребностей заданы «в сутки»).
func day_seconds() -> float:
	return vs._sim.clock.day_seconds() if vs._sim != null else GameClock.DEFAULT_DAY_LENGTH



static func is_need_kind(kind: StringName) -> bool:
	return KINDS.has(kind) or SocialSystem.is_social_kind(kind) or FamilyDefs.is_family_kind(kind)  # шаг 22: общение, клуб, баня, праздник, уход


# ---------- жильё ----------

## Готовые жилые здания (id по возрастанию).
func housing_ids() -> Array[int]:
	var out: Array[int] = []
	for id in vs.construction.buildings:
		var b: Building = vs.construction.buildings[id]
		if b.is_done() and BuildingDefs.is_housing(b.type):
			out.append(id)
	out.sort()
	return out


func capacity(id: int) -> int:
	var b := vs.construction.get_building(id)
	return NeedsDefs.housing_capacity(b.type) if b != null and b.is_done() else 0


func residents(id: int) -> Array[Villager]:
	var out: Array[Villager] = []
	for v: Villager in vs.villagers.values():
		if v.home_id == id:
			out.append(v)
	return out


func homeless_count() -> int:
	var n := 0
	for v: Villager in vs.villagers.values():
		if v.home_id == 0 and not v.arriving:
			n += 1
	return n


## Расселяет: сохраняет прежнее жильё, пока оно есть и не переполнено, остальных — в ближайший дом
## со свободным местом (по возрастанию id — детерминированно). Нет места — бездомный.
func assign_homes() -> void:
	var cap := {}
	for id in housing_ids():
		cap[id] = capacity(id)
	var cnt := {}
	var lost: Array[Villager] = []
	for v: Villager in vs.villagers.values():
		if v.arriving:
			continue
		if v.home_id > 0 and cap.has(v.home_id) and cnt.get(v.home_id, 0) < cap[v.home_id]:
			cnt[v.home_id] = cnt.get(v.home_id, 0) + 1
		else:
			v.home_id = 0
			lost.append(v)
	for v in lost:
		var best := 0
		var bd := INF
		for id in cap:
			if cnt.get(id, 0) >= cap[id]:
				continue
			var b := vs.construction.get_building(id)
			var d := Vector2(b.position.x - v.pos.x, b.position.z - v.pos.z).length()
			if d < bd or (is_equal_approx(d, bd) and id < best):
				bd = d
				best = id
		if best > 0:
			v.home_id = best
			cnt[best] = cnt.get(best, 0) + 1


func _home_door(v: Villager) -> Variant:
	if v.home_id <= 0:
		return null
	var b := vs.construction.get_building(v.home_id)
	return vs.household.door_pos(b) if b != null else null


## Житель у своего дома (включая двор).
func at_home(v: Villager) -> bool:
	var d = _home_door(v)
	return d != null and Vector2(d.x - v.pos.x, d.z - v.pos.z).length() <= NeedsDefs.HOME_AREA_RADIUS


## Житель под крышей: дома (с двором), в больнице или в столовой за делом.
func indoors(v: Villager) -> bool:
	if at_home(v):
		return true
	var kind: StringName = v.task.get("kind", &"")
	return v.at_site and (kind == &"heal" or kind == &"treat" or ((kind == &"eat" or kind == &"drink") and v.task.get("dest", &"") == &"canteen"))


## Тепло среды вокруг жителя сейчас: дома — тепло дома, в столовой/больнице — без отопления, на улице — погода.
func ambient_warmth(v: Villager) -> float:
	var hs := vs.household
	if at_home(v):
		return hs.house_warmth(v.home_id)
	var kind: StringName = v.task.get("kind", &"")
	if v.at_site and (kind == &"heal" or kind == &"treat" or ((kind == &"eat" or kind == &"drink") and v.task.get("dest", &"") == &"canteen")):
		var b := vs.construction.get_building(int(v.task.get("target", 0)))
		if b != null:
			return NeedsDefs.unheated_warmth(b.type, hs.outdoor_cold)
	var out := NeedsDefs.outdoor_warmth(hs.outdoor_cold)
	if v.home_id == 0:
		out -= NeedsDefs.HOMELESS_WARMTH_PENALTY
	return clampf(out, 0.0, 1.0)


## Дому пора топить: тепло нужно, печь почти пуста, на поленнице есть дрова.
func stoke_wanted(id: int) -> bool:
	var hs := vs.household
	var h := hs.home(id)
	return h != null and hs.simulate_heat and hs.wants_heat(id) and h.stove <= NeedsDefs.STOKE_BELOW and h.woodpile > 0 and hs.stove_demand(id) > 0


## Занят ли уже другой житель топкой этого дома.
func _stoker_busy(id: int, me: Villager) -> bool:
	for o: Villager in vs.villagers.values():
		if o != me and o.task.get("kind", &"") == &"stoke" and int(o.task.get("target", 0)) == id:
			return true
	return false


# ---------- тик ----------

func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	var days := dt / day_seconds()
	_home_acc += dt
	if _home_acc >= NeedsDefs.HOME_ASSIGN_INTERVAL:
		_home_acc = 0.0
		assign_homes()
	var staff := {}   # id больницы -> множитель лечения (лучший из присутствующих)
	for v: Villager in vs.villagers.values():
		if v.task.get("kind", &"") == &"treat" and v.at_site:
			var m := 1.0 if v.profession == &"doctor" else NeedsDefs.NONDOCTOR_HEAL_MULT
			var t := int(v.task.get("target", 0))
			staff[t] = maxf(staff.get(t, 0.0), m)
	for v: Villager in vs.villagers.values():
		if v.arriving:
			continue
		_tick_one(v, dt, days, staff)


func _tick_one(v: Villager, dt: float, days: float, staff: Dictionary) -> void:
	var hs := vs.household
	var mult := hs.consumption_multiplier
	var cold := hs.outdoor_cold
	var kind: StringName = v.task.get("kind", &"")
	var target := int(v.task.get("target", 0))
	var resting := (kind == &"sleep" and v.at_site) or (kind == &"heal" and v.at_site)
	var treated: bool = kind == &"heal" and v.at_site and staff.has(target)
	# убыль и восполнение
	var slow := NeedsDefs.SLEEP_DECAY_MULT if resting else 1.0
	var cm := vs.family.consumption_mult(v) if vs.family != null else 1.0  # шаг 23: дети едят меньше
	v.set_need(NeedsDefs.FOOD, v.need(NeedsDefs.FOOD) - NeedsDefs.FOOD_DECAY_PER_DAY * NeedsDefs.cold_factor(NeedsDefs.FOOD, cold) * mult * slow * cm * days)
	v.set_need(NeedsDefs.WATER, v.need(NeedsDefs.WATER) - NeedsDefs.WATER_DECAY_PER_DAY * mult * hs.water_decay_multiplier * slow * cm * days)
	var amb := ambient_warmth(v)
	var w := v.need(NeedsDefs.WARMTH)
	var wrate := NeedsDefs.WARMTH_RATE_PER_DAY * (NeedsDefs.cold_factor(NeedsDefs.WARMTH, cold) * mult if amb < w else 1.0)
	if vs.family != null and amb < w:
		wrate *= vs.family.warmth_mult(v)  # малыши мёрзнут быстрее
	var exposed := (hs.exposure_warmth_mult > 1.0 or hs.exposure_health_drain > 0.0) and not indoors(v)
	if exposed and amb < w:
		wrate *= hs.exposure_warmth_mult
	v.set_need(NeedsDefs.WARMTH, move_toward(w, amb, wrate * days))
	if resting:
		var k := 1.0 if v.home_id > 0 and (at_home(v) or kind == &"heal") else NeedsDefs.HOMELESS_REST_MULT
		v.set_need(NeedsDefs.REST, v.need(NeedsDefs.REST) + NeedsDefs.SLEEP_RESTORE_PER_DAY * k * days)
	else:
		var working := v.at_site and not is_need_kind(kind) and not v.task.is_empty()
		v.set_need(NeedsDefs.REST, v.need(NeedsDefs.REST) - (NeedsDefs.REST_DECAY_WORK if working else NeedsDefs.REST_DECAY_IDLE) * days)
	# здоровье
	var hp := v.need(NeedsDefs.HEALTH)
	var drain := 0.0
	for n in NeedsDefs.BASIC:
		var x := v.need(n)
		if x < NeedsDefs.CRITICAL_NEED:
			drain += NeedsDefs.STARVE_DRAIN_PER_DAY * (1.0 - x / NeedsDefs.CRITICAL_NEED)
	if exposed:
		drain += hs.exposure_health_drain  # застигнуты непогодой на улице
	if v.sick and not treated:
		drain += NeedsDefs.SICK_DRAIN_PER_DAY
	if drain > 0.0:
		hp -= drain * days
	elif not v.sick and _all_basic_above(v, NeedsDefs.REGEN_NEEDS_MIN):
		hp += NeedsDefs.HEALTH_REGEN_PER_DAY * days
	if treated:
		hp += NeedsDefs.HEAL_PER_DAY * float(staff[target]) * days
	hp = clampf(hp, 0.0, 1.0)
	if not v.can_die():
		hp = maxf(hp, NeedsDefs.HERO_HEALTH_FLOOR)
	v.set_need(NeedsDefs.HEALTH, hp)
	if hp <= 0.0 and v.can_die():
		vs.kill_villager(v.id, _death_cause(v))
		return
	if v.sick and hp >= NeedsDefs.RECOVER_HEALTH and (treated or drain <= 0.0):
		v.sick = false
		v.think_cd = 0.0
		vs._jobs_dirty = true
		vs._emit(VillagerSystem.TOPIC_RECOVERED, _payload(v))
	# болезнь (детерминированный RNG симуляции)
	if not v.sick:
		v.sick_acc += dt
		v.bad_water_days = maxf(0.0, v.bad_water_days - dt / day_seconds())
		if v.sick_acc >= NeedsDefs.SICK_ROLL_INTERVAL:
			v.sick_acc -= NeedsDefs.SICK_ROLL_INTERVAL
			var rate := NeedsDefs.sick_rate_per_day(v.needs, v.bad_water_days > 0.0)
			if vs.social != null:
				rate += vs.social.sick_bonus(v)  # шаг 22: подавленные болеют чаще
			var p := 1.0 - exp(-rate * NeedsDefs.SICK_ROLL_INTERVAL / day_seconds())
			if vs._rng().randf() < p:
				fall_sick(v)


func _all_basic_above(v: Villager, x: float) -> bool:
	for n in NeedsDefs.BASIC:
		if v.need(n) < x:
			return false
	return true


func _payload(v: Villager) -> Dictionary:
	return {"id": v.id, "name": v.display_name, "profession": v.profession}


## Житель заболевает: бросает работу, идёт лечиться.
func fall_sick(v: Villager) -> void:
	if v.sick:
		return
	v.sick = true
	v.set_need(NeedsDefs.HEALTH, minf(v.need(NeedsDefs.HEALTH), NeedsDefs.SICK_START_HEALTH_CAP))
	v.think_cd = 0.0
	vs._jobs_dirty = true
	vs._emit(VillagerSystem.TOPIC_SICK, _payload(v))


func _death_cause(v: Villager) -> StringName:
	if v.sick:
		return &"sickness"
	var worst := NeedsDefs.FOOD
	for n in NeedsDefs.BASIC:
		if v.need(n) < v.need(worst):
			worst = n
	return worst


# ---------- выбор нужного дела ----------

func _job(kind: StringName, target: int, dest: StringName) -> Dictionary:
	return {"key": "n:%s:%d" % [kind, target], "cat": &"", "kind": kind, "target": target, "dest": dest}


## Нужное дело жителя ({} — свободен для работы). Порядок: вода, еда, болезнь, сон, тепло.
func job_for(v: Villager) -> Dictionary:
	var cur: StringName = v.task.get("kind", &"")
	var hs := vs.household
	if vs.social != null and vs.social.is_leaving(v.id):
		return vs.social.job_for(v, cur)  # решил уйти: ничто не держит
	if v.need(NeedsDefs.WATER) < NeedsDefs.DRINK_BELOW or (cur == &"drink" and v.need(NeedsDefs.WATER) < NeedsDefs.MEAL_FULL):
		var h := hs.home(v.home_id) if v.home_id > 0 else null
		if h != null and h.water > 0:
			return _job(&"drink", v.home_id, &"home")
		var c := hs.canteen_with_water(v)
		if c > 0:
			return _job(&"drink", c, &"canteen")
	if v.need(NeedsDefs.FOOD) < NeedsDefs.EAT_BELOW or (cur == &"eat" and v.need(NeedsDefs.FOOD) < NeedsDefs.MEAL_FULL):
		if v.home_id > 0 and hs.house_has_food(v.home_id):
			return _job(&"eat", v.home_id, &"home")
		var c2 := hs.canteen_for(v)
		if c2 > 0:
			return _job(&"eat", c2, &"canteen")
	if v.sick:
		var bed := hospital_bed_for(v)
		if bed > 0:
			return _job(&"heal", bed, &"hospital")
		return _job(&"sleep", maxi(v.home_id, 0), &"home")
	var fj := fire_job_for(v)
	if not fj.is_empty():
		return fj
	if _wants_sleep(v, cur):
		return _job(&"sleep", maxi(v.home_id, 0), &"home")
	if v.home_id > 0 and stoke_wanted(v.home_id) and (cur == &"stoke" or not _stoker_busy(v.home_id, v)):
		return _job(&"stoke", v.home_id, &"stove")
	if hs.shelter_required and not indoors(v):
		var hb := vs.construction.get_building(v.home_id) if v.home_id > 0 else null
		var ok := hb != null and hb.is_done() and not hb.burning and not hb.flooded
		return _job(&"shelter", v.home_id if ok else 0, &"home")  # бездомный стоит на месте
	if v.home_id > 0 and (v.need(NeedsDefs.WARMTH) < NeedsDefs.WARM_BELOW or (cur == &"warm" and v.need(NeedsDefs.WARMTH) < NeedsDefs.WARM_DONE)):
		if hs.house_warmth(v.home_id) > v.need(NeedsDefs.WARMTH) + 0.1:
			return _job(&"warm", v.home_id, &"home")
	if vs.family != null:
		var fj2 := vs.family.job_for(v, cur)  # шаг 23: школа, двор, забота о детях
		if not fj2.is_empty():
			return fj2
	if vs.social != null:
		return vs.social.job_for(v, cur)  # шаг 22: праздник, клуб, баня, разговор
	return {}


## Тушение: ближайший очаг, которому ещё не хватает воды (с учётом несущих), если есть колодец.
## Пока идёт укрытие от непогоды — только горящие здания. {} — тушить нечего.
func fire_job_for(v: Villager) -> Dictionary:
	var w := vs.weather
	if w == null or w.fire.is_empty() or v.arriving:
		return {}
	var hs := vs.household
	if hs.nearest_well(v.pos) < 0:
		return {}
	var cur_key: String = v.task.get("key", "")
	var best := {}
	var bd := INF
	var targets: Array = []
	for id in w.fire.buildings:
		targets.append([&"building", id])
	if not hs.shelter_required:
		for i in w.fire.cells:
			targets.append([&"cell", i])
	for t in targets:
		var dest: StringName = t[0]
		var tid: int = t[1]
		var key := "n:extinguish:%s:%d" % [dest, tid]
		var pending := 0
		for o: Villager in vs.villagers.values():
			if o != v and o.task.get("kind", &"") == &"extinguish" and int(o.task.get("target", 0)) == tid and o.task.get("dest", &"") == dest:
				pending += HouseholdDefs.WATER_CARRY
		if key != cur_key and w.fire.water_left(dest, tid) - pending <= 0:
			continue
		var p = w.fire.target_pos(dest, tid)
		if p == null:
			continue
		var d := Vector2(p.x - v.pos.x, p.z - v.pos.z).length() - (1000.0 if dest == &"building" else 0.0) - (500.0 if key == cur_key else 0.0)
		if d < bd:
			bd = d
			best = {"key": key, "cat": &"", "kind": &"extinguish", "target": tid, "dest": dest}
	return best


func _wants_sleep(v: Villager, cur: StringName) -> bool:
	var night := is_night()
	var rest := v.need(NeedsDefs.REST)
	if night and cur == &"treat" and rest > NeedsDefs.NIGHT_SHIFT_MIN_REST:
		return false  # ночная смена у пациентов
	if cur == &"sleep":
		return night or rest < NeedsDefs.DAY_NAP_WAKE
	return night or rest < NeedsDefs.EXHAUSTED


# ---------- больница ----------

func hospital_ids() -> Array[int]:
	var out: Array[int] = []
	for id in vs.construction.buildings:
		var b: Building = vs.construction.buildings[id]
		if b.is_done() and b.type == &"hospital":
			out.append(id)
	out.sort()
	return out


## Больные, закреплённые за больницей (идут или лежат).
func patients(id: int) -> Array[Villager]:
	var out: Array[Villager] = []
	for v: Villager in vs.villagers.values():
		if v.sick and v.task.get("kind", &"") == &"heal" and int(v.task.get("target", 0)) == id:
			out.append(v)
	return out


## Койка для больного: прежняя, если место есть, иначе ближайшая больница со свободной койкой (0 — нет).
func hospital_bed_for(v: Villager) -> int:
	var cur := int(v.task.get("target", 0)) if v.task.get("kind", &"") == &"heal" else 0
	var best := 0
	var bd := INF
	for id in hospital_ids():
		var taken := patients(id).size() - (1 if id == cur else 0)
		if taken >= NeedsDefs.HOSPITAL_BEDS:
			continue
		if id == cur:
			return id
		var b := vs.construction.get_building(id)
		var d := Vector2(b.position.x - v.pos.x, b.position.z - v.pos.z).length()
		if d < bd:
			bd = d
			best = id
	return best


## Может ли житель лечить: врач, а если здоровых врачей в посёлке нет — любой (хуже).
func can_treat(v: Villager) -> bool:
	if v.sick:
		return false
	if v.profession == &"doctor":
		return true
	return not doctor_available()


func doctor_available() -> bool:
	for o: Villager in vs.villagers.values():
		if o.profession == &"doctor" and not o.sick and not o.arriving:
			return true
	return false


func hospital_staffed(id: int) -> bool:
	for v: Villager in vs.villagers.values():
		if v.task.get("kind", &"") == &"treat" and int(v.task.get("target", 0)) == id and v.at_site:
			return true
	return false
