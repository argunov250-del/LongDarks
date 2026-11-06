class_name NeedsDefs
extends RefCounted
## Физические потребности жителей (шаг 11): ВЕСЬ баланс (плейсхолдеры) — одно место.
## Потребность 0..1 (1 — всё хорошо): еда, вода, тепло, отдых, здоровье.
## Скорости заданы «за игровые сутки» (GameClock.day_length_usec, 480 с при 1x). Шаг 13: сутки
## сократились с 1440 до 480 с — расходные скорости пересчитаны (x1/3), чтобы темп в реальном времени
## остался прежним; еда и вода — так, чтобы житель ел и пил примерно раз в игровые сутки.
##
## ХУКИ:
##  - сезоны/погода (шаг 13, SeasonSystem): outdoor_cold из температуры, consumption_multiplier зимой выше;
##  - ссоры/уход к соседям: VillagerSystem.suffering(v) (0..1, сводная «нужда»), событие TOPIC_SICK/TOPIC_DIED;
##  - психика (дружба, семья, надежда, досуг) — отдельным шагом; общая трапеза: HOOK_SHARED_MEAL.

const FOOD := &"food"
const WATER := &"water"
const WARMTH := &"warmth"
const REST := &"rest"
const HEALTH := &"health"
const NEEDS: Array[StringName] = [FOOD, WATER, WARMTH, REST, HEALTH]
## Потребности, которые убывают и восполняются (здоровье — производное).
const BASIC: Array[StringName] = [FOOD, WATER, WARMTH, REST]
const NAMES := {FOOD: "Еда", WATER: "Вода", WARMTH: "Тепло", REST: "Отдых", HEALTH: "Здоровье"}
const WARNING_NAMES := {FOOD: "голоден", WATER: "жажда", WARMTH: "холодно", REST: "устал", HEALTH: "болен"}

## Стартовые значения новичка (приходит уставшим и не сытым).
const NEWCOMER_START := {FOOD: 0.7, WATER: 0.7, WARMTH: 0.6, REST: 0.5, HEALTH: 1.0}
const START_HOUR := 7.0            # новая игра начинается утром

# ---------- жильё ----------
## Сколько жителей в доме по звену цепочки: землянка < изба < каменный дом.
const HOUSING_CAPACITY := {&"dugout": 2, &"izba": 4, &"stone_house": 6}
const HOME_AREA_RADIUS := 3.6      # «дома» — не дальше от двери (двор считается домом), м
const HOME_REACH_RADIUS := 1.6     # подойти к двери, чтобы поесть/лечь, м
const HOME_ASSIGN_INTERVAL := 1.0  # как часто пересматривать расселение, игр. с

# ---------- убыль (за сутки при множителе 1) ----------
const FOOD_DECAY_PER_DAY := 0.6     # ~1 трапеза в сутки (0.45 -> 0.9)
const WATER_DECAY_PER_DAY := 0.75   # пьют чуть чаще, чем едят
const REST_DECAY_WORK := 1.0       # устают на работе (на объекте)
const REST_DECAY_IDLE := 0.6       # в пути и без дела
const SLEEP_DECAY_MULT := 0.5      # во сне еда и вода убывают медленнее
const SLEEP_RESTORE_PER_DAY := 3.0 # сон дома (8 ч ≈ +1.0)
const HOMELESS_REST_MULT := 0.4    # сон без дома восстанавливает хуже
const HOMELESS_WARMTH_PENALTY := 0.1  # без дома теплее некуда: сквозняк и сырость

# ---------- еда и вода ----------
const EAT_BELOW := 0.45            # пора поесть
const DRINK_BELOW := 0.45
const MEAL_FULL := 0.9             # ели/пили до этого уровня
const EAT_UNIT_TIME := 4.0         # игр. с на одну порцию
const DRINK_UNIT_TIME := 2.0
const FOOD_PER_UNIT := 0.3         # сытость от единицы еды (по умолчанию)
const WATER_PER_UNIT := 0.3
## Особая сытость отдельных продуктов (остальные — FOOD_PER_UNIT).
const FOOD_VALUE := {&"meat": 0.5, &"fish": 0.45, &"eggs": 0.35, &"milk": 0.3, &"grain": 0.25, &"rapeseed": 0.2, &"mushrooms": 0.2}
const HOOK_SHARED_MEAL := false    # ХУК (психика): общая трапеза в столовой даст бонус настроения

# ---------- тепло ----------
const DEFAULT_OUTDOOR_COLD := 0.35 # 0 — тепло, 1 — лютый мороз; без календаря (SeasonSystem выставляет сам)
const MILD_COLD := 0.35            # «обычный» холод: выше него растёт расход (зима)
## Дополнительный расход при максимальном морозе (множитель = 1 + extra * доля превышения MILD_COLD).
const COLD_EXTRA_FOOD := 0.5
const COLD_EXTRA_WARMTH := 1.0
const COLD_EXTRA_FUEL := 1.5
const OUTDOOR_WARMTH_FACTOR := 0.7 # тепло на улице = (1 - холод) * это
const SHELTER := {&"dugout": 0.10, &"izba": 0.25, &"stone_house": 0.40}  # доля «до 1», что даёт крыша без печи
const PUBLIC_SHELTER := 0.20       # столовая/больница (без отопления; ХУК: печи общественных зданий)
const STOVE_HEAT := 0.6            # прибавка тепла дома от горящей печи
const HOUSE_HEAT_PER_DAY := 2.7    # дом прогревается, ед./сутки
const HOUSE_COOL_PER_DAY := 1.3    # и остывает
const WARMTH_RATE_PER_DAY := 1.3   # житель подстраивается под среду
const WARM_BELOW := 0.3            # пора домой греться
const WARM_DONE := 0.6
const COLD_WARNING := 0.35
const STOKE_BELOW := 1               # житель идёт топить, когда в печи не больше стольких дров
const BURN_LOGS_PER_DAY := 1.7     # дров в сутки горит печь при множителе 1
const HEAT_MIN_COLD := 0.02        # ниже — тепло не нужно (хук wants_heat)

# ---------- сон ----------
const NIGHT_START_HOUR := 21.0
const NIGHT_END_HOUR := 6.0
const EXHAUSTED := 0.15            # днём тоже ложатся спать
const DAY_NAP_WAKE := 0.6
const NIGHT_SHIFT_MIN_REST := 0.3  # врач на дежурстве у пациентов не спит ночью, пока не устал

# ---------- здоровье и болезни ----------
const CRITICAL_NEED := 0.12        # ниже — начинает вредить здоровью
const STARVE_DRAIN_PER_DAY := 0.2  # за каждую критичную потребность (при нуле)
const HEALTH_REGEN_PER_DAY := 0.083 # когда всё в порядке
const REGEN_NEEDS_MIN := 0.35
const SICK_BASE_PER_DAY := 0.01    # шанс заболеть в сутки при сытой жизни
const SICK_NEED_WEIGHT := 0.33      # + сумма ((FLOOR-потребность)/FLOOR)^2 по базовым потребностям
const SICK_NEED_FLOOR := 0.5       # выше этого уровня потребность на болезнь не влияет
const SICK_ROLL_INTERVAL := 20.0   # как часто бросать кубик, игр. с
const SICK_DRAIN_PER_DAY := 0.13    # без лечения здоровье падает
const SICK_START_HEALTH_CAP := 0.85
const RECOVER_HEALTH := 0.85       # здоров, когда здоровье снова не ниже
const HERO_HEALTH_FLOOR := 0.05    # герой не умирает

# ---------- больница ----------
const HOSPITAL_BEDS := 4
const HOSPITAL_STAFF_SLOTS := 2
const TREAT_PRIORITY := 3
const HEAL_PER_DAY := 0.67          # лечение врачом, здоровье/сутки на пациента
const NONDOCTOR_HEAL_MULT := 0.5   # если врача в посёлке нет, лечит любой, хуже
const HEAL_BED_REST_PER_DAY := 0.0 # койка без персонала не лечит

# ---------- влияние на работу ----------
const RATE_PENALTY_BELOW := 0.3    # ниже — потребность снижает скорость работы
const NEED_RATE_FLOOR := {FOOD: 0.6, WATER: 0.5, WARMTH: 0.7, REST: 0.5}  # множитель при нуле
const HEALTH_RATE_BELOW := 0.5
const HEALTH_RATE_FLOOR := 0.5
const MIN_NEEDS_RATE := 0.15


## Климат: множитель расхода от мороза (kind — &"food" | &"warmth" | &"fuel").
static func cold_factor(kind: StringName, cold: float) -> float:
	var extra := 0.0
	match kind:
		FOOD:
			extra = COLD_EXTRA_FOOD
		WARMTH:
			extra = COLD_EXTRA_WARMTH
		&"fuel":
			extra = COLD_EXTRA_FUEL
	var over := clampf((cold - MILD_COLD) / (1.0 - MILD_COLD), 0.0, 1.0)
	return 1.0 + extra * over


## Шанс заболеть в сутки по уровням потребностей (чем ниже, тем выше).
static func sick_rate_per_day(needs: Dictionary) -> float:
	var r := SICK_BASE_PER_DAY
	for n in BASIC:
		var d := maxf(0.0, SICK_NEED_FLOOR - float(needs.get(n, 1.0))) / SICK_NEED_FLOOR
		r += SICK_NEED_WEIGHT * d * d
	return r


static func housing_capacity(type: StringName) -> int:
	return HOUSING_CAPACITY.get(type, 0)


static func shelter(type: StringName) -> float:
	return SHELTER.get(type, PUBLIC_SHELTER)


static func outdoor_warmth(cold: float) -> float:
	return clampf(1.0 - cold, 0.0, 1.0) * OUTDOOR_WARMTH_FACTOR


## Тепло неотапливаемого здания: крыша поднимает уличное к 1 на долю shelter.
static func unheated_warmth(type: StringName, cold: float) -> float:
	var o := outdoor_warmth(cold)
	return o + (1.0 - o) * shelter(type)


static func is_night(hour: float) -> bool:
	return hour >= NIGHT_START_HOUR or hour < NIGHT_END_HOUR


static func full() -> Dictionary:
	return {FOOD: 1.0, WATER: 1.0, WARMTH: 1.0, REST: 1.0, HEALTH: 1.0}


## Множитель скорости работы от нужд (1.0, когда всё в порядке).
static func rate_multiplier(needs: Dictionary) -> float:
	var m := 1.0
	for n in BASIC:
		var x: float = needs.get(n, 1.0)
		if x < RATE_PENALTY_BELOW:
			m *= lerpf(NEED_RATE_FLOOR[n], 1.0, clampf(x / RATE_PENALTY_BELOW, 0.0, 1.0))
	var h: float = needs.get(HEALTH, 1.0)
	if h < HEALTH_RATE_BELOW:
		m *= lerpf(HEALTH_RATE_FLOOR, 1.0, clampf(h / HEALTH_RATE_BELOW, 0.0, 1.0))
	return maxf(MIN_NEEDS_RATE, m)


## Сводная «нужда» 0..1 (хук ссор/ухода): 0 — всё хорошо.
static func suffering(needs: Dictionary, sick: bool) -> float:
	var s := 0.0
	for n in BASIC:
		s += maxf(0.0, RATE_PENALTY_BELOW - float(needs.get(n, 1.0))) / RATE_PENALTY_BELOW
	s = s / float(BASIC.size()) + (0.25 if sick else 0.0) + maxf(0.0, HEALTH_RATE_BELOW - float(needs.get(HEALTH, 1.0))) * 0.5
	return clampf(s, 0.0, 1.0)


## Какие предупреждения показывать у жителя (id потребностей), по важности.
static func warnings(needs: Dictionary, sick: bool) -> Array[StringName]:
	var out: Array[StringName] = []
	if sick:
		out.append(HEALTH)
	if float(needs.get(WATER, 1.0)) < DRINK_BELOW:
		out.append(WATER)
	if float(needs.get(FOOD, 1.0)) < EAT_BELOW:
		out.append(FOOD)
	if float(needs.get(WARMTH, 1.0)) < COLD_WARNING:
		out.append(WARMTH)
	if float(needs.get(REST, 1.0)) < EXHAUSTED * 2.0:
		out.append(REST)
	return out


static func warning_text(needs: Dictionary, sick: bool) -> String:
	var parts: Array[String] = []
	for w in warnings(needs, sick):
		parts.append("⚠ " + WARNING_NAMES[w])
	return " ".join(parts)


static func bar(x: float, cells: int = 10) -> String:
	var n := clampi(roundi(x * cells), 0, cells)
	return "█".repeat(n) + "░".repeat(cells - n)


static func card_lines(needs: Dictionary) -> String:
	var lines: Array[String] = []
	for n in NEEDS:
		var x: float = needs.get(n, 1.0)
		lines.append("%s  %s %d%%" % [NAMES[n], bar(x), roundi(x * 100.0)])
	return "\n".join(lines)
