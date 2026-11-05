class_name Villager
extends Walker
## Один житель. Только данные и состояние; поведение — в VillagerSystem.

var id: int = 0
var display_name := ""
var sex: StringName = &"m"          # &"m" | &"f"
var age: int = 30
var backstory := ""
var profession: StringName = &"builder"
var traits: Array[StringName] = []  # 1..3 черты (TraitDefs)
## Навык по категориям работы (TaskDefs.WORK_CATEGORIES) 0..1, см. SkillDefs.
var skills: Dictionary = {}         # StringName категория -> float
var is_hero := false
var immortal := false               # герой не может умереть (системы смерти обязаны проверять)
var arriving := false               # новичок идёт в посёлок
## Текущая задача: {} или {kind, cat, key, target, phase, work, carry, src, res, dest}
## (res — что несёт в руках, dest — куда: &"stove"|&"woodpile"|&"house"|&"canteen").
var task: Dictionary = {}
var at_site := false                # стоит на месте работы (для анимации/текста)
var think_cd := 0.0
var needs: Dictionary = NeedsDefs.full()  # NeedsDefs.NEEDS -> 0..1 (шаг 11)
var sick := false
var home_id: int = 0                # здание-жильё, 0 — бездомный (расселяет VillagerSystem.assign_homes)
var sick_acc := 0.0                 # накопление до следующего броска на болезнь
var banned: Dictionary = {}         # key -> время, до которого цель недоступна (не сохраняется)


func can_die() -> bool:
	return not immortal


func profession_name() -> String:
	return VillagerDefs.profession_name(profession)


func need(n: StringName) -> float:
	return needs.get(n, 1.0)


func set_need(n: StringName, x: float) -> void:
	needs[n] = clampf(x, 0.0, 1.0)


func skill(cat: StringName) -> float:
	return skills.get(cat, SkillDefs.BASE_SKILL)


## Случайный житель. opts: sex (&"m"/&"f"), profession, hero (bool), age.
## Все случайные числа — только из rng (детерминизм).
static func generate(rng: RandomNumberGenerator, opts: Dictionary = {}) -> Villager:
	var v := Villager.new()
	v.sex = opts.get("sex", &"m" if rng.randi_range(0, 1) == 0 else &"f")
	var si := rng.randi_range(0, VillagerDefs.SURNAMES.size() - 1)
	var names: Array[String] = VillagerDefs.MALE_NAMES if v.sex == &"m" else VillagerDefs.FEMALE_NAMES
	var first: String = names[rng.randi_range(0, names.size() - 1)]
	v.display_name = "%s %s" % [first, VillagerDefs.SURNAMES[si][0 if v.sex == &"m" else 1]]
	v.age = int(opts.get("age", rng.randi_range(VillagerDefs.AGE_MIN, VillagerDefs.AGE_MAX)))
	var prof_idx := rng.randi_range(0, VillagerDefs.PROFESSIONS.size() - 1)
	v.profession = opts.get("profession", VillagerDefs.PROFESSIONS[prof_idx])
	v.skills = SkillDefs.initial(v.profession)
	# Черты: количество, затем случайные без дублей и несовместимых.
	var want := rng.randi_range(VillagerDefs.TRAITS_MIN, VillagerDefs.TRAITS_MAX)
	var pool := TraitDefs.ids()
	var guard := 0
	while v.traits.size() < want and guard < 50:
		guard += 1
		var t: StringName = pool[rng.randi_range(0, pool.size() - 1)]
		var ok := not v.traits.has(t)
		for o in v.traits:
			if TraitDefs.are_exclusive(o, t):
				ok = false
		if ok:
			v.traits.append(t)
	var past: Array = VillagerDefs.PAST_LIFE[v.profession]
	var a: String = past[rng.randi_range(0, past.size() - 1)]
	var b: String = VillagerDefs.ARRIVAL_STORY[rng.randi_range(0, VillagerDefs.ARRIVAL_STORY.size() - 1)]
	v.backstory = VillagerDefs.gendered(a + " " + b, v.sex)
	v.is_hero = opts.get("hero", false)
	v.immortal = v.is_hero
	return v


func to_dict() -> Dictionary:
	var tr := []
	for t in traits:
		tr.append(String(t))
	var sk := {}
	for k in skills:
		sk[String(k)] = skills[k]
	var tk := {}
	for k in task:
		tk[String(k)] = String(task[k]) if (task[k] is StringName) else task[k]
	var nd := {}
	for k in needs:
		nd[String(k)] = needs[k]
	return {
		"id": id, "name": display_name, "sex": String(sex), "age": age, "backstory": backstory,
		"profession": String(profession), "traits": tr, "skills": sk,
		"hero": is_hero, "immortal": immortal, "arriving": arriving,
		"pos": [pos.x, pos.y, pos.z], "facing": facing, "task": tk, "think_cd": think_cd,
		"needs": nd, "sick": sick, "home_id": home_id, "sick_acc": sick_acc,
	}


static func from_dict(d: Dictionary) -> Villager:
	var v := Villager.new()
	v.id = SaveManager.to_int(d.get("id"), 0)
	v.display_name = String(d.get("name", ""))
	v.sex = &"f" if String(d.get("sex", "m")) == "f" else &"m"
	v.age = SaveManager.to_int(d.get("age"), 30)
	v.backstory = String(d.get("backstory", ""))
	var prof := StringName(String(d.get("profession", "")))
	v.profession = prof if VillagerDefs.PROFESSIONS.has(prof) else VillagerDefs.PROFESSIONS[0]
	if d.get("traits") is Array:
		for t in d["traits"]:
			var tid := StringName(String(t))
			if TraitDefs.exists(tid) and not v.traits.has(tid):
				v.traits.append(tid)
	v.skills = SkillDefs.initial(v.profession)  # старые/битые сохранения: недостающее — по профессии
	if d.get("skills") is Dictionary:
		for k in d["skills"]:
			var c := StringName(String(k))
			if TaskDefs.WORK_CATEGORIES.has(c):
				v.skills[c] = clampf(float(d["skills"][k]), 0.0, SkillDefs.MAX_SKILL)
	v.is_hero = bool(d.get("hero", false))
	v.immortal = bool(d.get("immortal", false)) or v.is_hero
	v.arriving = bool(d.get("arriving", false))
	if d.get("needs") is Dictionary:
		for n in NeedsDefs.NEEDS:
			if d["needs"].has(String(n)):
				v.set_need(n, float(d["needs"][String(n)]))
	v.sick = bool(d.get("sick", false))
	v.home_id = SaveManager.to_int(d.get("home_id"), 0)
	v.sick_acc = float(d.get("sick_acc", 0.0))
	var p = d.get("pos")
	if p is Array and p.size() == 3:
		v.pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
	v.facing = float(d.get("facing", 0.0))
	v.think_cd = float(d.get("think_cd", 0.0))
	if d.get("task") is Dictionary:
		for k in d["task"]:
			var val = d["task"][k]
			match String(k):
				"kind", "cat", "phase", "res", "dest":
					v.task[String(k)] = StringName(String(val))
				"key":
					v.task[String(k)] = String(val)
				"target", "carry", "src":
					v.task[String(k)] = SaveManager.to_int(val, 0)
				"work":
					v.task[String(k)] = float(val)
	# Нормализация: битая задача (нет вида/ключа) снимается.
	if not v.task.has("kind") or not v.task.has("key"):
		v.task = {}
	else:
		v.task["cat"] = v.task.get("cat", &"")
		v.task["target"] = v.task.get("target", 0)
		v.task["phase"] = v.task.get("phase", &"")
		v.task["work"] = v.task.get("work", 0.0)
		v.task["carry"] = v.task.get("carry", 0)
		v.task["src"] = v.task.get("src", 0)
		v.task["res"] = v.task.get("res", &"")
		v.task["dest"] = v.task.get("dest", &"")
	return v
