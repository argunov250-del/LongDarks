class_name FamilySystem
extends SimSystem
## Семья и дети (шаг 23), design/gdd/families.md: пары, общий дом, беременность и рождение, рост детей
## (младенец -> ребёнок -> подросток -> взрослый), школа, забота, наследование черт, потребность «семья»,
## горе, старение и естественная смерть. Герой бессмертен (Villager.can_die()). Баланс — FamilyDefs.
## Принадлежит симуляции (ключ сохранения &"family"); VillagerSystem знает её через vs.family.

const TOPIC_WEDDING := &"family_wedding"   # {a, b, a_name, b_name}
const TOPIC_BORN := &"family_born"         # {id, name, mother, father, mother_name}
const TOPIC_GREW := &"family_grew_up"      # {id, name, profession}
const CAUSE_OLD_AGE := &"old_age"

var vs: VillagerSystem
var social: SocialSystem
var enabled := true

var _partner: Dictionary = {}     # id -> id (симметрично)
var _parents: Dictionary = {}     # id ребёнка -> [id матери, id отца]
var _names: Dictionary = {}       # id -> имя (родня, которой уже нет в посёлке)
var _pregnant: Dictionary = {}    # id матери -> {father, left (игр. с)}
var _postpartum: Dictionary = {}  # id матери -> суток до новой беременности
var _grief: Dictionary = {}       # id -> горе 0..1
var _school: Dictionary = {}      # id ребёнка -> суток в школе
var _care: Dictionary = {}        # id ребёнка -> забота 0..1
var _acc := 0.0
var _roll_acc := 0.0
var _sim: Simulation


func _init(vs_in: VillagerSystem) -> void:
	vs = vs_in
	vs.family = self


func attach(sim: Simulation) -> void:
	_sim = sim
	sim.bus.subscribe(VillagerSystem.TOPIC_DIED, _on_gone)
	sim.bus.subscribe(SocialSystem.TOPIC_LEFT, _on_gone)


## Связывает с психикой: потребность «семья» и горе влияют на настроение.
func bind(social_in: SocialSystem) -> void:
	social = social_in
	social.family = self
	social.family_provider = Callable(self, "family_need_of")


func _emit(topic: StringName, payload: Dictionary) -> void:
	if _sim != null:
		_sim.bus.emit(topic, payload)


func _day_seconds() -> float:
	return _sim.clock.day_seconds() if _sim != null else GameClock.DEFAULT_DAY_LENGTH


func _hour() -> float:
	return _sim.clock.get_hour() if _sim != null else 12.0


func _v(id: int) -> Villager:
	return vs.get_villager(id)


# ---------- родство ----------

func partner_of(id: int) -> Villager:
	return _v(int(_partner.get(id, 0)))


func partner_id(id: int) -> int:
	return int(_partner.get(id, 0))


## [мать, отец] (id; 0 — неизвестно). Родители могут быть уже не в посёлке.
func parent_ids(id: int) -> Array:
	return _parents.get(id, [0, 0])


## Живые в посёлке дети жителя (по id).
func children_of(id: int) -> Array[Villager]:
	var out: Array[Villager] = []
	var ids: Array = []
	for c in _parents:
		var p: Array = _parents[c]
		if p[0] == id or p[1] == id:
			ids.append(c)
	ids.sort()
	for c in ids:
		var cv := _v(c)
		if cv != null:
			out.append(cv)
	return out


## Все дети жителя, включая ушедших/умерших (для лимита детей).
func children_count(id: int) -> int:
	var n := 0
	for c in _parents:
		var p: Array = _parents[c]
		if p[0] == id or p[1] == id:
			n += 1
	return n


func is_pregnant(id: int) -> bool:
	return _pregnant.has(id)


func pregnancy_left_days(id: int) -> float:
	return maxf(0.0, float(_pregnant[id]["left"])) / _day_seconds() if _pregnant.has(id) else 0.0


func related(a: int, b: int) -> bool:
	var pa := parent_ids(a)
	var pb := parent_ids(b)
	if pa.has(b) or pb.has(a):
		return true
	for x in pa:
		if x != 0 and pb.has(x):
			return true
	return false


func _name_of(id: int) -> String:
	var v := _v(id)
	return v.display_name if v != null else String(_names.get(id, "?"))


# ---------- жильё ----------

## Свободных мест в доме с учётом будущих рождений.
func free_slots(home: int) -> int:
	var cap := vs.needs.capacity(home)
	if cap <= 0:
		return 0
	var used := 0
	for o: Villager in vs.villagers.values():
		if o.home_id == home and not o.arriving:
			used += 1
			if _pregnant.has(o.id):
				used += 1
	return cap - used


## Пара селится вместе: к тому, у кого есть место, иначе в дом с двумя свободными местами. false — нет жилья.
func move_in_together(a: Villager, b: Villager) -> bool:
	if a.home_id > 0 and a.home_id == b.home_id:
		return true
	if a.home_id > 0 and free_slots(a.home_id) >= 1:
		b.home_id = a.home_id
		return true
	if b.home_id > 0 and free_slots(b.home_id) >= 1:
		a.home_id = b.home_id
		return true
	var best := 0
	var bd := INF
	for id in vs.needs.housing_ids():
		if free_slots(id) >= 2:
			var bl := vs.construction.get_building(id)
			var d := Vector2(bl.position.x - a.pos.x, bl.position.z - a.pos.z).length()
			if d < bd:
				bd = d
				best = id
	if best > 0:
		a.home_id = best
		b.home_id = best
		return true
	return false


# ---------- пары ----------

func _single_adult(v: Villager) -> bool:
	return v.stage == FamilyDefs.ADULT and not v.arriving and not _partner.has(v.id) and grief(v) < FamilyDefs.COUPLE_GRIEF_BELOW \
		and not (social != null and social.is_leaving(v.id))


## Могут ли стать парой: взрослые мужчина и женщина, свободны, не родня, близкая дружба, разница лет.
func can_pair(a: Villager, b: Villager) -> bool:
	if a.sex == b.sex or not _single_adult(a) or not _single_adult(b) or related(a.id, b.id):
		return false
	if absi(a.age - b.age) > FamilyDefs.COUPLE_MAX_AGE_GAP:
		return false
	return social != null and social.friendship(a.id, b.id) >= FamilyDefs.COUPLE_FRIENDSHIP


## Заключает союз (бросок удачи — в roll_pass); пара переезжает в один дом, если есть место.
func marry(a: Villager, b: Villager) -> void:
	_partner[a.id] = b.id
	_partner[b.id] = a.id
	_names[a.id] = a.display_name
	_names[b.id] = b.display_name
	if social != null:
		social.add_friendship(a.id, b.id, 1.0)
		social.add_need(a, SocialDefs.HOPE, FamilyDefs.HOPE_WEDDING)
		social.add_need(b, SocialDefs.HOPE, FamilyDefs.HOPE_WEDDING)
	move_in_together(a, b)
	vs._jobs_dirty = true
	_emit(TOPIC_WEDDING, {"a": a.id, "b": b.id, "a_name": a.display_name, "b_name": b.display_name})


func _form_couples() -> void:
	var list: Array[Villager] = []
	for v: Villager in vs.villagers.values():
		if _single_adult(v):
			list.append(v)
	list.sort_custom(func(x: Villager, y: Villager) -> bool: return x.id < y.id)
	var cands: Array = []
	for i in list.size():
		for j in range(i + 1, list.size()):
			if can_pair(list[i], list[j]):
				cands.append([social.friendship(list[i].id, list[j].id), list[i], list[j]])
	cands.sort_custom(func(x: Array, y: Array) -> bool:
		return x[0] > y[0] or (is_equal_approx(x[0], y[0]) and (x[1].id < y[1].id or (x[1].id == y[1].id and x[2].id < y[2].id))))
	var p := 1.0 - exp(-FamilyDefs.COUPLE_RATE_PER_DAY * FamilyDefs.ROLL / _day_seconds())
	for c in cands:
		if _partner.has(c[1].id) or _partner.has(c[2].id):
			continue
		if vs._rng().randf() < p:
			marry(c[1], c[2])


## Семьи живут вместе: пара — в одном доме, дети — в доме матери (или отца), если есть место.
func _unite_households() -> void:
	var ids: Array = _partner.keys()
	ids.sort()
	for id in ids:
		var a := _v(id)
		var b := _v(int(_partner[id]))
		if a != null and b != null and a.id < b.id:
			move_in_together(a, b)
	for v: Villager in vs.villagers.values():
		if not v.is_minor():
			continue
		var pr := parent_ids(v.id)
		for pid in pr:
			var par := _v(pid)
			if par != null and par.home_id > 0:
				if par.home_id != v.home_id and free_slots(par.home_id) >= 1:
					v.home_id = par.home_id
				break


# ---------- беременность и рождение ----------

## Условия зачатия (без броска): живут вместе, есть место и еда, возраст, лимит детей и населения.
func can_conceive(f: Villager, m: Villager) -> bool:
	if f.sex != &"f" or m.sex != &"m" or int(_partner.get(f.id, 0)) != m.id or f.stage != FamilyDefs.ADULT or m.stage != FamilyDefs.ADULT:
		return false
	if _pregnant.has(f.id) or float(_postpartum.get(f.id, 0.0)) > 0.0 or f.age > FamilyDefs.FERTILE_MAX_AGE or f.sick:
		return false
	if f.home_id <= 0 or f.home_id != m.home_id or free_slots(f.home_id) < 1:
		return false
	if f.need(NeedsDefs.FOOD) < FamilyDefs.CONCEIVE_MIN_FOOD or f.need(NeedsDefs.HEALTH) < FamilyDefs.CONCEIVE_MIN_HEALTH:
		return false
	if vs.population() + _pregnant.size() >= vs.max_population:
		return false
	return children_count(f.id) < FamilyDefs.MAX_CHILDREN


## Начинает беременность, если можно (без броска удачи). false — условия не выполнены.
func conceive(f: Villager, m: Villager) -> bool:
	if not can_conceive(f, m):
		return false
	_pregnant[f.id] = {"father": m.id, "left": FamilyDefs.PREGNANCY_DAYS * _day_seconds()}
	return true


func _conceive_pass() -> void:
	var p := 1.0 - exp(-FamilyDefs.CONCEIVE_RATE_PER_DAY * FamilyDefs.ROLL / _day_seconds())
	var ids: Array = _partner.keys()
	ids.sort()
	for id in ids:
		var f := _v(id)
		var m := _v(int(_partner[id]))
		if f == null or m == null or f.sex != &"f":
			continue
		if can_conceive(f, m) and vs._rng().randf() < p:
			conceive(f, m)


func _complication_chance() -> float:
	var p := FamilyDefs.BIRTH_COMPLICATION
	if vs.needs.doctor_available():
		p *= FamilyDefs.COMPLICATION_DOCTOR_MULT
	if not vs.needs.hospital_ids().is_empty():
		p *= FamilyDefs.COMPLICATION_HOSPITAL_MULT
	return p


## Роды: нужен дом с местом и свободное место в населении, иначе ждёт. Возвращает ребёнка или null.
func try_birth(f: Villager) -> Villager:
	if not _pregnant.has(f.id):
		return null
	if vs.population() >= vs.max_population or f.home_id <= 0 or vs.needs.residents(f.home_id).size() >= vs.needs.capacity(f.home_id):
		return null
	var info: Dictionary = _pregnant[f.id]
	var m := _v(int(info["father"]))
	var rng := vs._rng()
	var sex: StringName = &"m" if rng.randi_range(0, 1) == 0 else &"f"
	var father_name := m.display_name if m != null else String(_names.get(int(info["father"]), f.display_name))
	var prof: StringName = f.profession
	if m != null and rng.randi_range(0, 1) == 1:
		prof = m.profession
	var c := Villager.generate(rng, {"sex": sex, "profession": prof, "age": 0})
	var first := c.display_name.get_slice(" ", 0)
	c.display_name = "%s %s" % [first, FamilyDefs.surname_for(father_name, sex)]
	var parents: Array[Villager] = [f]
	if m != null:
		parents.append(m)
	c.traits = _inherit_traits(parents, c.traits)
	c.backstory = VillagerDefs.gendered("Родил{ся|ась} в посёлке. Мать — %s, отец — %s." % [f.display_name, father_name], sex)
	c.skills = SkillDefs.initial(&"")
	c.stage = FamilyDefs.INFANT
	c.growth = 0.0
	c.age = 0
	c.id = vs._next_id
	vs._next_id += 1
	c.pos = f.pos
	c.home_id = f.home_id
	if rng.randf() < _complication_chance():
		f.set_need(NeedsDefs.HEALTH, f.need(NeedsDefs.HEALTH) - FamilyDefs.COMPLICATION_MOTHER_HEALTH)
		c.set_need(NeedsDefs.HEALTH, FamilyDefs.COMPLICATION_BABY_HEALTH)
	vs.villagers[c.id] = c
	_parents[c.id] = [f.id, int(info["father"])]
	_names[f.id] = f.display_name
	_names[int(info["father"])] = father_name
	_names[c.id] = c.display_name
	_care[c.id] = 1.0
	_pregnant.erase(f.id)
	_postpartum[f.id] = FamilyDefs.POSTPARTUM_DAYS
	if social != null:
		social.add_need(f, SocialDefs.HOPE, FamilyDefs.HOPE_BIRTH_MOTHER)
		for o: Villager in vs.villagers.values():
			if o != f and not o.arriving and o != c:
				social.add_need(o, SocialDefs.HOPE, FamilyDefs.HOPE_BIRTH_ALL)
	vs._jobs_dirty = true
	vs._emit(VillagerSystem.TOPIC_CHANGED, {})
	_emit(TOPIC_BORN, {"id": c.id, "name": c.display_name, "mother": f.id, "father": int(info["father"]), "mother_name": f.display_name})
	return c


## Черты ребёнка: каждая черта родителей переходит с шансом INHERIT_TRAIT_CHANCE (без несовместимых, не больше
## MAX_TRAITS); если не перешла ни одна — одна случайная (из сгенерированных).
func _inherit_traits(parents: Array[Villager], random_traits: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	var pool: Array[StringName] = []
	for p in parents:
		for t in p.traits:
			if not pool.has(t):
				pool.append(t)
	pool.sort()
	for t in pool:
		if out.size() >= FamilyDefs.MAX_TRAITS:
			break
		if vs._rng().randf() >= FamilyDefs.INHERIT_TRAIT_CHANCE:
			continue
		var ok := true
		for o in out:
			if TraitDefs.are_exclusive(o, t):
				ok = false
		if ok:
			out.append(t)
	if out.is_empty() and not random_traits.is_empty():
		out.append(random_traits[0])
	return out


# ---------- рост ----------

func school_days(id: int) -> float:
	return float(_school.get(id, 0.0))


func care_of(id: int) -> float:
	return float(_care.get(id, 1.0))


## Стартовые навыки взрослого: профессия (половина без школы) + бонус школы пропорционально посещению.
func adult_skills(prof: StringName, school_d: float) -> Dictionary:
	var f := clampf(school_d / FamilyDefs.SCHOOL_FULL_DAYS, 0.0, 1.0)
	var init := SkillDefs.initial(prof)
	var out := {}
	for c in TaskDefs.WORK_CATEGORIES:
		var base := SkillDefs.BASE_SKILL
		var prof_part: float = float(init[c]) - base
		out[c] = clampf(base + prof_part * lerpf(FamilyDefs.HOME_TRAINING_SHARE, 1.0, f) + FamilyDefs.SCHOOL_BONUS_ALL * f, 0.0, SkillDefs.MAX_SKILL)
	return out


## Ребёнок становится взрослым работником: навыки по школе, жильё пересматривается, уведомление.
func grow_up(v: Villager) -> void:
	v.skills = adult_skills(v.profession, school_days(v.id))
	v.stage = FamilyDefs.ADULT
	v.age = FamilyDefs.ADULT_AGE
	v.growth = 0.0
	v.age_acc = 0.0
	v.think_cd = 0.0
	v.task = {}
	_school.erase(v.id)
	_care.erase(v.id)
	vs._jobs_dirty = true
	vs.needs.assign_homes()
	_emit(TOPIC_GREW, {"id": v.id, "name": v.display_name, "profession": v.profession})


func _guardians_near(c: Villager) -> bool:
	if c.task.get("kind", &"") == &"school" and c.at_site:
		return true
	for o: Villager in vs.villagers.values():
		if o == c or o.is_minor() or o.arriving or o.sick:
			continue
		if not is_guardian(o, c):
			continue
		if Vector2(o.pos.x - c.pos.x, o.pos.z - c.pos.z).length() <= FamilyDefs.CARE_RADIUS:
			return true
	return false


## Опекун: родитель, а у сироты — взрослый из того же дома.
func is_guardian(o: Villager, c: Villager) -> bool:
	var pr := parent_ids(c.id)
	if pr.has(o.id):
		return true
	var any_alive := false
	for pid in pr:
		if pid != 0 and _v(pid) != null:
			any_alive = true
	return not any_alive and c.home_id > 0 and o.home_id == c.home_id


# ---------- тик ----------

func tick(sim: Simulation, dt: float) -> void:
	_sim = sim
	if dt <= 0.0 or not enabled:
		return
	_acc += dt
	_roll_acc += dt
	if _acc >= FamilyDefs.STEP:
		var step := _acc
		_acc = 0.0
		step_pass(step)
	if _roll_acc >= FamilyDefs.ROLL:
		_roll_acc = 0.0
		roll_pass()


## Годовой расчёт: старение, рост детей, забота, школа, горе, роды. dt — игровые секунды.
func step_pass(dt: float) -> void:
	var days := dt / _day_seconds()
	for v: Villager in vs.villagers.values().duplicate():
		if v.arriving or not vs.villagers.has(v.id):
			continue
		if _grief.has(v.id):
			var g := float(_grief[v.id]) - FamilyDefs.GRIEF_DECAY_PER_DAY * days
			if g <= 0.0:
				_grief.erase(v.id)
			else:
				_grief[v.id] = g
		if v.is_minor():
			_step_minor(v, days)
		else:
			_step_adult(v, days)
	for id in _postpartum.keys():
		_postpartum[id] = float(_postpartum[id]) - days
		if float(_postpartum[id]) <= 0.0:
			_postpartum.erase(id)
	for id in _pregnant.keys():
		var f := _v(id)
		if f == null:
			_pregnant.erase(id)
			continue
		_pregnant[id]["left"] = float(_pregnant[id]["left"]) - dt
		if float(_pregnant[id]["left"]) <= 0.0:
			try_birth(f)


func _step_minor(v: Villager, days: float) -> void:
	var care := care_of(v.id)
	if _guardians_near(v):
		care += FamilyDefs.CARE_RESTORE_PER_DAY * days
	else:
		care -= FamilyDefs.CARE_DECAY_PER_DAY * (FamilyDefs.CARE_INFANT_MULT if v.stage == FamilyDefs.INFANT else 1.0) * days
	care = clampf(care, 0.0, 1.0)
	_care[v.id] = care
	if v.task.get("kind", &"") == &"school" and v.at_site:
		_school[v.id] = school_days(v.id) + days
	v.growth += days * (FamilyDefs.STUNT_GROWTH_MULT if care < FamilyDefs.CARE_STUNT else 1.0)
	v.age = int(floor(v.growth))
	if v.growth >= FamilyDefs.ADULT_AT_DAYS:
		grow_up(v)
	else:
		v.stage = FamilyDefs.stage_for_years(v.growth)


func _step_adult(v: Villager, days: float) -> void:
	v.age_acc += days
	while v.age_acc >= FamilyDefs.ADULT_YEAR_DAYS:
		v.age_acc -= FamilyDefs.ADULT_YEAR_DAYS
		v.age += 1
	if v.age >= FamilyDefs.DEATH_FROM and v.can_die():
		var rate_year := FamilyDefs.DEATH_PER_YEAR_PER_AGE * float(v.age - FamilyDefs.DEATH_FROM + 1)
		var p := 1.0 - exp(-rate_year / FamilyDefs.ADULT_YEAR_DAYS * days)
		if vs._rng().randf() < p:
			vs.kill_villager(v.id, CAUSE_OLD_AGE)


## Броски семьи: пары, переезд, зачатие.
func roll_pass() -> void:
	if social != null:
		_form_couples()
	_unite_households()
	_conceive_pass()


# ---------- множители ----------

## Множитель скорости работы от возраста: подросток вполсилы, дети 0, пожилые медленнее.
func work_multiplier(v: Villager) -> float:
	match v.stage:
		FamilyDefs.TEEN: return FamilyDefs.TEEN_WORK_MULT
		FamilyDefs.INFANT, FamilyDefs.CHILD: return 0.0
	return FamilyDefs.elder_multiplier(v.age)


func consumption_mult(v: Villager) -> float:
	return float(FamilyDefs.CONSUME_MULT.get(v.stage, 1.0))


func warmth_mult(v: Villager) -> float:
	return float(FamilyDefs.WARMTH_MULT.get(v.stage, 1.0))


## Можно ли несовершеннолетнему взять работу: дети нет, подросток — только по хозяйству.
func may_work(v: Villager, job: Dictionary) -> bool:
	return v.stage == FamilyDefs.TEEN and job.get("tcat", &"") == TaskDefs.CHORES


# ---------- семья как потребность и горе ----------

func grief(v: Villager) -> float:
	return float(_grief.get(v.id, 0.0))


func add_grief(id: int, x: float) -> void:
	_grief[id] = clampf(float(_grief.get(id, 0.0)) + x, 0.0, 1.0)


## Вычет из настроения от горя.
func grief_penalty(v: Villager) -> float:
	return FamilyDefs.GRIEF_MOOD_WEIGHT * grief(v) if enabled else 0.0


## Потребность «семья» 0..1: партнёр и дети в посёлке удовлетворяют, горе снижает.
func family_need_of(id: int) -> float:
	var v := _v(id)
	if v == null:
		return -1.0
	var base := FamilyDefs.NEED_PARTNER if partner_of(id) != null else FamilyDefs.NEED_ALONE
	var kids := 0
	for c in children_of(id):
		kids += 1
	base += FamilyDefs.NEED_PER_CHILD * float(kids)
	return clampf(minf(base, 1.0) - FamilyDefs.GRIEF_NEED_WEIGHT * grief(v), 0.0, 1.0)


func _on_gone(p: Dictionary) -> void:
	var id := int(p.get("id", 0))
	_names[id] = String(p.get("name", "?"))
	var pid := int(_partner.get(id, 0))
	if pid != 0:
		_partner.erase(id)
		_partner.erase(pid)
		add_grief(pid, FamilyDefs.GRIEF_PARTNER)
	var pr := parent_ids(id)
	for x in pr:
		if x != 0 and _v(x) != null:
			add_grief(x, FamilyDefs.GRIEF_CHILD)
	for c in _parents:
		var cp: Array = _parents[c]
		if (cp[0] == id or cp[1] == id) and _v(c) != null:
			add_grief(c, FamilyDefs.GRIEF_PARENT)
		elif c != id and _v(c) != null and cp != [0, 0] and (pr[0] != 0 and cp[0] == pr[0] or pr[1] != 0 and cp[1] == pr[1]):
			add_grief(c, FamilyDefs.GRIEF_SIBLING)
	_pregnant.erase(id)
	_postpartum.erase(id)
	_school.erase(id)
	_care.erase(id)
	_grief.erase(id)


# ---------- дело ----------

func _job(kind: StringName, target: int, dest: StringName) -> Dictionary:
	return {"key": "n:%s:%d" % [kind, target], "cat": &"", "kind": kind, "target": target, "dest": dest}


func school_building() -> int:
	var best := 0
	for id in vs.construction.buildings:
		var b: Building = vs.construction.buildings[id]
		if b.is_done() and b.type == &"school" and (best == 0 or id < best):
			best = id
	return best


func school_open() -> bool:
	var h := _hour()
	return school_building() > 0 and h >= FamilyDefs.SCHOOL_START_HOUR and h < FamilyDefs.SCHOOL_END_HOUR


## Дело семьи ({} — нет): дети в школе или во дворе, опекун — к ребёнку, которому нужна забота.
func job_for(v: Villager, cur: StringName) -> Dictionary:
	if not enabled or v.arriving:
		return {}
	if v.is_minor():
		if v.stage != FamilyDefs.INFANT and school_open():
			return _job(&"school", school_building(), &"school")
		if v.stage == FamilyDefs.TEEN:
			return {}
		return _job(&"play", maxi(v.home_id, 0), &"home")
	if v.sick:
		return {}
	var best: Villager = null
	for c: Villager in vs.villagers.values():
		if not c.is_minor() or not is_guardian(v, c):
			continue
		var care := care_of(c.id)
		var mine: bool = cur == &"care" and int(v.task.get("target", 0)) == c.id
		if care < FamilyDefs.CARE_CALL or (mine and care < FamilyDefs.CARE_DONE):
			if _carers(c.id, v) == 0 and (best == null or care < care_of(best.id)):
				best = c
	return _job(&"care", best.id, &"villager") if best != null else {}


func _carers(child: int, except: Villager) -> int:
	var n := 0
	for o: Villager in vs.villagers.values():
		if o != except and o.task.get("kind", &"") == &"care" and int(o.task.get("target", 0)) == child:
			n += 1
	return n


# ---------- описание ----------

func tree_lines(v: Villager) -> Array[String]:
	var out: Array[String] = []
	var p := partner_of(v.id)
	out.append("Партнёр: " + (p.display_name if p != null else "нет"))
	var pr := parent_ids(v.id)
	var names: Array[String] = []
	for x in pr:
		if x != 0:
			names.append(_name_of(x) + ("" if _v(x) != null else " (нет в посёлке)"))
	out.append("Родители: " + (", ".join(names) if not names.is_empty() else "неизвестны"))
	var kids: Array[String] = []
	for c in children_of(v.id):
		kids.append("%s (%s, %s)" % [c.display_name, FamilyDefs.stage_label(c), VillagerDefs.age_text(c.age)])
	out.append("Дети: " + ("; ".join(kids) if not kids.is_empty() else "нет"))
	if is_pregnant(v.id):
		out.append("Ждёт ребёнка (ещё %.1f сут.)" % pregnancy_left_days(v.id))
	if grief(v) > 0.05:
		out.append("Горюет по близкому")
	return out


## Раздел «Семья» карточки жителя.
func card_text(v: Villager) -> String:
	var t := "Возраст: %s, %s\n" % [VillagerDefs.age_text(v.age), FamilyDefs.stage_label(v)]
	t += "\n".join(tree_lines(v))
	if v.is_minor():
		t += "\nЗабота: %s %d%%" % [SocialDefs.bar(care_of(v.id)), roundi(care_of(v.id) * 100.0)]
		t += "\nШкола: %.1f сут." % school_days(v.id)
	return t


# ---------- сохранение ----------

func get_save_key() -> StringName:
	return &"family"


func _ints(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d:
		o[str(k)] = d[k]
	return o


func save_state() -> Dictionary:
	var par := {}
	for k in _parents:
		par[str(k)] = [_parents[k][0], _parents[k][1]]
	var preg := {}
	for k in _pregnant:
		preg[str(k)] = {"father": _pregnant[k]["father"], "left": _pregnant[k]["left"]}
	return {"partner": _ints(_partner), "parents": par, "names": _ints(_names), "pregnant": preg,
		"postpartum": _ints(_postpartum), "grief": _ints(_grief), "school": _ints(_school), "care": _ints(_care)}


func load_state(d: Dictionary) -> void:
	for dict in [_partner, _parents, _names, _pregnant, _postpartum, _grief, _school, _care]:
		dict.clear()
	var s: Dictionary
	s = d.get("partner", {}) if d.get("partner") is Dictionary else {}
	for k in s:
		_partner[SaveManager.to_int(k, 0)] = SaveManager.to_int(s[k], 0)
	s = d.get("parents", {}) if d.get("parents") is Dictionary else {}
	for k in s:
		if s[k] is Array and s[k].size() == 2:
			_parents[SaveManager.to_int(k, 0)] = [SaveManager.to_int(s[k][0], 0), SaveManager.to_int(s[k][1], 0)]
	s = d.get("names", {}) if d.get("names") is Dictionary else {}
	for k in s:
		_names[SaveManager.to_int(k, 0)] = String(s[k])
	s = d.get("pregnant", {}) if d.get("pregnant") is Dictionary else {}
	for k in s:
		if s[k] is Dictionary:
			_pregnant[SaveManager.to_int(k, 0)] = {"father": SaveManager.to_int(s[k].get("father"), 0), "left": float(s[k].get("left", 0.0))}
	for pair in [["postpartum", _postpartum], ["grief", _grief], ["school", _school], ["care", _care]]:
		s = d.get(pair[0], {}) if d.get(pair[0]) is Dictionary else {}
		for k in s:
			pair[1][SaveManager.to_int(k, 0)] = float(s[k])
