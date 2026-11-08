class_name HouseholdSystem
extends RefCounted
## Домашнее хозяйство (шаг 10b): у каждого жилья — своя печь, поленница, запас воды
## и еды, огород; сарай (куры+корова) строит игрок; у столовой — запас еды и воды.
## Принадлежит VillagerSystem (vs.household): тикается и сохраняется вместе с ним.
## Запасы создаются по готовому жилью/столовой лениво (sync) и сохраняются при улучшении
## дома (id здания не меняется).
##
## Шаг 11: отопление (печь жжёт дрова, тепло дома), хуки outdoor_cold/consumption_multiplier.
## API (еда/отопление): house_has_food(id), canteen_for(villager),
## stove_demand(id) (heating_needed выставляет SeasonSystem: печи топят при <= +5 °C),
## HouseholdDefs.garden_season_allows (календарь огорода по сезону).

const TOPIC_CHANGED := &"household_changed"

var construction: ConstructionSystem
var economy: EconomySystem
var homes: Dictionary = {}      # int id здания -> Household (жильё)
var canteens: Dictionary = {}   # int id здания -> Household (столовые)
## ХУК ОТОПЛЕНИЯ: true — дому нужны дрова в печи (до её вместимости).
var heating_needed: bool = true
## ХУКИ СЕЗОНОВ/ПОГОДЫ (шаг 11): холод снаружи 0..1 и общий множитель расхода (еда, тепло, дрова).
var outdoor_cold: float = NeedsDefs.DEFAULT_OUTDOOR_COLD
var consumption_multiplier: float = 1.0
## Отопление и расход дров идут (тесты старых шагов отключают).
var simulate_heat: bool = true
## Календарь (шаг 13): null — сезонов нет, огород без ограничений (старые тесты).
var seasons: SeasonSystem = null
## ХУКИ ПОГОДЫ (WeatherSystem, шаг 14). weather — источник плодородия (null — нет).
var weather: WeatherSystem = null
var garden_growth_multiplier: float = 1.0   # рост огорода (дождь > 1, засуха 0)
var garden_dry_rate: float = 0.0            # убыль прогресса неполитой грядки (доля скорости роста)
var well_work_multiplier: float = 1.0       # во сколько раз дольше наполнение вёдер (засуха)
var water_decay_multiplier: float = 1.0     # убыль воды у жителей (жара)
var shelter_required: bool = false          # жители идут домой (метель, ураган, гроза)
var exposure_warmth_mult: float = 1.0       # тепло на улице убывает быстрее
var exposure_health_drain: float = 0.0      # здоровье/сутки у застигнутых на улице

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
		if BuildingDefs.is_barn(b.type) and homes.has(b.host_id):
			homes[b.host_id].barn = true
		if BuildingDefs.is_housing(b.type) and not homes.has(id):
			homes[id] = Household.new(id, &"house")
			homes[id].warmth = NeedsDefs.unheated_warmth(b.type, outdoor_cold)
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
	return heating_needed and outdoor_cold >= NeedsDefs.HEAT_MIN_COLD


## Расход дров в сутки на печь (мороз и общий множитель увеличивают).
func fuel_per_day() -> float:
	return NeedsDefs.BURN_LOGS_PER_DAY * NeedsDefs.cold_factor(&"fuel", outdoor_cold) * consumption_multiplier


func house_warmth(id: int) -> float:
	var h := home(id)
	return h.warmth if h != null else NeedsDefs.outdoor_warmth(outdoor_cold)


func stove_lit(id: int) -> bool:
	var h := home(id)
	return h != null and h.lit()


## Столовая с водой ближайшая к жителю (id здания) или -1.
func canteen_with_water(v: Villager) -> int:
	sync()
	var best := -1
	var bd := INF
	for id in canteens:
		var h: Household = canteens[id]
		var b := construction.get_building(id)
		if b == null or not b.is_done() or h.water <= 0:
			continue
		var d := Vector2(b.position.x - v.pos.x, b.position.z - v.pos.z).length()
		if d < bd:
			bd = d
			best = id
	return best


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


func add_water(id: int, n: int, bad: bool = false) -> int:
	var h := stock_of(id)
	if h == null or n <= 0:
		return 0
	var moved := mini(n, water_room(id))
	h.water += moved
	if bad and moved > 0:
		h.water_bad = true
	return moved


## Колодец, из которого можно набрать воду: ближайший готовый (id здания) или -1.
func nearest_well(from: Vector3) -> int:
	var best := -1
	var bd := INF
	for id in construction.buildings:
		var b: Building = construction.buildings[id]
		if b.operational() and BuildingDefs.is_well(b.type):
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

## Текущий сезон для огорода (&"" — календаря нет).
func current_season() -> StringName:
	return seasons.season() if seasons != null else &""


## Step 17 (design/gdd/land-restoration.md): set by Main/tests; null — no poison rules.
var restoration: RestorationSystem


## The garden cell lies on poisoned land: nothing grows («земля отравлена»).
func garden_poisoned(id: int) -> bool:
	var b := construction.get_building(id)
	if restoration == null or b == null:
		return false
	var p := garden_pos(b)
	return restoration.is_poisoned(construction.world.cell_of(p.x, p.z))


## The well stands in poison: its water is bad.
func well_bad(well_id: int) -> bool:
	var b := construction.get_building(well_id)
	return restoration != null and b != null and restoration.water_bad_at(b.position)


func can_plant(id: int, _day: int = 0) -> bool:
	var h := home(id)
	return h != null and not garden_poisoned(id) and h.garden_state == Household.GARDEN_EMPTY and HouseholdDefs.garden_season_allows(current_season(), &"plant")


func can_harvest(id: int, _day: int = 0) -> bool:
	var h := home(id)
	return h != null and h.garden_state == Household.GARDEN_RIPE and HouseholdDefs.garden_season_allows(current_season(), &"harvest") and h.food.free_space() > 0


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
	return {"res": crop, "n": garden_yield(id)}


## Урожай за цикл: GARDEN_YIELD * (1 + плодородие клетки огорода) (выгоревший лес удобряет почву).
func garden_yield(id: int) -> int:
	var b := construction.get_building(id)
	if weather == null or b == null:
		return HouseholdDefs.GARDEN_YIELD
	var p := garden_pos(b)
	var f := weather.fertility_at(construction.world.cell_of(p.x, p.z))
	return roundi(float(HouseholdDefs.GARDEN_YIELD) * (1.0 + f * WeatherDefs.GARDEN_YIELD_FERTILITY))


# ---------- сарай ----------

func can_build_barn(id: int) -> bool:
	var h := home(id)
	return h != null and not h.barn and construction.barn_of(id) == null


## Игрок заказывает сарай: на дворе закладывается обычная стройка (этапы, ресурсы, жители).
## Куры и корова начинают давать продукцию, только когда сарай достроен (sync ставит barn).
func build_barn(id: int) -> bool:
	if not can_build_barn(id):
		return false
	return construction.place_barn(id) > 0


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
	var season := current_season()
	var days := dt / sim.clock.day_seconds()
	var cold_store := economy != null and economy.ambient_cold  # на холоде еда не портится
	for id in homes:
		var h: Household = homes[id]
		if h.garden_state == Household.GARDEN_GROWING and HouseholdDefs.garden_season_allows(season, &"grow"):
			h.garden_progress = maxf(0.0, h.garden_progress + dt * (garden_growth_multiplier - garden_dry_rate))
			if h.garden_progress >= HouseholdDefs.GARDEN_GROW_TIME:
				h.garden_state = Household.GARDEN_RIPE
		if h.barn:
			h.egg_acc = minf(h.egg_acc + dt, HouseholdDefs.EGG_PERIOD)
			h.milk_acc = minf(h.milk_acc + dt, HouseholdDefs.MILK_PERIOD)
			if h.egg_acc >= HouseholdDefs.EGG_PERIOD and h.food.add(&"eggs", 1) > 0:
				h.egg_acc -= HouseholdDefs.EGG_PERIOD
			if h.milk_acc >= HouseholdDefs.MILK_PERIOD and h.food.add(&"milk", 1) > 0:
				h.milk_acc -= HouseholdDefs.MILK_PERIOD
			h.manure_acc = minf(h.manure_acc + dt * HouseholdDefs.COWS, FuelDefs.MANURE_PERIOD)
			if h.manure_acc >= FuelDefs.MANURE_PERIOD and economy != null and economy.deposit(&"manure", 1) > 0:
				h.manure_acc -= FuelDefs.MANURE_PERIOD
		if not cold_store:
			var lost := h.food.spoil(days)
			if economy != null and not lost.is_empty():
				economy.note_spoiled(lost)
		if simulate_heat:
			_tick_heat(id, h, days)
	if not cold_store:
		for id in canteens:
			var clost := (canteens[id] as Household).food.spoil(days)
			if economy != null and not clost.is_empty():
				economy.note_spoiled(clost)


## Печь жжёт дрова из своего запаса, дом греется к цели или остывает.
func _tick_heat(id: int, h: Household, days: float) -> void:
	var b := construction.get_building(id)
	if b == null:
		return
	if h.burn_left <= 0.0 and h.stove > 0 and wants_heat(id):
		h.stove -= 1
		h.burn_left = 1.0
	if h.burn_left > 0.0:
		h.burn_left = maxf(0.0, h.burn_left - fuel_per_day() * days)
	var target := NeedsDefs.unheated_warmth(b.type, outdoor_cold)
	if h.lit():
		target = minf(1.0, target + NeedsDefs.STOVE_HEAT)
	var rate := NeedsDefs.HOUSE_HEAT_PER_DAY if target > h.warmth else NeedsDefs.HOUSE_COOL_PER_DAY
	h.warmth = move_toward(h.warmth, target, rate * days)


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
	return {"homes": hs, "canteens": cs, "heating_needed": heating_needed,
		"outdoor_cold": outdoor_cold, "consumption_multiplier": consumption_multiplier}


func load_state(d: Dictionary) -> void:
	homes.clear()
	canteens.clear()
	heating_needed = bool(d.get("heating_needed", true))
	outdoor_cold = clampf(float(d.get("outdoor_cold", NeedsDefs.DEFAULT_OUTDOOR_COLD)), 0.0, 1.0)
	consumption_multiplier = maxf(0.0, float(d.get("consumption_multiplier", 1.0)))
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
