class_name WeatherDefs
extends RefCounted
## Погодные события (шаг 14): ВЕСЬ баланс и таблица событий — одно место (как SeasonDefs).
## GDD: design/gdd/weather-events.md. Времена — игровые секунды (при 1x равны реальным);
## длительности событий заданы в минутах таблицы GDD, здесь сразу в секундах.

const BLIZZARD := &"blizzard"
const SEVERE_FROST := &"severe_frost"
const DOWNPOUR := &"downpour"
const FLOOD := &"flood"
const DROUGHT := &"drought_heat"
const THUNDERSTORM := &"thunderstorm"
const HURRICANE := &"hurricane"
## Порядок = приоритет при одновременном успехе бросков в одни сутки.
const ORDER: Array[StringName] = [BLIZZARD, SEVERE_FROST, DOWNPOUR, FLOOD, DROUGHT, THUNDERSTORM, HURRICANE]

# ---------- планировщик ----------
const NO_EVENTS_FIRST_DAYS := 2        # событий нет, пока clock.get_day() <= этого
const COOLDOWN := 240.0                # пауза после события, с (кроме паводка после ливня)
const AFTER_TIME := 30.0               # фаза «после»: собака успокаивается, температура возвращается
const RAMP_IN := 20.0                  # температура/вид нарастают за это время после старта
const FLOOD_AFTER_RAIN_MIN := 180.0    # ливень не короче этого может вызвать паводок (вне зимы)
const FLOOD_AFTER_RAIN_CHANCE := 0.3
const SALT_START := 11                 # соль хеш-бросков (детерминированный план)
const SALT_DURATION := 12
const SALT_ROLL := 13
const SALT_FLOOD_RAIN := 14

# ---------- таблица событий ----------
## seasons: сезон -> {"freq": раз/сезон, "from": доля сезона от, "to": до}. dur — [мин, макс], с.
## temp — Δt, °C; build/walk — множители; lead — упреждение собаки, с; peak — пик тревоги 0..1.
## stuck — вязкость для техники 0..1 (хук); mud — нижняя граница mud_level.
## garden — множитель роста огорода; dry — убыль прогресса огорода (доля скорости роста);
## well — во сколько раз дольше наполнение вёдер; water_decay — множитель убыли воды у жителей.
## shelter — жители идут домой; exp_warmth/exp_drain — потери на улице (множитель тепла, здоровье/сутки).
## rain — идёт дождь (огород +1 сутки после); extinguish — гасит пожар; lightning — молнии.
const EVENTS := {
	BLIZZARD: {
		"name": "Метель", "toast": "Началась метель",
		"seasons": {&"winter": {"freq": 1.0}, &"autumn": {"freq": 0.3, "from": 0.7}},
		"dur": [180.0, 300.0], "temp": -8.0, "build": 0.0, "walk": 0.6, "lead": 90.0, "peak": 0.7,
		"stuck": 1.0, "shelter": true, "exp_warmth": 2.5, "exp_drain": 0.30,
	},
	SEVERE_FROST: {
		"name": "Сильный мороз", "toast": "Ударил сильный мороз",
		"seasons": {&"winter": {"freq": 0.7}},
		"dur": [300.0, 480.0], "temp": -12.0, "build": 1.0, "walk": 1.0, "lead": 120.0, "peak": 0.4,
	},
	DOWNPOUR: {
		"name": "Ливень", "toast": "Начался ливень",
		"seasons": {&"spring": {"freq": 1.0}, &"summer": {"freq": 0.7}, &"autumn": {"freq": 0.7}},
		"dur": [120.0, 240.0], "temp": -3.0, "build": 0.0, "walk": 0.8, "lead": 60.0, "peak": 0.5,
		"stuck": 0.8, "mud": 0.8, "rain": true, "extinguish": true, "garden": 1.3,
	},
	FLOOD: {
		"name": "Паводок", "toast": "Начался паводок",
		"seasons": {&"spring": {"freq": 0.7, "from": 0.1, "to": 0.5}},
		"dur": [180.0, 300.0], "temp": 0.0, "build": 1.0, "walk": 1.0, "lead": 120.0, "peak": 0.5,
		"stuck": 0.8, "flood": true,
	},
	DROUGHT: {
		"name": "Засуха", "toast": "Наступила засуха",
		"seasons": {&"summer": {"freq": 0.5}},
		"dur": [360.0, 600.0], "temp": 8.0, "build": 0.8, "walk": 1.0, "lead": 120.0, "peak": 0.3,
		"garden": 0.0, "dry": 0.3, "well": 2.5, "water_decay": 1.5,
	},
	THUNDERSTORM: {
		"name": "Гроза", "toast": "Началась гроза",
		"seasons": {&"spring": {"freq": 0.3, "from": 0.5}, &"summer": {"freq": 1.0}, &"autumn": {"freq": 0.3, "to": 0.4}},
		"dur": [120.0, 180.0], "temp": -4.0, "build": 0.0, "walk": 0.9, "lead": 60.0, "peak": 0.8,
		"stuck": 0.5, "shelter": true, "exp_warmth": 1.5, "exp_drain": 0.15, "rain": true, "lightning": true, "garden": 1.3,
	},
	HURRICANE: {
		"name": "Ураган", "toast": "Налетел ураган",
		"seasons": {&"summer": {"freq": 0.2}, &"autumn": {"freq": 0.3}},
		"dur": [120.0, 180.0], "temp": -3.0, "build": 0.0, "walk": 0.5, "lead": 90.0, "peak": 1.0,
		"stuck": 1.0, "shelter": true, "exp_warmth": 2.0, "exp_drain": 0.20,
	},
}

# ---------- паводок ----------
const FLOOD_RISE := 60.0               # подъём воды, с
const FLOOD_RECEDE := 120.0            # спад, с
const FLOOD_REACH_CELLS := 3           # не дальше этого числа клеток (4-связность) от воды
const FLOOD_HEIGHT := 1.5              # пик уровня над WorldMap.WATER_LEVEL, м
const FLOOD_LEVEL_STEP := 0.05         # пересчёт затопления при изменении уровня на столько, м

# ---------- огород ----------
const GARDEN_RAIN_AFTER := 480.0       # огороду «после дождя» ещё сутки (480 с)
const GARDEN_YIELD_FERTILITY := 1.0    # урожай = GARDEN_YIELD * (1 + fertility * это)

# ---------- гроза и пожар ----------
const LIGHTNING_PERIOD := 20.0         # с между ударами
const IGNITE_CHANCE := 0.35            # поджог лесной клетки с деревьями
const BURN_TIME := 60.0                # горение клетки леса, с
const SPREAD_INTERVAL := 10.0          # как часто огонь пробует перейти, с
const SPREAD_CHANCE := 0.1             # на соседнюю клетку леса за интервал
const MAX_BURN_CELLS := 10             # клеток на очаг
const BUILDING_FIRE_REACH := 3.0       # здание не дальше от горящей клетки (м) может загореться
const BUILDING_IGNITE_CHANCE := 0.3    # за интервал, от каждой горящей клетки
const BUILDING_BURN_TIME := 90.0       # здание горит до повреждения, с
const FOREST_FIRE_WATER := 6           # воды, чтобы потушить лесную клетку (1 ходка)
const BUILDING_FIRE_WATER := 18        # и здание (3 ходки)
const BURN_FERTILITY := 0.5            # плодородие выгоревшей клетки (урожай 8 -> 12)
const FERTILITY_MAX := 1.0
const FERTILITY_LIFETIME_YEARS := 1.0  # бонус BURN_FERTILITY сходит на нет за столько игровых лет
const REPAIR_COST_FRACTION := 0.25     # повреждённое здание: доля полной цены (ceil)
const REPAIR_WORK_FRACTION := 0.35     # и доля суммарной работы стадий

# ---------- вид ----------
const FADE := 10.0                     # вид события нарастает/гаснет за столько секунд
const FLASH_TIME := 0.18               # вспышка молнии, реальные секунды
const FLASH_ALPHA := 0.55
const SNOW_AMOUNT := 700
const RAIN_AMOUNT := 600
const PARTICLE_BOX := Vector3(70.0, 24.0, 70.0)
const FIRE_COLOR := Color(1.0, 0.45, 0.1)
const BURNT_COLOR := Color(0.07, 0.06, 0.05)
const BURNT_ALPHA_MAX := 0.85
const FLOOD_COLOR := Color(0.28, 0.42, 0.50, 0.78)
## Вид неба и света: sky — цвет неба/горизонта (смешивается), light — множитель света, ambient — ambient,
## fog — плотность тумана и его цвет, sun — оттенок солнца (множитель цвета).
const LOOKS := {
	BLIZZARD: {"sky": Color(0.80, 0.84, 0.90), "mix": 0.85, "light": 0.55, "ambient": 0.85, "fog": 0.018, "fog_color": Color(0.86, 0.89, 0.94), "sun": Color(1, 1, 1)},
	SEVERE_FROST: {"sky": Color(0.62, 0.78, 0.96), "mix": 0.5, "light": 1.0, "ambient": 1.0, "fog": 0.0, "fog_color": Color.WHITE, "sun": Color(0.85, 0.93, 1.0)},
	DOWNPOUR: {"sky": Color(0.40, 0.44, 0.50), "mix": 0.8, "light": 0.5, "ambient": 0.85, "fog": 0.008, "fog_color": Color(0.5, 0.54, 0.6), "sun": Color(0.9, 0.95, 1.0)},
	FLOOD: {"sky": Color(0.55, 0.60, 0.66), "mix": 0.5, "light": 0.8, "ambient": 0.95, "fog": 0.003, "fog_color": Color(0.6, 0.65, 0.7), "sun": Color(1, 1, 1)},
	DROUGHT: {"sky": Color(0.95, 0.85, 0.55), "mix": 0.55, "light": 1.15, "ambient": 1.05, "fog": 0.007, "fog_color": Color(0.95, 0.85, 0.55), "sun": Color(1.15, 1.0, 0.7)},
	THUNDERSTORM: {"sky": Color(0.22, 0.24, 0.30), "mix": 0.9, "light": 0.35, "ambient": 0.75, "fog": 0.009, "fog_color": Color(0.30, 0.32, 0.38), "sun": Color(0.85, 0.9, 1.0)},
	HURRICANE: {"sky": Color(0.32, 0.35, 0.40), "mix": 0.85, "light": 0.45, "ambient": 0.8, "fog": 0.01, "fog_color": Color(0.42, 0.45, 0.50), "sun": Color(0.9, 0.95, 1.0)},
}
## Частицы: вид (&"snow"|&"rain"|&""), горизонтальный ветер (м/с), скорость падения (м/с).
const PARTICLES := {
	BLIZZARD: {"kind": &"snow", "wind": 14.0, "fall": 4.0, "amount": 1.0},
	DOWNPOUR: {"kind": &"rain", "wind": 3.0, "fall": 26.0, "amount": 1.0},
	THUNDERSTORM: {"kind": &"rain", "wind": 5.0, "fall": 28.0, "amount": 1.0},
	HURRICANE: {"kind": &"rain", "wind": 22.0, "fall": 20.0, "amount": 0.8},
	FLOOD: {"kind": &"rain", "wind": 1.0, "fall": 22.0, "amount": 0.3},
}
const TREE_SWAY_HURRICANE := 0.22      # амплитуда качания деревьев (м на метр высоты)
const TREE_SWAY_STORM := 0.07


static func exists(id: StringName) -> bool:
	return EVENTS.has(id)


static func def(id: StringName) -> Dictionary:
	return EVENTS.get(id, {})


static func display_name(id: StringName) -> String:
	return def(id).get("name", String(id))


static func toast_text(id: StringName) -> String:
	return def(id).get("toast", "")


static func f(id: StringName, key: String, fallback: float) -> float:
	return float(def(id).get(key, fallback))


## Событие допустимо в сезоне при доле сезона p (freq > 0 и в окне from..to).
static func freq_in(id: StringName, season: StringName, p: float) -> float:
	var s: Dictionary = (def(id).get("seasons", {}) as Dictionary).get(season, {})
	if s.is_empty():
		return 0.0
	if p < float(s.get("from", 0.0)) or p > float(s.get("to", 1.0)):
		return 0.0
	return float(s.get("freq", 0.0))


## Детерминированный хеш-шум [0,1) от целых (seed, год, сутки, id события, соль).
static func hash01(seed_value: int, year: int, day: int, id: StringName, salt: int) -> float:
	var x: int = (seed_value * 2654435761 + year * 73856093 + day * 19349663 + String(id).hash() * 83492791 + salt * 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	x = x ^ (x >> 16)
	return float(x & 0xffffff) / 16777216.0


## Длительность события (с) для детерминированного броска.
static func duration_for(id: StringName, r: float) -> float:
	var d: Array = def(id).get("dur", [120.0, 180.0])
	return lerpf(float(d[0]), float(d[1]), r)


## Затопление: уровень воды над WATER_LEVEL (м) на секунде e события длительностью dur (пик держится dur).
static func flood_level(e: float, peak_len: float) -> float:
	if e < FLOOD_RISE:
		return FLOOD_HEIGHT * clampf(e / FLOOD_RISE, 0.0, 1.0)
	if e < FLOOD_RISE + peak_len:
		return FLOOD_HEIGHT
	return FLOOD_HEIGHT * clampf(1.0 - (e - FLOOD_RISE - peak_len) / FLOOD_RECEDE, 0.0, 1.0)


## Полная длительность паводка (подъём + пик + спад).
static func flood_total(peak_len: float) -> float:
	return FLOOD_RISE + peak_len + FLOOD_RECEDE
