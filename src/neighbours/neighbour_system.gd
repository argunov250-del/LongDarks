class_name NeighbourSystem
extends SimSystem
## Соседнее поселение (шаг 24), design/gdd/neighbours.md: собственный ИИ соседа (абстрактная симуляция),
## отношения, торговля и караваны, взаимопомощь, переселение людей, кражи и налёты, оборона и дипломатия.
## Баланс — NeighbourDefs. Ключ сохранения &"neighbours". Детерминирован по seed (собственный RNG).

const TOPIC_CARAVAN := &"neighbour_caravan"        # {nid, name, goods, vehicle}
const TOPIC_REQUEST := &"neighbour_request"        # {nid, name, res, n}
const TOPIC_THEFT := &"neighbour_theft"            # {nid, name, res, n, repelled}
const TOPIC_RAID := &"neighbour_raid"              # {nid, name, repelled, loot, hurt}
const TOPIC_RAID_SEEN := &"neighbour_raid_seen"    # {nid, name}
const TOPIC_MIGRATE := &"neighbour_migrate"        # {dir: &"to_them"|&"to_us", name, nid}
const TOPIC_PACT_BROKEN := &"neighbour_pact_broken"  # {nid, name}
const TOPIC_CHANGED := &"neighbours_changed"

var vs: VillagerSystem
var economy: EconomySystem
var construction: ConstructionSystem
var seasons: SeasonSystem
var social: SocialSystem
var vehicles: VehicleSystem
var world: WorldMap
var enabled := true
var neighbours: Array = []     # Array of Dictionary (состояние соседей)
var parties: Array = []        # идущие отряды: караваны, торговцы, помощь, налётчики
var attract_override := -1.0   # тесты: >= 0 подменяет привлекательность посёлка
var rng := RandomNumberGenerator.new()

var _sim: Simulation
var _acc_days := 0.0
var _next_party := 1
var _weather_events := 0
var _season_override: StringName = &""


func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value
	for d in NeighbourDefs.START:
		neighbours.append(_make(d))


func _make(d: Dictionary) -> Dictionary:
	var stock := {}
	for k in d["stock"]:
		stock[k] = float(d["stock"][k])
	return {"id": d["id"], "name": d["name"], "side": int(d["side"]), "along": float(d["along"]),
		"relation": float(d["relation"]), "trend": 0.0, "prev": float(d["relation"]),
		"baseline": float(d["baseline"]), "greed": float(d["greed"]), "aggression": float(d["aggression"]),
		"pop": int(d["pop"]), "level": int(d["level"]), "vehicles": int(d["vehicles"]), "mood": float(d["mood"]),
		"stock": stock, "offers": [], "request": {}, "pact_left": 0.0, "tribute": {},
		"cd_theft": 0.0, "cd_raid": 0.0, "cd_visit": 2.0, "cd_request": 0.0, "cd_offers": 0.0,
		"visit_left": 0.0, "gift_today": 0.0, "grow_acc": 0.0, "thefts": 0, "raids": 0}


func attach(sim: Simulation) -> void:
	_sim = sim
	sim.bus.subscribe(WeatherSystem.TOPIC_STARTED, func(_p: Dictionary) -> void: _weather_events += 1)
	sim.bus.subscribe(WeatherSystem.TOPIC_ENDED, func(_p: Dictionary) -> void: _weather_events = maxi(0, _weather_events - 1))


## Связывает с миром; перехватывает уход жителей (SocialSystem.on_villager_left).
func bind(vs_in: VillagerSystem, economy_in: EconomySystem, construction_in: ConstructionSystem, seasons_in: SeasonSystem,
		social_in: SocialSystem, vehicles_in: VehicleSystem, world_in: WorldMap) -> void:
	vs = vs_in
	economy = economy_in
	construction = construction_in
	seasons = seasons_in
	social = social_in
	vehicles = vehicles_in
	world = world_in
	if social != null:
		social.on_villager_left = Callable(self, "on_player_villager_left")
	for n in neighbours:
		refresh_offers(n)


func _emit(topic: StringName, payload: Dictionary) -> void:
	if _sim != null:
		_sim.bus.emit(topic, payload)


func _day_seconds() -> float:
	return _sim.clock.day_seconds() if _sim != null else GameClock.DEFAULT_DAY_LENGTH


func get_neighbour(nid: StringName) -> Dictionary:
	for n in neighbours:
		if n["id"] == nid:
			return n
	return {}


func set_season_override(s: StringName) -> void:
	_season_override = s


func season() -> StringName:
	if _season_override != &"":
		return _season_override
	return seasons.season() if seasons != null else SeasonDefs.AUTUMN


# ---------- позиции ----------

func camp_pos(n: Dictionary) -> Vector3:
	var w := world.get_world_size() if world != null else 200.0
	var m := 8.0
	var a := float(n["along"]) * w
	var p := Vector3(a, 0.0, m)
	match int(n["side"]):
		1: p = Vector3(a, 0.0, w - m)
		2: p = Vector3(m, 0.0, a)
		3: p = Vector3(w - m, 0.0, a)
	if world != null:
		p.y = world.height_at(p.x, p.z)
	return p


func hub() -> Vector3:
	return vs.hub_position() if vs != null else Vector3.ZERO


# ---------- ИИ соседа ----------

func food_total(n: Dictionary) -> float:
	var s: Dictionary = n["stock"]
	return float(s.get(&"potato", 0.0)) + float(s.get(&"fish", 0.0)) + float(s.get(&"grain", 0.0))


func food_days(n: Dictionary) -> float:
	return food_total(n) / maxf(0.1, float(n["pop"]) * NeighbourDefs.FOOD_EAT)


## Нужда соседа в ресурсе 0..1 (food — вся еда; firewood — по сезону; spare_parts — по числу людей).
func need_of(n: Dictionary, res: StringName) -> float:
	var s: Dictionary = n["stock"]
	var pop := float(n["pop"])
	match res:
		&"potato", &"fish", &"grain", &"food":
			return clampf(1.0 - food_days(n) / NeighbourDefs.FOOD_SAFE_DAYS, 0.0, 1.0)
		&"firewood":
			var burn := float(NeighbourDefs.WOOD_BURN.get(season(), 0.0))
			if burn <= 0.0:
				return 0.0
			return clampf(1.0 - float(s.get(&"firewood", 0.0)) / maxf(1.0, pop * burn * NeighbourDefs.FOOD_SAFE_DAYS), 0.0, 1.0)
		&"spare_parts":
			return clampf(1.0 - float(s.get(&"spare_parts", 0.0)) / maxf(1.0, pop * 0.5), 0.0, 1.0)
	return 0.0


## Шаг ИИ на заданное число игровых суток (≤ 1 за вызов — вызывающий дробит).
func step_days(days: float) -> void:
	for n in neighbours:
		_econ_day(n, days)
		_social_day(n, days)
	_emit(TOPIC_CHANGED, {})


func _prod_mult() -> float:
	var m := float(NeighbourDefs.SEASON_FARM.get(season(), 1.0))
	return m * (NeighbourDefs.WEATHER_PROD_MULT if _weather_events > 0 else 1.0)


func _econ_day(n: Dictionary, d: float) -> void:
	var s: Dictionary = n["stock"]
	var pop := float(n["pop"])
	if pop <= 0.0:
		return
	var lvl := 1.0 + NeighbourDefs.LEVEL_MULT * float(int(n["level"]) - 1)
	var wm := NeighbourDefs.WEATHER_PROD_MULT if _weather_events > 0 else 1.0
	_add(s, &"potato", pop * NeighbourDefs.FARM_PER_POP * lvl * float(NeighbourDefs.SEASON_FARM.get(season(), 1.0)) * wm * d)
	_add(s, &"fish", pop * NeighbourDefs.FISH_PER_POP * wm * d)
	_add(s, &"firewood", pop * NeighbourDefs.WOOD_PER_POP * lvl * wm * d)
	_add(s, &"logs", pop * NeighbourDefs.LOGS_PER_POP * lvl * wm * d)
	_add(s, &"planks", pop * NeighbourDefs.PLANKS_PER_POP * lvl * wm * d)
	_add(s, &"spare_parts", pop * NeighbourDefs.PARTS_PER_POP_LEVEL * float(n["level"]) * wm * d)
	_add(s, &"scrap_metal", pop * NeighbourDefs.SCRAP_PER_POP * wm * d)
	# потребление
	var eat := pop * NeighbourDefs.FOOD_EAT * d
	for k in [&"potato", &"fish", &"grain"]:
		var have := float(s.get(k, 0.0))
		var take := minf(have, eat)
		s[k] = have - take
		eat -= take
	var starving := eat > 0.001
	var burn := float(NeighbourDefs.WOOD_BURN.get(season(), 0.0)) * pop * d
	var wood := float(s.get(&"firewood", 0.0))
	var cold := burn > wood
	s[&"firewood"] = maxf(0.0, wood - burn)
	# настроение
	var target := 0.4 + 0.4 * clampf(food_days(n) / NeighbourDefs.FOOD_SAFE_DAYS, 0.0, 1.0) + (0.0 if cold else 0.2)
	if starving:
		target = 0.0
	n["mood"] = float(n["mood"]) + (target - float(n["mood"])) * minf(1.0, NeighbourDefs.MOOD_RATE * d)
	# рост и убыль
	var cap := int(n["level"]) * NeighbourDefs.POP_MAX_PER_LEVEL
	if starving and float(n["mood"]) < NeighbourDefs.STARVE_MOOD and int(n["pop"]) > 0 and rng.randf() < NeighbourDefs.STARVE_POP_CHANCE * d:
		n["pop"] = int(n["pop"]) - 1
	elif food_days(n) > NeighbourDefs.GROW_FOOD_DAYS and float(n["mood"]) > NeighbourDefs.GROW_MOOD and int(n["pop"]) < cap:
		n["grow_acc"] = float(n["grow_acc"]) + NeighbourDefs.GROW_PER_DAY * d
		if float(n["grow_acc"]) >= 1.0:
			n["grow_acc"] = float(n["grow_acc"]) - 1.0
			n["pop"] = int(n["pop"]) + 1
	# уровень построек и транспорт
	var lv := int(n["level"])
	if lv < NeighbourDefs.MAX_LEVEL and float(s.get(&"planks", 0.0)) >= NeighbourDefs.LEVEL_PLANKS_COST * lv and int(n["pop"]) >= NeighbourDefs.LEVEL_POP_PER_LEVEL * lv:
		s[&"planks"] = float(s[&"planks"]) - NeighbourDefs.LEVEL_PLANKS_COST * lv
		n["level"] = lv + 1
	if lv >= NeighbourDefs.VEHICLE_MIN_LEVEL and int(n["vehicles"]) < lv - 1 and float(s.get(&"spare_parts", 0.0)) > NeighbourDefs.VEHICLE_PARTS_COST * 2.0:
		s[&"spare_parts"] = float(s[&"spare_parts"]) - NeighbourDefs.VEHICLE_PARTS_COST
		n["vehicles"] = int(n["vehicles"]) + 1
	for k in s.keys():
		s[k] = minf(float(s[k]), NeighbourDefs.STOCK_CAP)


func _add(s: Dictionary, k: StringName, x: float) -> void:
	s[k] = float(s.get(k, 0.0)) + x


func _social_day(n: Dictionary, d: float) -> void:
	for k in ["cd_theft", "cd_raid", "cd_visit", "cd_request", "cd_offers", "visit_left", "gift_today"]:
		n[k] = maxf(0.0, float(n[k]) - (d if k != "gift_today" else d * NeighbourDefs.GIFT_DAILY_CAP))
	# отношения: дрейф к базе личности, ожесточение нуждающегося
	var base := float(n["baseline"])
	if need_of(n, &"food") > NeighbourDefs.DESPERATION_NEED:
		base -= NeighbourDefs.DESPERATION_PULL
	n["relation"] = clampf(float(n["relation"]) + (base - float(n["relation"])) * NeighbourDefs.DRIFT_PER_DAY * d, -1.0, 1.0)
	if rng.randf() < NeighbourDefs.EVENT_CHANCE * d:
		add_relation(n, NeighbourDefs.EVENT_GOOD if rng.randf() < 0.5 + float(n["baseline"]) else -NeighbourDefs.EVENT_BAD * (0.5 + float(n["aggression"])))
	# пакт и дань
	if float(n["pact_left"]) > 0.0:
		n["pact_left"] = float(n["pact_left"]) - d
		if float(n["relation"]) < NeighbourDefs.PACT_BREAK_REL:
			n["pact_left"] = 0.0
			_emit(TOPIC_PACT_BROKEN, {"nid": n["id"], "name": n["name"]})
	_tribute_day(n, d)
	# просьба о помощи
	if not (n["request"] as Dictionary).is_empty():
		n["request"]["left"] = float(n["request"]["left"]) - d
		if float(n["request"]["left"]) <= 0.0:
			add_relation(n, -NeighbourDefs.IGNORE_LOSS)
			n["request"] = {}
			n["cd_request"] = NeighbourDefs.REQUEST_COOLDOWN_DAYS
	elif float(n["cd_request"]) <= 0.0 and int(n["pop"]) > 0:
		_maybe_request(n)
	# торговцы и предложения
	if float(n["cd_offers"]) <= 0.0:
		refresh_offers(n)
	if float(n["cd_visit"]) <= 0.0 and int(n["pop"]) > 0 and float(n["relation"]) >= NeighbourDefs.VISIT_MIN_REL and vs != null:
		n["cd_visit"] = NeighbourDefs.VISIT_PERIOD_DAYS
		_spawn_party(n, &"visit", {}, &"")
	# кражи и налёты
	var host := hostility(n)
	if host > 0.0 and int(n["pop"]) > 0 and economy != null and float(n["pact_left"]) <= 0.0:
		var tf := tribute_factor(n)
		if float(n["cd_theft"]) <= 0.0 and rng.randf() < NeighbourDefs.THEFT_BASE * host * (1.0 + float(n["greed"])) * tf * d:
			resolve_theft(n)
		if float(n["relation"]) < NeighbourDefs.RAID_REL_MAX and float(n["cd_raid"]) <= 0.0 and int(n["pop"]) >= NeighbourDefs.RAID_MIN_POP \
				and rng.randf() < NeighbourDefs.RAID_BASE * host * (0.5 + float(n["aggression"])) * tf * d:
			n["cd_raid"] = NeighbourDefs.RAID_COOLDOWN_DAYS
			_spawn_party(n, &"raid", {}, &"")
			_emit(TOPIC_RAID_SEEN, {"nid": n["id"], "name": n["name"]})
	_migration_day(n, d)
	n["trend"] = float(n["trend"]) * NeighbourDefs.TREND_SMOOTH + (float(n["relation"]) - float(n["prev"])) / maxf(d, 0.001) * (1.0 - NeighbourDefs.TREND_SMOOTH)
	n["prev"] = n["relation"]


func add_relation(n: Dictionary, delta: float) -> void:
	n["relation"] = clampf(float(n["relation"]) + delta, -1.0, 1.0)


func hostility(n: Dictionary) -> float:
	return clampf((-float(n["relation"]) - NeighbourDefs.HOSTILE_FROM) / (1.0 - NeighbourDefs.HOSTILE_FROM), 0.0, 1.0)


func tribute_factor(n: Dictionary) -> float:
	return NeighbourDefs.TRIBUTE_FACTOR if not (n["tribute"] as Dictionary).is_empty() else 1.0


func relation_text(n: Dictionary) -> String:
	var t := float(n["trend"])
	var arrow := "↑" if t > 0.004 else ("↓" if t < -0.004 else "→")
	return "%s %s" % [NeighbourDefs.rel_word(float(n["relation"])), arrow]


# ---------- торговля ----------

## Цена (в ценностях) единицы res, которую сосед ПРОДАЁТ вам: скидка за отношения (и за визит каравана).
func buy_price(n: Dictionary, res: StringName) -> float:
	var disc := NeighbourDefs.REL_DISCOUNT * float(n["relation"]) + (NeighbourDefs.VISIT_DISCOUNT if float(n["visit_left"]) > 0.0 else 0.0)
	return NeighbourDefs.value_of(res) * (1.0 - disc)


## Цена единицы res, которую сосед у вас ПОКУПАЕТ: надбавка за их нужду и за хорошие отношения.
func sell_price(n: Dictionary, res: StringName) -> float:
	return NeighbourDefs.value_of(res) * (1.0 + NeighbourDefs.NEED_PREMIUM * need_of(n, res)) * (1.0 + NeighbourDefs.REL_BONUS * float(n["relation"]))


## Сколько want надо отдать за give_n единиц give.
func quote(n: Dictionary, give: StringName, give_n: int, want: StringName) -> int:
	return maxi(1, int(ceil(buy_price(n, give) * float(give_n) / sell_price(n, want) - 0.0001)))


func refresh_offers(n: Dictionary) -> void:
	n["cd_offers"] = NeighbourDefs.OFFER_REFRESH_DAYS
	var offers: Array = []
	if int(n["pop"]) <= 0:
		n["offers"] = offers
		return
	var wants: Array[StringName] = []
	for r in [&"potato", &"firewood", &"spare_parts"]:
		if need_of(n, r) > 0.2:
			wants.append(r)
	for r in NeighbourDefs.WANT_DEFAULT:
		wants.append(r)
	var s: Dictionary = n["stock"]
	var wi := 0
	for res in NeighbourDefs.TRADE_RES:
		var surplus := float(s.get(res, 0.0)) - float(NeighbourDefs.STOCK_RESERVE.get(res, 0.0))
		if surplus < NeighbourDefs.MIN_LOT:
			continue
		var want: StringName = wants[wi % wants.size()]
		wi += 1
		if want == res:
			continue
		var gn := mini(NeighbourDefs.LOT, int(surplus))
		offers.append({"give": res, "give_n": gn, "want": want, "want_n": quote(n, res, gn, want), "vehicle": &""})
	if int(n["vehicles"]) > 0 and int(n["level"]) >= 2:
		var vt: StringName = &"pickup"
		var val: float = float(NeighbourDefs.VEHICLE_VALUE[vt]) * (1.0 - NeighbourDefs.REL_DISCOUNT * float(n["relation"]))
		offers.append({"give": &"", "give_n": 1, "want": &"spare_parts", "want_n": maxi(1, int(ceil(val / sell_price(n, &"spare_parts")))), "vehicle": vt})
	n["offers"] = offers


## Принять предложение: оплата сразу, товар везёт караван. false — нет у вас оплаты / нет такого предложения.
func accept_offer(nid: StringName, idx: int) -> bool:
	var n := get_neighbour(nid)
	if n.is_empty() or idx < 0 or idx >= (n["offers"] as Array).size() or economy == null:
		return false
	var o: Dictionary = n["offers"][idx]
	if not economy.consume({o["want"]: int(o["want_n"])}):
		return false
	var s: Dictionary = n["stock"]
	var goods := {}
	if o["vehicle"] != &"":
		n["vehicles"] = maxi(0, int(n["vehicles"]) - 1)
	else:
		var gn := mini(int(o["give_n"]), int(float(s.get(o["give"], 0.0))))
		s[o["give"]] = float(s.get(o["give"], 0.0)) - gn
		goods[o["give"]] = gn
	s[o["want"]] = float(s.get(o["want"], 0.0)) + int(o["want_n"])
	(n["offers"] as Array).remove_at(idx)
	add_relation(n, NeighbourDefs.TRADE_REL_GAIN)
	_spawn_party(n, &"caravan", goods, o["vehicle"])
	_emit(TOPIC_CHANGED, {})
	return true


# ---------- помощь ----------

func _maybe_request(n: Dictionary) -> void:
	var best: StringName = &""
	var bn := NeighbourDefs.REQUEST_NEED
	for r in [&"food", &"firewood", &"spare_parts"]:
		var x := need_of(n, r)
		if x > bn:
			bn = x
			best = r
	if best == &"":
		return
	n["request"] = {"res": best, "n": int(NeighbourDefs.REQUEST_QTY[best]), "left": NeighbourDefs.REQUEST_DAYS}
	_emit(TOPIC_REQUEST, {"nid": n["id"], "name": n["name"], "res": best, "n": n["request"]["n"]})


## Количество ресурса у игрока (food — вся еда).
func player_has(res: StringName) -> int:
	if res == &"food":
		var t := 0
		for r in ResourceDefs.ids_in_category(ResourceDefs.Category.FOOD):
			t += economy.total(r)
		return t
	return economy.total(res)


func _player_take(res: StringName, k: int) -> bool:
	if player_has(res) < k:
		return false
	if res != &"food":
		return economy.consume({res: k})
	var left := k
	for r in ResourceDefs.ids_in_category(ResourceDefs.Category.FOOD):
		var t := mini(economy.total(r), left)
		if t > 0 and economy.consume({r: t}):
			left -= t
		if left <= 0:
			break
	return left <= 0


## Ответ на просьбу соседа. accept: ресурсы уходят караваном, отношения растут; отказ — падают.
func answer_request(nid: StringName, accept: bool) -> bool:
	var n := get_neighbour(nid)
	if n.is_empty() or (n["request"] as Dictionary).is_empty():
		return false
	var rq: Dictionary = n["request"]
	if accept:
		if not _player_take(rq["res"], int(rq["n"])):
			return false
		var res: StringName = &"potato" if rq["res"] == &"food" else rq["res"]
		add_relation(n, NeighbourDefs.HELP_GAIN)
		_spawn_party(n, &"aid", {res: int(rq["n"])}, &"")
	else:
		add_relation(n, -NeighbourDefs.REFUSE_LOSS)
	n["request"] = {}
	n["cd_request"] = NeighbourDefs.REQUEST_COOLDOWN_DAYS
	_emit(TOPIC_CHANGED, {})
	return true


## Просьба игрока к соседу. Возвращает, сколько едет к вам (0 — отказ).
func ask_help(nid: StringName, res: StringName, qty: int) -> int:
	var n := get_neighbour(nid)
	if n.is_empty():
		return 0
	var key: StringName = &"potato" if res == &"food" else res
	var surplus := int(float((n["stock"] as Dictionary).get(key, 0.0)) - float(NeighbourDefs.STOCK_RESERVE.get(key, 0.0)))
	if float(n["relation"]) < NeighbourDefs.ASK_MIN_REL or surplus <= 0 or int(n["pop"]) < NeighbourDefs.NEIGHBOUR_MIN_POP_TO_GIVE:
		add_relation(n, -NeighbourDefs.ASK_DENIED_COST)
		return 0
	var k := mini(qty, surplus)
	n["stock"][key] = float(n["stock"][key]) - k
	add_relation(n, -NeighbourDefs.ASK_COST)
	_spawn_party(n, &"caravan", {key: k}, &"")
	return k


# ---------- дипломатия ----------

func gift(nid: StringName, res: StringName, qty: int) -> bool:
	var n := get_neighbour(nid)
	if n.is_empty() or qty <= 0 or not _player_take(res, qty):
		return false
	var key: StringName = &"potato" if res == &"food" else res
	_add(n["stock"], key, float(qty))
	var val := NeighbourDefs.value_of(key) * float(qty)
	var room := maxf(0.0, NeighbourDefs.GIFT_DAILY_CAP - float(n["gift_today"]))
	var gain := minf(room, val * NeighbourDefs.GIFT_GAIN * (1.0 - maxf(0.0, float(n["relation"]))))
	n["gift_today"] = float(n["gift_today"]) + gain
	add_relation(n, gain)
	_emit(TOPIC_CHANGED, {})
	return true


func can_pact(n: Dictionary) -> bool:
	return float(n["relation"]) >= NeighbourDefs.PACT_MIN_REL and float(n["pact_left"]) <= 0.0 and economy != null and economy.can_afford(NeighbourDefs.PACT_COST)


func propose_pact(nid: StringName) -> bool:
	var n := get_neighbour(nid)
	if n.is_empty() or not can_pact(n) or not economy.consume(NeighbourDefs.PACT_COST):
		return false
	n["pact_left"] = NeighbourDefs.PACT_DAYS
	for r in NeighbourDefs.PACT_COST:
		_add(n["stock"], r, float(NeighbourDefs.PACT_COST[r]))
	_emit(TOPIC_CHANGED, {})
	return true


func set_tribute(nid: StringName, res: StringName, qty: int, period_days: float) -> bool:
	var n := get_neighbour(nid)
	if n.is_empty() or qty <= 0:
		return false
	n["tribute"] = {"res": res, "n": qty, "period": period_days, "left": period_days}
	return true


func cancel_tribute(nid: StringName) -> void:
	var n := get_neighbour(nid)
	if not n.is_empty():
		n["tribute"] = {}


func _tribute_day(n: Dictionary, d: float) -> void:
	var t: Dictionary = n["tribute"]
	if t.is_empty() or economy == null:
		return
	t["left"] = float(t["left"]) - d
	if float(t["left"]) > 0.0:
		return
	if _player_take(t["res"], int(t["n"])):
		_add(n["stock"], &"potato" if t["res"] == &"food" else t["res"], float(t["n"]))
		add_relation(n, NeighbourDefs.TRIBUTE_REL_PER_PAY)
		t["left"] = float(t["period"])
	else:
		n["tribute"] = {}
		add_relation(n, -NeighbourDefs.TRIBUTE_MISS_LOSS)


# ---------- защита, кражи, налёты ----------

func count_done(type: StringName) -> int:
	var c := 0
	if construction == null:
		return 0
	for b in construction.buildings.values():
		if b.type == type and b.is_done():
			c += 1
	return c


func guards_on_duty() -> int:
	if vs == null:
		return 0
	var adults := 0
	for v: Villager in vs.villagers.values():
		if not v.is_minor() and not v.arriving:
			adults += 1
	var pr := clampi(vs.get_priority(TaskDefs.GUARD), 0, NeighbourDefs.GUARD_SHARE.size() - 1)
	var want := int(round(float(adults) * float(NeighbourDefs.GUARD_SHARE[pr])))
	return mini(want, count_done(&"guard_post") * NeighbourDefs.GUARD_SLOTS_PER_POST)


func defense_score() -> float:
	return minf(count_done(&"fence"), NeighbourDefs.FENCE_MAX) * NeighbourDefs.FENCE_DEF \
		+ count_done(&"watchtower") * NeighbourDefs.TOWER_DEF + guards_on_duty() * NeighbourDefs.GUARD_DEF


func raid_power(n: Dictionary) -> float:
	return NeighbourDefs.RAID_POWER_BASE + float(n["pop"]) * NeighbourDefs.RAID_POWER_PER_POP


func repel_chance(power: float) -> float:
	var d := defense_score()
	return d / (d + power) if d + power > 0.0 else 0.0


## Ночная кража (одна ходка). Возвращает вынесенное {res, n} ({} — отражена или нечего брать).
func resolve_theft(n: Dictionary) -> Dictionary:
	n["cd_theft"] = NeighbourDefs.THEFT_COOLDOWN_DAYS
	var repelled := rng.randf() < repel_chance(NeighbourDefs.THEFT_POWER)
	var res: StringName = &""
	var k := 0
	if not repelled:
		var have: Array[StringName] = []
		for r in NeighbourDefs.TRADE_RES:
			if economy.total(r) > 0:
				have.append(r)
		if have.is_empty():
			return {}
		res = have[rng.randi_range(0, have.size() - 1)]
		k = mini(rng.randi_range(NeighbourDefs.THEFT_MIN, NeighbourDefs.THEFT_MAX), economy.total(res))
		if k > 0 and economy.consume({res: k}):
			_add(n["stock"], res, float(k))
	n["thefts"] = int(n["thefts"]) + (0 if repelled else 1)
	_emit(TOPIC_THEFT, {"nid": n["id"], "name": n["name"], "res": res, "n": k, "repelled": repelled})
	return {} if repelled or k <= 0 else {"res": res, "n": k}


## Налёт дошёл до центра. Отражён — уходят ни с чем; иначе уносят долю запасов и ранят жителей.
## Здания не страдают, смертей нет (здоровье не ниже RAID_HURT_FLOOR).
func resolve_raid(n: Dictionary) -> Dictionary:
	var repelled := rng.randf() < repel_chance(raid_power(n))
	var loot := {}
	var hurt: Array[String] = []
	if not repelled:
		for r in NeighbourDefs.TRADE_RES:
			var k := mini(int(float(economy.total(r)) * NeighbourDefs.RAID_LOOT_FRACTION), NeighbourDefs.RAID_LOOT_MAX)
			if k > 0 and economy.consume({r: k}):
				loot[r] = k
				_add(n["stock"], r, float(k))
		var cands: Array = []
		for v: Villager in vs.villagers.values():
			if not v.arriving:
				cands.append(v)
		for _i in NeighbourDefs.RAID_INJURED_MAX:
			if cands.is_empty():
				break
			var v: Villager = cands.pop_at(rng.randi_range(0, cands.size() - 1))
			v.set_need(NeedsDefs.HEALTH, maxf(NeighbourDefs.RAID_HURT_FLOOR, v.need(NeedsDefs.HEALTH) - NeighbourDefs.RAID_HURT))
			hurt.append(v.display_name)
		n["raids"] = int(n["raids"]) + 1
	add_relation(n, NeighbourDefs.RAID_FAIL_REL)
	_emit(TOPIC_RAID, {"nid": n["id"], "name": n["name"], "repelled": repelled, "loot": loot, "hurt": hurt})
	return {"repelled": repelled, "loot": loot, "hurt": hurt}


# ---------- люди ----------

## Хук SocialSystem.on_villager_left: ушедший оседает у лучшего соседа.
func on_player_villager_left(payload: Dictionary) -> void:
	var best := {}
	for n in neighbours:
		if best.is_empty() or float(n["relation"]) > float(best["relation"]):
			best = n
	if best.is_empty():
		return
	best["pop"] = int(best["pop"]) + 1
	add_relation(best, NeighbourDefs.LEFT_REL)
	_emit(TOPIC_MIGRATE, {"dir": &"to_them", "name": payload.get("name", "?"), "nid": best["id"]})


## Привлекательность вашего посёлка 0..1: настроение, еда, свободное жильё.
func attractiveness() -> float:
	if attract_override >= 0.0:
		return attract_override
	if vs == null or economy == null:
		return 0.0
	var mood := social.settlement_mood() if social != null else 0.7
	var pop := maxi(1, vs.population())
	var food := clampf(float(player_has(&"food")) / (float(pop) * NeighbourDefs.ATTRACT_FOOD_PER_POP), 0.0, 1.0)
	var beds := 0
	for id in vs.needs.housing_ids():
		beds += vs.needs.capacity(id)
	var housing := 1.0 if beds > vs.population() else 0.0
	return 0.5 * mood + 0.3 * food + 0.2 * housing


func _migration_day(n: Dictionary, d: float) -> void:
	if vs == null or int(n["pop"]) <= NeighbourDefs.POP_MIN:
		return
	var a := attractiveness()
	if a < NeighbourDefs.ATTRACT_MIN:
		return
	if rng.randf() < NeighbourDefs.ARRIVE_BASE * a * (1.5 - float(n["mood"])) * d:
		var v := vs.spawn_newcomer()
		if v != null:
			n["pop"] = int(n["pop"]) - 1
			_emit(TOPIC_MIGRATE, {"dir": &"to_us", "name": v.display_name, "nid": n["id"]})


# ---------- отряды ----------

func _spawn_party(n: Dictionary, kind: StringName, goods: Dictionary, vehicle: StringName) -> Dictionary:
	var camp := camp_pos(n)
	var h := hub()
	var from := camp
	var to := h
	if kind == &"aid":
		from = h
		to = camp
	var speed := NeighbourDefs.RAID_SPEED if kind == &"raid" else (NeighbourDefs.CARAVAN_SPEED_VEHICLE if vehicle != &"" or int(n["vehicles"]) > 0 and kind != &"aid" else NeighbourDefs.CARAVAN_SPEED)
	var p := {"id": _next_party, "kind": kind, "nid": n["id"], "goods": goods, "vehicle": vehicle, "from": from, "to": to,
		"t": 0.0, "dur": maxf(1.0, from.distance_to(to) / speed), "back": false, "driving": speed == NeighbourDefs.CARAVAN_SPEED_VEHICLE}
	_next_party += 1
	parties.append(p)
	return p


func party_pos(p: Dictionary) -> Vector3:
	var a: Vector3 = p["from"]
	var b: Vector3 = p["to"]
	var t := float(p["t"])
	return b.lerp(a, t) if bool(p["back"]) else a.lerp(b, t)


func tick(_sim_in: Simulation, dt: float) -> void:
	if not enabled:
		return
	_acc_days += dt / _day_seconds()
	while _acc_days >= 1.0:
		_acc_days -= 1.0
		step_days(1.0)
	advance_parties(dt)


func advance_parties(dt: float) -> void:
	for p in parties.duplicate():
		p["t"] = float(p["t"]) + dt / float(p["dur"])
		if float(p["t"]) < 1.0:
			continue
		if bool(p["back"]):
			parties.erase(p)
		else:
			_arrive(p)


func _arrive(p: Dictionary) -> void:
	var n := get_neighbour(p["nid"])
	match p["kind"]:
		&"caravan":
			var lost := {}
			for r in p["goods"]:
				var put := economy.deposit(r, int(p["goods"][r]))
				if put < int(p["goods"][r]):
					lost[r] = int(p["goods"][r]) - put
			if p["vehicle"] != &"" and vehicles != null:
				vehicles.add_vehicle(p["vehicle"], NeighbourDefs.VEHICLE_COND, NeighbourDefs.VEHICLE_FUEL, hub(), &"trade")
			_emit(TOPIC_CARAVAN, {"nid": p["nid"], "name": n.get("name", "?"), "goods": p["goods"], "vehicle": p["vehicle"], "lost": lost})
			parties.erase(p)
		&"visit":
			if not n.is_empty():
				n["visit_left"] = NeighbourDefs.VISIT_STAY_DAYS
				refresh_offers(n)
			_emit(TOPIC_CARAVAN, {"nid": p["nid"], "name": n.get("name", "?"), "goods": {}, "vehicle": &"", "lost": {}})
			parties.erase(p)
		&"aid":
			if not n.is_empty():
				for r in p["goods"]:
					_add(n["stock"], r, float(p["goods"][r]))
			parties.erase(p)
		&"raid":
			if not n.is_empty():
				resolve_raid(n)
			p["back"] = true
			p["t"] = 0.0


# ---------- интерфейс ----------

func summary_text(n: Dictionary) -> String:
	var s: Dictionary = n["stock"]
	return "Население %d, постройки ур. %d, машин %d\nНастроение %d%%, еды на %d дн.\nЗапасы: еда %d, дрова %d, доски %d, запчасти %d" % [
		int(n["pop"]), int(n["level"]), int(n["vehicles"]), roundi(float(n["mood"]) * 100.0), int(food_days(n)),
		int(food_total(n)), int(float(s.get(&"firewood", 0.0))), int(float(s.get(&"planks", 0.0))), int(float(s.get(&"spare_parts", 0.0)))]


func offer_text(o: Dictionary) -> String:
	var give := "Пикап" if o["vehicle"] != &"" else "%d × %s" % [int(o["give_n"]), ResourceDefs.display_name(o["give"])]
	return "%s за %d × %s" % [give, int(o["want_n"]), ResourceDefs.display_name(o["want"])]


# ---------- сохранение ----------

func get_save_key() -> StringName:
	return &"neighbours"


func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _from_v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Vector3.ZERO


func _sd(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d:
		o[String(k)] = d[k]
	return o


func _ds(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d:
		o[StringName(k)] = d[k]
	return o


func save_state() -> Dictionary:
	var ns := []
	for n in neighbours:
		var e := {}
		for k in n:
			match k:
				"id": e[k] = String(n[k])
				"stock": e[k] = _sd(n[k])
				"request": e[k] = _sd(n[k])
				"tribute": e[k] = _sd(n[k])
				"offers":
					var os := []
					for o in n[k]:
						os.append({"give": String(o["give"]), "give_n": o["give_n"], "want": String(o["want"]), "want_n": o["want_n"], "vehicle": String(o["vehicle"])})
					e[k] = os
				_: e[k] = n[k]
		if e["request"].has("res"):
			e["request"]["res"] = String(e["request"]["res"])
		if e["tribute"].has("res"):
			e["tribute"]["res"] = String(e["tribute"]["res"])
		ns.append(e)
	var ps := []
	for p in parties:
		ps.append({"id": p["id"], "kind": String(p["kind"]), "nid": String(p["nid"]), "goods": _sd(p["goods"]), "vehicle": String(p["vehicle"]),
			"from": _v3(p["from"]), "to": _v3(p["to"]), "t": p["t"], "dur": p["dur"], "back": p["back"], "driving": p["driving"]})
	return {"neighbours": ns, "parties": ps, "acc_days": _acc_days, "next_party": _next_party, "weather": _weather_events,
		"rng_seed": str(rng.seed), "rng_state": str(rng.state)}


func load_state(d: Dictionary) -> void:
	_acc_days = float(d.get("acc_days", 0.0))
	_next_party = int(d.get("next_party", 1))
	_weather_events = int(d.get("weather", 0))
	if d.get("neighbours") is Array:
		neighbours.clear()
		for e in d["neighbours"]:
			var n := {}
			for k in e:
				n[k] = e[k]
			n["id"] = StringName(e["id"])
			for ik in ["pop", "level", "vehicles", "side", "thefts", "raids"]:
				n[ik] = int(e[ik])
			n["stock"] = _ds(e["stock"])
			var rq: Dictionary = _ds(e.get("request", {}))
			if rq.has(&"res"):
				rq[&"res"] = StringName(rq[&"res"])
			n["request"] = _str_keys(rq)
			var tr: Dictionary = _ds(e.get("tribute", {}))
			if tr.has(&"res"):
				tr[&"res"] = StringName(tr[&"res"])
			n["tribute"] = _str_keys(tr)
			var os := []
			for o in e.get("offers", []):
				os.append({"give": StringName(o["give"]), "give_n": int(o["give_n"]), "want": StringName(o["want"]), "want_n": int(o["want_n"]), "vehicle": StringName(o["vehicle"])})
			n["offers"] = os
			neighbours.append(n)
	if d.get("parties") is Array:
		parties.clear()
		for e in d["parties"]:
			var goods := {}
			for k in e["goods"]:
				goods[StringName(k)] = int(e["goods"][k])
			parties.append({"id": int(e["id"]), "kind": StringName(e["kind"]), "nid": StringName(e["nid"]), "goods": goods, "vehicle": StringName(e["vehicle"]),
				"from": _from_v3(e["from"]), "to": _from_v3(e["to"]), "t": float(e["t"]), "dur": float(e["dur"]), "back": bool(e["back"]), "driving": bool(e["driving"])})
	if d.has("rng_seed"):
		rng.seed = SaveManager.to_int(d["rng_seed"], rng.seed)
	if d.has("rng_state"):
		rng.state = SaveManager.to_int(d["rng_state"], rng.state)


## Ключи словаря обратно в String (request/tribute используют строковые ключи в коде).
func _str_keys(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d:
		o[String(k)] = d[k]
	return o
