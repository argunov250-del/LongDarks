class_name HouseholdSystem
extends RefCounted
## Домашнее хозяйство (шаг 10b): у каждого жилья — своя печь, поленница, запас воды
## и еды, огород; сарай (куры+корова) строит игрок; у столовой — запас еды и воды.
## Принадлежит VillagerSystem (vs.household): тикается и сохраняется вместе с ним.
## Запасы создаются по готовому жилью/столовой лениво (sync) и сохраняются при улучшении
## дома (id здания не меняется).
##
## API шага 11 (еда/отопление): house_has_food(id), canteen_for(villager),
## stove_demand(id) (хук отопления: heating_needed), HouseholdDefs.garden_season_allows (хук сезонов).

const TOPIC_CHANGED := &"household_changed"

var construction: ConstructionSystem
var economy: EconomySystem
var homes: Dictionary = {}      # int id здания -> Household (жильё)
var canteens: Dictionary = {}   # int id здания -> Household (столовые)
## ХУК ОТОПЛЕНИЯ: true — дому нужны дрова в печи (до её вместимости). Расход — шаг 11.
var heating_needed: bool = true

var _sim: Simulation


func _init(construction_in: ConstructionSystem, economy_in: EconomySystem) -> void:
	construction = construction_in
	economy = economy_in


# ---------- реестр ----------

## Создаёт запасы для готового жилья/столовых, удаляет для исчезнувших зданий.
func sync() -> void:
	for id in homes.keys():
		if construction.get_building(id) == null:
			homes.erase(id)
	for id in canteens.keys():
		if construction.get_building(id) == null:
			canteens.erase(id)
	for id in construction.buildings:
		var b: Building = construction.buildings[id]
		if not b.is_done():
			continue
		if BuildingDefs.is_housing(b.type) and not homes.has(id):
			homes[id] = Household.new(id, &"house")
		elif BuildingDefs.is_canteen(b.type) and not canteens.has(id):
			canteens[id] = Household.new(id, &"canteen")


## Запас жилья (null — не жильё или ещё не построено).
func home(id: int) -> Household:
	if not homes.has(id):
		sync()
	return homes.get(id)


func canteen(id: int) -> Household:
	if not canteens.has(id):
		sync()
	return canteens.get(id)


## Запас жилья или столовой.
func stock_of(id: int) -> Household:
	var h := home(id)
	return h if h != null else canteen(id)


func home_ids() -> Array[int]:
	var out: Array[int] = []
	for id in homes:
		out.append(id)
	out.sort()
	return out


func canteen_ids() -> Array[int]:
	var out: Array[int] = []
	for id in canteens:
		out.append(id)
	out.sort()
	return out


# ---------- дрова: печь и поленница ----------

func woodpile_capacity(id: int) -> int:
	var b := construction.get_building(id)
	return BuildingDefs.firewood_capacity(b.type) if b != null else 0


func stove_capacity(id: int) -> int:
	var b := construction.get_building(id)
	return BuildingDefs.stove_capacity(b.type) if b != null else 0


func wants_heat(_id: int) -> bool:
	return heating_needed  # шаг 11: по температуре дома/сезону


## Сколько дров дом хочет в печь сейчас (0 — тепло не нужно или печь полна).
func stove_demand(id: int) -> int:
	var h := home(id)
	if h == null or not wants_heat(id):
		return 0
	return maxi(0, stove_capacity(id) - h.stove)


func woodpile_room(id: int) -> int:
	var h := home(id)
	return maxi(0, woodpile_capacity(id) - h.woodpile) if h != null else 0


## Сколько дров дому ещё нужно всего (печь по спросу + поленница).
func wood_room(id: int) -> int:
	return stove_demand(id) + woodpile_room(id)


## Кладёт дрова: в печь (если нужно тепло) и на поленницу; возвращает принятое.
func add_firewood(id: int, n: int, to_stove: bool) -> int:
	var h := home(id)
	if h == null or n <= 0:
		return 0
	var left := n
	if to_stove:
		var s := mini(left, stove_demand(id))
		h.stove += s
		left -= s
	var w := mini(left, woodpile_room(id))
	h.woodpile += w
	left -= w
	if left > 0 and not to_stove:
		var s2 := mini(left, stove_demand(id))
		h.stove += s2
		left -= s2
	return n - left


# ---------- вода и еда ----------

func water_room(id: int) -> int:
	var h := stock_of(id)
	return maxi(0, h.water_cap - h.water) if h != null else 0


func add_water(id: int, n: int) -> int:
	var h := stock_of(id)
	if h == null or n <= 0:
		return 0
	var moved := mini(n, water_room(id))
	h.water += moved
	return moved


## Колодец, из которого можно набрать воду: ближайший готовый (id здания) или -1.
func nearest_well(from: Vector3) -> int:
	var best := -1
	var bd := INF
	for id in construction.buildings:
		var b: Building = construction.buildings[id]
		if b.is_done() and BuildingDefs.is_well(b.type):
			var d := Vector2(b.position.x - from.x, b.position.z - from.z).length()
			if d < bd:
				bd = d
				best = id
	return best


func add_food(id: int, res: StringName, n: int) -> int:
	var h := stock_of(id)
	if h == null or ResourceDefs.category(res) != ResourceDefs.Category.FOOD:
		return 0
	return h.food.add(res, n)


## В доме есть еда (шаг 11: житель без еды дома идёт в столовую).
func house_has_food(id: int) -> bool:
	var h := home(id)
	return h != null and h.food.used() > 0


## Ближайшая готовая столовая, где есть еда (id здания), иначе -1. Для житель-логики шага 11.
func canteen_for(v: Villager) -> int:
	sync()
	var best := -1
	var bd := INF
	for id in canteens:
		var h: Household = canteens[id]
		var b := construction.get_building(id)
		if b == null or not b.is_done() or h.food.used() <= 0:
			continue
		var d := Vector2(b.position.x - v.pos.x, b.position.z - v.pos.z).length()
		if d < bd:
			bd = d
			best = id
	return best


# ---------- огород ----------

func can_plant(id: int, day: int = 0) -> bool:
	var h := home(id)
	return h != null and h.garden_state == Household.GARDEN_EMPTY and HouseholdDefs.garden_season_allows(day, &"plant")


func can_harvest(id: int, day: int = 0) -> bool:
	var h := home(id)
	return h != null and h.garden_state == Household.GARDEN_RIPE and HouseholdDefs.garden_season_allows(day, &"harvest") and h.food.free_space() > 0


func plant(id: int) -> bool:
	var h := home(id)
	if h == null or h.garden_state != Household.GARDEN_EMPTY:
		return false
	h.garden_state = Household.GARDEN_GROWING
	h.garden_progress = 0.0
	return true


## Снимает урожай (грядка пустеет); возвращает {"res", "n"} для корзины или {}.
func harvest(id: int) -> Dictionary:
	var h := home(id)
	if h == null or h.garden_state != Household.GARDEN_RIPE:
		return {}
	var crop := h.garden_crop
	h.garden_state = Household.GARDEN_EMPTY
	h.garden_progress = 0.0
	var i := HouseholdDefs.GARDEN_CROPS.find(crop)
	h.garden_crop = HouseholdDefs.GARDEN_CROPS[(i + 1) % HouseholdDefs.GARDEN_CROPS.size()]
	return {"res": crop, "n": HouseholdDefs.GARDEN_YIELD}


# ---------- сарай ----------

func can_build_barn(id: int) -> bool:
	var h := home(id)
	return h != null and not h.barn and economy.can_afford(HouseholdDefs.BARN_COST)


## Игрок строит сарай (куры и корова) во дворе: цена сразу, постройка мгновенная (плейсхолдер).
func build_barn(id: int) -> bool:
	if not can_build_barn(id):
		return false
	economy.consume(HouseholdDefs.BARN_COST)
	home(id).barn = true
	_changed()
	return true


# ---------- места во дворе (мировые координаты) ----------

func world_point(b: Building, local: Vector2) -> Vector3:
	var p := Footprint.local_to_world(b.xz(), b.rot, local)
	return Vector3(p.x, construction.world.height_at(p.x, p.y), p.y)


func yard_spot(b: Building, yard_local: Vector2) -> Vector3:
	return world_point(b, BuildingDefs.YARD_OFFSET + yard_local)


func woodpile_pos(b: Building) -> Vector3:
	return yard_spot(b, HouseholdDefs.WOODPILE_STAND)


func chop_pos(b: Building) -> Vector3:
	return yard_spot(b, HouseholdDefs.CHOP_STAND)


func garden_pos(b: Building) -> Vector3:
	return yard_spot(b, HouseholdDefs.GARDEN_STAND)


func door_pos(b: Building) -> Vector3:
	return world_point(b, HouseholdDefs.DOOR_LOCAL)


# ---------- тик ----------

func tick(sim: Simulation, dt: float) -> void:
	_sim = sim
	if dt <= 0.0:
		return
	sync()
	var day := sim.clock.get_day()
	var days := dt / (float(sim.clock.day_length_usec) / GameClock.USEC)
	for id in homes:
		var h: Household = homes[id]
		if h.garden_state == Household.GARDEN_GROWING and HouseholdDefs.garden_season_allows(day, &"grow"):
			h.garden_progress += dt
			if h.garden_progress >= HouseholdDefs.GARDEN_GROW_TIME:
				h.garden_state = Household.GARDEN_RIPE
		if h.barn:
			h.egg_acc = minf(h.egg_acc + dt, HouseholdDefs.EGG_PERIOD)
			h.milk_acc = minf(h.milk_acc + dt, HouseholdDefs.MILK_PERIOD)
			if h.egg_acc >= HouseholdDefs.EGG_PERIOD and h.food.add(&"eggs", 1) > 0:
				h.egg_acc -= HouseholdDefs.EGG_PERIOD
			if h.milk_acc >= HouseholdDefs.MILK_PERIOD and h.food.add(&"milk", 1) > 0:
				h.milk_acc -= HouseholdDefs.MILK_PERIOD
		h.food.spoil(days)
	for id in canteens:
		(canteens[id] as Household).food.spoil(days)


func _changed() -> void:
	if _sim != null:
		_sim.bus.emit(TOPIC_CHANGED, {})


# ---------- сохранение ----------

func save_state() -> Dictionary:
	var hs := []
	for id in home_ids():
		hs.append((homes[id] as Household).to_dict())
	var cs := []
	for id in canteen_ids():
		cs.append((canteens[id] as Household).to_dict())
	return {"homes": hs, "canteens": cs, "heating_needed": heating_needed}


func load_state(d: Dictionary) -> void:
	homes.clear()
	canteens.clear()
	heating_needed = bool(d.get("heating_needed", true))
	if d.get("homes") is Array:
		for e in d["homes"]:
			if e is Dictionary:
				var h := Household.from_dict(e)
				if h.id > 0:
					homes[h.id] = h
	if d.get("canteens") is Array:
		for e in d["canteens"]:
			if e is Dictionary:
				var h := Household.from_dict(e)
				if h.id > 0:
					h.kind = &"canteen"
					canteens[h.id] = h
