class_name SocialSystem
extends SimSystem
## Психика жителей (шаг 22), design/gdd/mental-needs.md: общение, семья, надежда, досуг; дружба и ссоры,
## клуб, баня, праздники; плохое настроение замедляет работу, повышает шанс болезни, а при долгом отчаянии
## житель уходит. Герой и собака не ссорятся, не уходят и не умирают (Villager.can_die()).
## Принадлежит симуляции как отдельная система (ключ сохранения &"social"); VillagerSystem знает её через
## vs.social (null — психика выключена, как в старых тестах). Баланс — SocialDefs.
##
## ХУКИ: set_family(id, x) — шаг 23 (семья и дети); on_villager_left — шаг 24 (соседи): Callable(dict).

const TOPIC_QUARREL := &"villager_quarrel"          # {a, b, a_name, b_name}
const TOPIC_LEFT := &"villager_left"                # {id, name, profession}
const TOPIC_HOLIDAY_STARTED := &"holiday_started"   # {id, name, called, feast}
const TOPIC_HOLIDAY_ENDED := &"holiday_ended"       # {id, name}

const KINDS: Array[StringName] = [&"talk", &"club", &"bath", &"party", &"leave"]

var vs: VillagerSystem
var seasons: SeasonSystem            # null — календарных праздников нет
var enabled := true
## ХУК шага 24: вызывается, когда житель ушёл (Callable(payload: Dictionary)); пусто — просто исчезает.
var on_villager_left: Callable = Callable()
## ХУК шага 23: Callable(id: int) -> float (потребность в семье 0..1) или отрицательное (нейтрально).
var family_provider: Callable = Callable()

var holiday: Dictionary = {}         # {} или {id, name, left, called, feast, attended: {id: true}}
var _st: Dictionary = {}             # id -> {social, family, hope, fun, idle, misery, bath_cd, quarrel_cd}
var _friends: Dictionary = {}        # "a:b" -> -1..1
var _leaving: Dictionary = {}        # id -> {to: Vector3, t: float}
var _last_holiday := ""
var _call_cd := 0.0                  # игр. с до следующего «праздника из клуба»
var _acc := 0.0
var _quarrel_acc := 0.0
var _sim: Simulation


func _init(vs_in: VillagerSystem) -> void:
	vs = vs_in
	vs.social = self


func attach(sim: Simulation) -> void:
	_sim = sim
	sim.bus.subscribe(ClimateSystem.TOPIC_FIRST_BIRDS, _on_first_birds)
	sim.bus.subscribe(ClimateSystem.TOPIC_WARMING_MILESTONE, _on_warming)
	sim.bus.subscribe(VillagerSystem.TOPIC_ARRIVED, _on_arrived)


func bind(seasons_in: SeasonSystem) -> void:
	seasons = seasons_in


static func is_social_kind(kind: StringName) -> bool:
	return KINDS.has(kind)


func _emit(topic: StringName, payload: Dictionary) -> void:
	if _sim != null:
		_sim.bus.emit(topic, payload)


func _day_seconds() -> float:
	return _sim.clock.day_seconds() if _sim != null else GameClock.DEFAULT_DAY_LENGTH


func _hour() -> float:
	return _sim.clock.get_hour() if _sim != null else 12.0


# ---------- состояние жителей ----------

## Состояние жителя (создаётся при первом обращении: герой стартует бодрее новичка).
func st(v: Villager) -> Dictionary:
	if not _st.has(v.id):
		var base: Dictionary = SocialDefs.HERO_START if v.is_hero else SocialDefs.START
		_st[v.id] = {SocialDefs.SOCIAL: base[SocialDefs.SOCIAL], SocialDefs.FAMILY: base[SocialDefs.FAMILY],
			SocialDefs.HOPE: base[SocialDefs.HOPE], SocialDefs.FUN: base[SocialDefs.FUN],
			"idle": 0.0, "misery": 0.0, "bath_cd": 0.0, "quarrel_cd": 0.0}
	return _st[v.id]


func need(v: Villager, n: StringName) -> float:
	return float(st(v)[n])


func set_need(v: Villager, n: StringName, x: float) -> void:
	st(v)[n] = clampf(x, 0.0, 1.0)


func add_need(v: Villager, n: StringName, dx: float) -> void:
	set_need(v, n, need(v, n) + dx)


## ХУК шага 23: семья удовлетворяет потребность (0..1).
func set_family(v: Villager, x: float) -> void:
	set_need(v, SocialDefs.FAMILY, x)


## Настроение 0..1: взвешенные психические нужды минус влияние телесных страданий.
func mood(v: Villager) -> float:
	var s := st(v)
	var m := 0.0
	for n in SocialDefs.NEEDS:
		m += float(SocialDefs.MOOD_WEIGHTS[n]) * float(s[n])
	m -= SocialDefs.PHYSICAL_WEIGHT * vs.suffering(v)
	return clampf(m, 0.0, 1.0)


func mood_word(v: Villager) -> String:
	return SocialDefs.mood_word(mood(v))


## Средняя настроение посёлка (без прибывающих); 1.0 — никого нет.
func settlement_mood() -> float:
	var sum := 0.0
	var n := 0
	for v: Villager in vs.villagers.values():
		if not v.arriving:
			sum += mood(v)
			n += 1
	return sum / float(n) if n > 0 else 1.0


## Множитель скорости работы от настроения (интеграция: VillagerSystem.needs_multiplier).
func work_multiplier(v: Villager) -> float:
	return SocialDefs.rate_multiplier(mood(v)) if enabled else 1.0


## Добавка к шансу заболеть в сутки (интеграция: NeedsSystem).
func sick_bonus(v: Villager) -> float:
	return SocialDefs.sick_bonus(mood(v)) if enabled else 0.0


# ---------- дружба ----------

func friendship(a: int, b: int) -> float:
	return float(_friends.get(SocialDefs.pair_key(a, b), 0.0))


func add_friendship(a: int, b: int, delta: float) -> void:
	if a == b:
		return
	var k := SocialDefs.pair_key(a, b)
	var x := clampf(float(_friends.get(k, 0.0)) + delta, -1.0, 1.0)
	if absf(x) < 0.001:
		_friends.erase(k)
	else:
		_friends[k] = x


func are_friends(a: int, b: int) -> bool:
	return friendship(a, b) >= SocialDefs.FRIEND_AT


## Друзья жителя: [[id, значение], ...] по убыванию, не больше FRIEND_LIST_MAX.
func friends_of(v: Villager) -> Array:
	var out: Array = []
	for o: Villager in vs.villagers.values():
		if o.id != v.id:
			var f := friendship(v.id, o.id)
			if f >= SocialDefs.FRIEND_AT:
				out.append([o.id, f])
	out.sort_custom(func(x: Array, y: Array) -> bool: return x[1] > y[1] or (is_equal_approx(x[1], y[1]) and x[0] < y[0]))
	return out.slice(0, SocialDefs.FRIEND_LIST_MAX)


func enemies_of(v: Villager) -> Array:
	var out: Array = []
	for o: Villager in vs.villagers.values():
		if o.id != v.id and friendship(v.id, o.id) <= SocialDefs.HOSTILE_AT:
			out.append(o.id)
	return out


func _friend_gain(a: Villager, b: Villager, per_day: float, days: float) -> void:
	var m := SocialDefs.trait_mult(SocialDefs.TRAIT_FRIEND_MULT, a.traits) * SocialDefs.trait_mult(SocialDefs.TRAIT_FRIEND_MULT, b.traits)
	add_friendship(a.id, b.id, per_day * m * days)


# ---------- события ----------

func raise_hope_all(x: float) -> void:
	for v: Villager in vs.villagers.values():
		if not v.arriving:
			add_need(v, SocialDefs.HOPE, x)


func _on_first_birds(_p: Dictionary) -> void:
	raise_hope_all(SocialDefs.HOPE_FIRST_BIRDS)


func _on_warming(_p: Dictionary) -> void:
	raise_hope_all(SocialDefs.HOPE_WARMING_MILESTONE)


func _on_arrived(p: Dictionary) -> void:
	var nid := int(p.get("id", 0))
	for v: Villager in vs.villagers.values():
		if not v.arriving and v.id != nid:
			add_need(v, SocialDefs.HOPE, SocialDefs.HOPE_NEWCOMER)


# ---------- тик ----------

func tick(sim: Simulation, dt: float) -> void:
	_sim = sim
	if dt <= 0.0 or not enabled:
		return
	_call_cd = maxf(0.0, _call_cd - dt)
	_tick_holiday(dt)
	_tick_leaving(dt)
	_acc += dt
	_quarrel_acc += dt
	if _acc >= SocialDefs.STEP:
		var step := _acc
		_acc = 0.0
		_process(step)
	if _quarrel_acc >= SocialDefs.QUARREL_ROLL:
		_quarrel_acc = 0.0
		_quarrel_pass()


func _active(v: Villager) -> bool:
	return not v.arriving and not _leaving.has(v.id)


func _process(dt: float) -> void:
	var days := dt / _day_seconds()
	for id in _st.keys():
		if not vs.villagers.has(id):
			_st.erase(id)
	var groups := {}   # "тип:ключ" -> Array[Villager]
	for v: Villager in vs.villagers.values():
		if v.arriving:
			continue
		var s := st(v)
		var kind: StringName = v.task.get("kind", &"")
		var here := v.at_site and not v.task.is_empty()
		# убыль
		s[SocialDefs.SOCIAL] = clampf(float(s[SocialDefs.SOCIAL]) - SocialDefs.SOCIAL_DECAY_PER_DAY * SocialDefs.trait_mult(SocialDefs.TRAIT_SOCIAL_DECAY_MULT, v.traits) * days, 0.0, 1.0)
		s[SocialDefs.FUN] = clampf(float(s[SocialDefs.FUN]) - SocialDefs.FUN_DECAY_PER_DAY * days, 0.0, 1.0)
		var hope_d := -SocialDefs.HOPE_DECAY_PER_DAY
		# семья (хук шага 23)
		if family_provider.is_valid():
			var fam := float(family_provider.call(v.id))
			if fam >= 0.0:
				s[SocialDefs.FAMILY] = clampf(fam, 0.0, 1.0)
		s["bath_cd"] = maxf(0.0, float(s["bath_cd"]) - days)
		s["quarrel_cd"] = maxf(0.0, float(s["quarrel_cd"]) - days)
		# занятия
		if kind == &"talk" and here:
			add_need(v, SocialDefs.SOCIAL, SocialDefs.TALK_SOCIAL_PER_DAY * days)
			var partner := vs.get_villager(int(v.task.get("target", 0)))
			if partner != null and partner.id != v.id and not partner.arriving:
				add_need(partner, SocialDefs.SOCIAL, SocialDefs.TALK_SOCIAL_PER_DAY * days)
				_friend_gain(v, partner, SocialDefs.FRIEND_TALK_PER_DAY, days)
		elif kind == &"club" and here:
			add_need(v, SocialDefs.FUN, SocialDefs.CLUB_FUN_PER_DAY * days)
			add_need(v, SocialDefs.SOCIAL, SocialDefs.CLUB_SOCIAL_PER_DAY * days)
			_group(groups, "club:%d" % int(v.task.get("target", 0)), v)
		elif kind == &"party" and here:
			var k := 1.0 if bool(holiday.get("feast", true)) else SocialDefs.HOLIDAY_NO_FOOD_MULT
			add_need(v, SocialDefs.FUN, SocialDefs.HOLIDAY_FUN_PER_DAY * k * days)
			add_need(v, SocialDefs.SOCIAL, SocialDefs.HOLIDAY_SOCIAL_PER_DAY * k * days)
			if not holiday.is_empty():
				holiday["attended"][v.id] = true
			_group(groups, "party", v)
		elif (kind == &"eat" or kind == &"drink") and here and v.task.get("dest", &"") == &"canteen" and NeedsDefs.HOOK_SHARED_MEAL:
			_group(groups, "meal:%d" % int(v.task.get("target", 0)), v)
		elif kind == &"bath" and here:
			_group(groups, "bath:%d" % int(v.task.get("target", 0)), v)
		elif here and not NeedsSystem.is_need_kind(kind) and not SocialSystem.is_social_kind(kind) and kind != &"arrive":
			_group(groups, "work:" + String(v.task.get("key", "")), v)
			hope_d += _meaning(v) * 1.0
			s["idle"] = 0.0
		if v.task.is_empty() or kind == &"arrive":
			s["idle"] = float(s["idle"]) + days
			if float(s["idle"]) > SocialDefs.IDLE_GRACE_DAYS:
				hope_d -= SocialDefs.IDLE_HOPE_LOSS_PER_DAY
		add_need(v, SocialDefs.HOPE, hope_d * days)
		# отчаяние -> уход
		if mood(v) < SocialDefs.LEAVE_MOOD:
			s["misery"] = float(s["misery"]) + days
		else:
			s["misery"] = maxf(0.0, float(s["misery"]) - days * SocialDefs.LEAVE_RECOVER_MULT)
		if float(s["misery"]) >= SocialDefs.LEAVE_AFTER_DAYS and _may_leave(v):
			start_leave(v)
	_apply_groups(groups, days)
	_decay_friends(days)


func _group(groups: Dictionary, key: String, v: Villager) -> void:
	if not groups.has(key):
		groups[key] = []
	groups[key].append(v)


## Прирост надежды в сутки от осмысленной работы (по профессии/навыку — больше).
func _meaning(v: Villager) -> float:
	var cat: StringName = v.task.get("cat", &"")
	if cat != &"" and (vs.profession_multiplier(v, cat) > 1.0 or v.skill(cat) >= SocialDefs.MEANING_SKILL):
		return SocialDefs.MEANING_MATCH_PER_DAY
	return SocialDefs.MEANING_WORK_PER_DAY


## Групповые эффекты: пары в одной группе дружат; на работе и в столовой — ещё и общение.
func _apply_groups(groups: Dictionary, days: float) -> void:
	for key: String in groups:
		var list: Array = groups[key]
		var type := key.get_slice(":", 0)
		var rate := 0.0
		match type:
			"work": rate = SocialDefs.FRIEND_WORK_PER_DAY
			"meal": rate = SocialDefs.FRIEND_MEAL_PER_DAY
			"club": rate = SocialDefs.FRIEND_CLUB_PER_DAY
			"party": rate = SocialDefs.FRIEND_PARTY_PER_DAY
		if list.size() >= 2:
			for i in list.size():
				for j in range(i + 1, list.size()):
					if rate > 0.0:
						_friend_gain(list[i], list[j], rate, days)
			if type == "work":
				for v: Villager in list:
					add_need(v, SocialDefs.SOCIAL, SocialDefs.WORK_SOCIAL_PER_DAY * days)
		if type == "meal" and list.size() >= 2:
			for v: Villager in list:
				add_need(v, SocialDefs.SOCIAL, SocialDefs.MEAL_SOCIAL_PER_DAY * days)
				add_need(v, SocialDefs.FUN, SocialDefs.MEAL_FUN_PER_DAY * days)


func _decay_friends(days: float) -> void:
	for k in _friends.keys():
		var x: float = _friends[k]
		if x > 0.0:
			x = maxf(0.0, x - SocialDefs.FRIEND_DECAY_PER_DAY * days)
			if x <= 0.0:
				_friends.erase(k)
			else:
				_friends[k] = x


# ---------- ссоры ----------

## Шанс ссоры в сутки у жителя v с партнёром p при настроении m (0 — не ссорится).
func quarrel_rate(v: Villager, p: Villager, m: float) -> float:
	if m >= SocialDefs.QUARREL_MOOD_BELOW or v.is_hero or p.is_hero:
		return 0.0
	var r := SocialDefs.QUARREL_PER_DAY * SocialDefs.trait_mult(SocialDefs.TRAIT_QUARREL_MULT, v.traits)
	r *= 1.0 + (SocialDefs.QUARREL_MOOD_BELOW - m) / SocialDefs.QUARREL_MOOD_BELOW
	if friendship(v.id, p.id) <= SocialDefs.HOSTILE_AT:
		r *= SocialDefs.HOSTILE_QUARREL_MULT
	return r


func _quarrel_pass() -> void:
	var ids: Array = vs.villagers.keys()
	ids.sort()
	for id in ids:
		var v: Villager = vs.villagers.get(id)
		if v == null or v.is_hero or not _active(v) or float(st(v)["quarrel_cd"]) > 0.0:
			continue
		var m := mood(v)
		if m >= SocialDefs.QUARREL_MOOD_BELOW:
			continue
		var p := _nearest_other(v, SocialDefs.QUARREL_RADIUS, true)
		if p == null:
			continue
		var prob := 1.0 - exp(-quarrel_rate(v, p, m) * SocialDefs.QUARREL_ROLL / _day_seconds())
		if vs._rng().randf() < prob:
			quarrel(v, p)


func _nearest_other(v: Villager, radius: float, no_hero: bool) -> Villager:
	var best: Villager = null
	var bd := radius
	for o: Villager in vs.villagers.values():
		if o == v or not _active(o) or (no_hero and o.is_hero):
			continue
		var d := Vector2(o.pos.x - v.pos.x, o.pos.z - v.pos.z).length()
		if d <= bd:
			bd = d
			best = o
	return best


## Ссора пары: дружба падает, общение страдает, уведомление. Вызывается и напрямую (тесты).
func quarrel(a: Villager, b: Villager) -> void:
	add_friendship(a.id, b.id, -SocialDefs.QUARREL_DROP)
	for x in [a, b]:
		add_need(x, SocialDefs.SOCIAL, -SocialDefs.QUARREL_SOCIAL_LOSS)
		st(x)["quarrel_cd"] = SocialDefs.QUARREL_COOLDOWN_DAYS
	_emit(TOPIC_QUARREL, {"a": a.id, "b": b.id, "a_name": a.display_name, "b_name": b.display_name})


# ---------- уход ----------

func _may_leave(v: Villager) -> bool:
	return v.can_die() and not v.is_hero and not _leaving.has(v.id) and not v.arriving


func is_leaving(id: int) -> bool:
	return _leaving.has(id)


func leave_point(id: int) -> Variant:
	return _leaving[id]["to"] if _leaving.has(id) else null


## Житель решает уйти: идёт к ближайшему краю карты. Герой не уходит. false — отказ.
func start_leave(v: Villager) -> bool:
	if not _may_leave(v):
		return false
	var to = _edge_target(v)
	if to == null:
		_finish_leave(v)
		return true
	vs._drop_load(v)
	v.task = {}
	v.think_cd = 0.0
	v.at_site = false
	_leaving[v.id] = {"to": to, "t": 0.0}
	vs._jobs_dirty = true
	return true


func _edge_target(v: Villager) -> Variant:
	var n := vs.world.size
	var c0 := vs.world.cell_of(v.pos.x, v.pos.z)
	var cands: Array[Vector2i] = [Vector2i(c0.x, 0), Vector2i(c0.x, n - 1), Vector2i(0, c0.y), Vector2i(n - 1, c0.y)]
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a - c0).length() < Vector2(b - c0).length())
	for c in cands:
		for off in range(0, 20):
			for sgn in [1, -1]:
				var cc := c
				if c.x == 0 or c.x == n - 1:
					cc.y = clampi(c.y + off * sgn, 0, n - 1)
				else:
					cc.x = clampi(c.x + off * sgn, 0, n - 1)
				if not vs.pathfinder.is_walkable_cell(cc):
					continue
				var p := vs.world.cell_center(cc.x, cc.y)
				if not vs.pathfinder.find_path(v.pos, p).is_empty():
					return vs._ground(p)
	return null


func _tick_leaving(dt: float) -> void:
	for id in _leaving.keys():
		var v := vs.get_villager(id)
		if v == null:
			_leaving.erase(id)
			continue
		_leaving[id]["t"] = float(_leaving[id]["t"]) + dt
		if float(_leaving[id]["t"]) > SocialDefs.LEAVE_MAX_SECONDS:
			_finish_leave(v)


## Дошёл до края карты (VillagerSystem._work, &"leave"): исчезает, событие и хук соседей.
func _finish_leave(v: Villager) -> void:
	var payload := {"id": v.id, "name": v.display_name, "profession": v.profession, "traits": v.traits.duplicate()}
	_leaving.erase(v.id)
	_st.erase(v.id)
	if not vs.remove_villager(v.id):
		return
	vs.needs.assign_homes()
	if on_villager_left.is_valid():
		on_villager_left.call(payload)
	_emit(TOPIC_LEFT, payload)


func finish_leave(v: Villager) -> void:
	_finish_leave(v)


# ---------- праздники ----------

func holiday_active() -> bool:
	return not holiday.is_empty()


func has_club() -> bool:
	return _first_building(&"club") > 0


func _first_building(type: StringName) -> int:
	var best := 0
	for id in vs.construction.buildings:
		var b: Building = vs.construction.buildings[id]
		if b.is_done() and b.type == type and (best == 0 or id < best):
			best = id
	return best


## Сколько суток до следующего праздника из клуба (0 — можно).
func call_cooldown_days() -> float:
	return _call_cd / _day_seconds()


## Можно ли позвать праздник: &"ok" | &"no_club" | &"active" | &"cooldown" | &"night".
func can_call_holiday() -> StringName:
	if not has_club():
		return &"no_club"
	if holiday_active():
		return &"active"
	if _call_cd > 0.0:
		return &"cooldown"
	if NeedsDefs.is_night(_hour()) or _hour() + SocialDefs.HOLIDAY_HOURS > NeedsDefs.NIGHT_START_HOUR:
		return &"night"
	return &"ok"


## Игрок зовёт праздник из клуба (кулдаун CALL_COOLDOWN_DAYS). Возвращает причину отказа или &"ok".
func call_holiday() -> StringName:
	var r := can_call_holiday()
	if r != &"ok":
		return r
	start_holiday(&"called", true)
	_call_cd = SocialDefs.CALL_COOLDOWN_DAYS * _day_seconds()
	return &"ok"


## Начинает праздник: угощение со складов (мало еды — эффект слабее), все (кроме больных/спящих/уходящих) идут праздновать.
func start_holiday(id: StringName, called: bool = false) -> bool:
	if holiday_active() or not SocialDefs.HOLIDAYS.has(id):
		return false
	var need := ceili(float(vs.population()) * SocialDefs.HOLIDAY_FOOD_PER_VILLAGER)
	var got := _take_food(need)
	holiday = {"id": id, "name": SocialDefs.HOLIDAYS[id][0], "left": SocialDefs.HOLIDAY_HOURS / 24.0 * _day_seconds(),
		"called": called, "feast": got >= need, "attended": {}}
	for v: Villager in vs.villagers.values():
		v.think_cd = 0.0
	vs._jobs_dirty = true
	_emit(TOPIC_HOLIDAY_STARTED, {"id": id, "name": holiday["name"], "called": called, "feast": holiday["feast"]})
	return true


func _take_food(n: int) -> int:
	var left := n
	for s in vs.economy.storages:
		for res in s.contents.keys():
			if left <= 0:
				return n
			if ResourceDefs.category(res) == ResourceDefs.Category.FOOD:
				var k := mini(left, int(s.contents[res]))
				if k > 0:
					s.remove(res, k)
					left -= k
	return n - left


func _tick_holiday(dt: float) -> void:
	if holiday_active():
		holiday["left"] = float(holiday["left"]) - dt
		if float(holiday["left"]) <= 0.0:
			_end_holiday()
		return
	if seasons == null:
		return
	var cur := seasons.season()
	var year := seasons.year()
	var day := seasons.day_of_season()
	var dis := seasons.days_in_season(cur)
	if _hour() < SocialDefs.HOLIDAY_START_HOUR or _hour() >= SocialDefs.HOLIDAY_START_HOUR + SocialDefs.HOLIDAY_HOURS:
		return
	for hid: StringName in SocialDefs.HOLIDAYS:
		var def: Array = SocialDefs.HOLIDAYS[hid]
		if def[1] != cur:
			continue
		var target := dis if int(def[2]) < 0 else (mini(dis, dis / 2 + 1) if int(def[2]) == 0 else int(def[2]))
		var key := "%d:%s" % [year, hid]
		if day >= target and (day == target or int(def[2]) < 0) and key != _last_holiday:
			_last_holiday = key
			start_holiday(hid)
			return


func _end_holiday() -> void:
	var att: Dictionary = holiday.get("attended", {})
	for id in att:
		var v := vs.get_villager(int(id))
		if v != null:
			add_need(v, SocialDefs.HOPE, SocialDefs.HOPE_HOLIDAY)
	var ended := {"id": holiday["id"], "name": holiday["name"]}
	holiday = {}
	for v: Villager in vs.villagers.values():
		v.think_cd = 0.0
	vs._jobs_dirty = true
	_emit(TOPIC_HOLIDAY_ENDED, ended)


## Куда идти на праздник: клуб (id) или центр посёлка (0).
func party_spot() -> Vector3:
	var club := _first_building(&"club")
	if club > 0:
		return vs.construction.get_building(club).position
	return vs.hub_position()


## Своя точка у костра/клуба для жителя (кольцо вокруг центра праздника).
func party_point(v: Villager) -> Vector3:
	var c := party_spot()
	var a := float(v.id) * 2.399963  # золотой угол: жители не сливаются в одну точку
	var r := SocialDefs.PARTY_RADIUS * (0.6 + 0.4 * float(v.id % 3) / 2.0)
	return vs.pathfinder.nearest_walkable(c + Vector3(cos(a) * r, 0.0, sin(a) * r))


# ---------- выбор дела ----------

func _job(kind: StringName, target: int, dest: StringName) -> Dictionary:
	return {"key": "n:%s:%d" % [kind, target], "cat": &"", "kind": kind, "target": target, "dest": dest}


func _count_task(kind: StringName, target: int, except: Villager) -> int:
	var n := 0
	for o: Villager in vs.villagers.values():
		if o != except and o.task.get("kind", &"") == kind and int(o.task.get("target", 0)) == target:
			n += 1
	return n


## Дело для жителя в свободное время ({} — нет). Вызывается NeedsSystem.job_for после телесных нужд.
func job_for(v: Villager, cur: StringName) -> Dictionary:
	if not enabled or v.arriving:
		return {}
	if is_leaving(v.id):
		return _job(&"leave", 0, &"edge")
	if holiday_active():
		return _job(&"party", _first_building(&"club"), &"party")
	var hour := _hour()
	var night := NeedsDefs.is_night(hour)
	var s := st(v)
	var club := _first_building(&"club")
	if club > 0 and hour >= SocialDefs.CLUB_START_HOUR and hour < SocialDefs.CLUB_END_HOUR and v.need(NeedsDefs.REST) > SocialDefs.CLUB_MIN_REST:
		var fun := float(s[SocialDefs.FUN])
		if (fun < SocialDefs.CLUB_GO_BELOW or (cur == &"club" and fun < SocialDefs.CLUB_STAY_UNTIL)) and (cur == &"club" or _count_task(&"club", club, v) < SocialDefs.CLUB_CAPACITY):
			return _job(&"club", club, &"club")
	var bath := _first_building(&"bathhouse")
	if bath > 0 and not night and (cur == &"bath" or (float(s["bath_cd"]) <= 0.0 and (mood(v) < SocialDefs.BATH_MOOD_BELOW or v.need(NeedsDefs.HEALTH) < SocialDefs.BATH_HEALTH_BELOW))):
		if cur == &"bath" or _count_task(&"bath", bath, v) < SocialDefs.BATH_CAPACITY:
			return _job(&"bath", bath, &"bathhouse")
	if not night:
		var soc := float(s[SocialDefs.SOCIAL])
		if soc < SocialDefs.TALK_BELOW or (cur == &"talk" and soc < SocialDefs.TALK_DONE):
			var p := _talk_partner(v, int(v.task.get("target", 0)) if cur == &"talk" else 0)
			if p != null:
				return _job(&"talk", p.id, &"villager")
	return {}


func _talk_partner(v: Villager, keep: int) -> Villager:
	var best: Villager = null
	var bs := -INF
	for o: Villager in vs.villagers.values():
		if o == v or not _active(o) or friendship(v.id, o.id) <= SocialDefs.HOSTILE_AT:
			continue
		if o.task.get("kind", &"") == &"sleep" and o.at_site:
			continue
		var d := Vector2(o.pos.x - v.pos.x, o.pos.z - v.pos.z).length()
		var sc := friendship(v.id, o.id) * 4.0 - d * 0.05 + (2.0 if o.id == keep else 0.0)
		if sc > bs:
			bs = sc
			best = o
	return best


## Баня: завершение посещения (VillagerSystem._work, &"bath").
func finish_bath(v: Villager) -> void:
	v.set_need(NeedsDefs.HEALTH, v.need(NeedsDefs.HEALTH) + SocialDefs.BATH_HEALTH)
	v.set_need(NeedsDefs.WARMTH, v.need(NeedsDefs.WARMTH) + SocialDefs.BATH_WARMTH)
	add_need(v, SocialDefs.FUN, SocialDefs.BATH_FUN)
	st(v)["bath_cd"] = SocialDefs.BATH_COOLDOWN_DAYS


# ---------- описание ----------

func mental_card_lines(v: Villager) -> String:
	var lines: Array[String] = []
	for n in SocialDefs.NEEDS:
		var x := need(v, n)
		lines.append("%s  %s %d%%" % [SocialDefs.NAMES[n], SocialDefs.bar(x), roundi(x * 100.0)])
	return "\n".join(lines)


func friends_text(v: Villager) -> String:
	var parts: Array[String] = []
	for f in friends_of(v):
		var o := vs.get_villager(f[0])
		if o != null:
			parts.append(o.display_name)
	var t := ", ".join(parts) if not parts.is_empty() else "пока нет"
	var en: Array[String] = []
	for id in enemies_of(v):
		var o := vs.get_villager(id)
		if o != null:
			en.append(o.display_name)
	if not en.is_empty():
		t += "\nВ ссоре с: " + ", ".join(en)
	return t


## Блок карточки жителя: настроение, психические нужды, друзья.
func card_text(v: Villager) -> String:
	var t := "Настроение: %s (%d%%)" % [mood_word(v), roundi(mood(v) * 100.0)]
	if is_leaving(v.id):
		t += "\n⚠ собирается уйти из посёлка"
	t += "\n" + mental_card_lines(v) + "\nДрузья: " + friends_text(v)
	return t


func summary_text() -> String:
	var m := settlement_mood()
	var t := "Настроение посёлка: %s (%d%%)" % [SocialDefs.mood_word(m), roundi(m * 100.0)]
	if holiday_active():
		t += " — идёт праздник: " + String(holiday["name"])
	return t


# ---------- сохранение ----------

func get_save_key() -> StringName:
	return &"social"


func save_state() -> Dictionary:
	var v := {}
	for id in _st:
		var e := {}
		for k in _st[id]:
			e[String(k)] = _st[id][k]
		v[str(id)] = e
	var lv := {}
	for id in _leaving:
		var p: Vector3 = _leaving[id]["to"]
		lv[str(id)] = {"to": [p.x, p.y, p.z], "t": _leaving[id]["t"]}
	var hol := {}
	if not holiday.is_empty():
		var att := []
		for id in holiday["attended"]:
			att.append(id)
		hol = {"id": String(holiday["id"]), "name": holiday["name"], "left": holiday["left"], "called": holiday["called"], "feast": holiday["feast"], "attended": att}
	return {"villagers": v, "friends": _friends.duplicate(), "leaving": lv, "holiday": hol,
		"last_holiday": _last_holiday, "call_cd": _call_cd}


func load_state(d: Dictionary) -> void:
	_st.clear()
	_friends.clear()
	_leaving.clear()
	holiday = {}
	if d.get("villagers") is Dictionary:
		for k in d["villagers"]:
			var id := SaveManager.to_int(k, 0)
			var e: Dictionary = d["villagers"][k]
			if id <= 0:
				continue
			var s := {}
			for n in SocialDefs.NEEDS:
				s[n] = clampf(float(e.get(String(n), SocialDefs.START[n])), 0.0, 1.0)
			for f in ["idle", "misery", "bath_cd", "quarrel_cd"]:
				s[f] = maxf(0.0, float(e.get(f, 0.0)))
			_st[id] = s
	if d.get("friends") is Dictionary:
		for k in d["friends"]:
			_friends[String(k)] = clampf(float(d["friends"][k]), -1.0, 1.0)
	if d.get("leaving") is Dictionary:
		for k in d["leaving"]:
			var e: Dictionary = d["leaving"][k]
			var p = e.get("to")
			if p is Array and p.size() == 3:
				_leaving[SaveManager.to_int(k, 0)] = {"to": Vector3(float(p[0]), float(p[1]), float(p[2])), "t": float(e.get("t", 0.0))}
	if d.get("holiday") is Dictionary and not (d["holiday"] as Dictionary).is_empty():
		var h: Dictionary = d["holiday"]
		var hid := StringName(String(h.get("id", "")))
		if SocialDefs.HOLIDAYS.has(hid):
			var att := {}
			if h.get("attended") is Array:
				for a in h["attended"]:
					att[SaveManager.to_int(a, 0)] = true
			holiday = {"id": hid, "name": String(h.get("name", "")), "left": float(h.get("left", 0.0)),
				"called": bool(h.get("called", false)), "feast": bool(h.get("feast", true)), "attended": att}
	_last_holiday = String(d.get("last_holiday", ""))
	_call_cd = maxf(0.0, float(d.get("call_cd", 0.0)))
