class_name SeasonDefs
extends RefCounted
## Сезоны и климат (шаг 13): ВЕСЬ баланс календаря и температуры — одно место.
## Длительности сезонов — в реальных минутах при скорости 1x; SeasonSystem хранит их
## изменяемыми (ХУК потепления/сложности, шаг 15): SeasonSystem.set_duration_minutes().
## Цикл года: весна -> лето -> осень -> зима (игра стартует в конце зимы).

const SPRING := &"spring"
const SUMMER := &"summer"
const AUTUMN := &"autumn"
const WINTER := &"winter"
const ORDER: Array[StringName] = [SPRING, SUMMER, AUTUMN, WINTER]
const NAMES := {SPRING: "Весна", SUMMER: "Лето", AUTUMN: "Осень", WINTER: "Зима"}

## Длительность сезонов, реальные минуты при 1x (зима дольше всех, лето короче всех).
const DEFAULT_MINUTES := {SPRING: 25.0, SUMMER: 20.0, AUTUMN: 25.0, WINTER: 30.0}

# ---------- температура, °C ----------
## Средняя температура в СЕРЕДИНЕ сезона; между серединами — плавная (косинусная) кривая.
const SEASON_TEMP := {SPRING: 7.0, SUMMER: 19.0, AUTUMN: 3.0, WINTER: -14.0}
## Размах суточных колебаний (± от среднего, пик в DAY_PEAK_HOUR, минимум на 12 ч раньше).
const DAY_SWING := {SPRING: 4.5, SUMMER: 5.5, AUTUMN: 3.5, WINTER: 2.5}
const DAY_PEAK_HOUR := 15.0
## Детерминированный «шум погоды»: случайное значение на сутки, сглаженное между сутками.
const NOISE_AMPLITUDE := 2.0
const NOISE_SEED := 9173

# ---------- правила, привязанные к температуре ----------
const HEATING_MAX_TEMP := 5.0          # печи топят при +5 °C и ниже (правило дизайнера)
const SPOIL_COLD_BELOW := 4.0          # ниже — еда не портится (ambient_cold)
const FROST_BELOW := -1.0              # сезонная средняя ниже — земля промёрзла (только зимой)
const COLD_ZERO_TEMP := 20.0           # outdoor_cold = 0 при этой температуре и выше
const COLD_FULL_TEMP := -25.0          # outdoor_cold = 1 при этой температуре и ниже
const FROST_BUILD_MIN := 0.5           # скорость стройки при FROST_BUILD_FULL_TEMP и ниже
const FROST_BUILD_FULL_TEMP := -15.0
const CONSUMPTION_WINTER_EXTRA := 0.3  # + к множителю расхода на сильном морозе
const CONSUMPTION_FROM_TEMP := 5.0     # сезонная средняя ниже — расход растёт
const CONSUMPTION_FULL_TEMP := -15.0
## Распутица (весна): доля замедления шага на полной грязи и форма «грязи» по весне.
const MUD_WALK_SLOW := 0.35
const MUD_RAMP_IN := 0.12              # доля весны, за которую грязь нарастает
const MUD_PEAK_END := 0.45             # до этой доли весны грязь максимальна, дальше сохнет

# ---------- визуал ----------
## Снег: зимой 1; весной тает (быстро в начале), осенью возвращается к концу.
const SNOW_SPRING_MELT_FROM := 0.05
const SNOW_SPRING_MELT_TO := 0.6
const SNOW_AUTUMN_FROM := 0.6
## Значения в серединах сезонов (между ними — плавно).
const GRASS_TINT := {
	SPRING: Color(0.85, 1.12, 0.75), SUMMER: Color(0.70, 1.32, 0.60),
	AUTUMN: Color(1.22, 0.95, 0.60), WINTER: Color(1.0, 1.0, 1.0),
}
const GRASS_AMOUNT := {SPRING: 0.7, SUMMER: 1.0, AUTUMN: 0.8, WINTER: 0.0}
const SKY_TOP := {
	SPRING: Color(0.50, 0.68, 0.84), SUMMER: Color(0.30, 0.58, 0.88),
	AUTUMN: Color(0.52, 0.58, 0.68), WINTER: Color(0.52, 0.58, 0.68),
}
const SKY_HORIZON := {
	SPRING: Color(0.80, 0.88, 0.92), SUMMER: Color(0.76, 0.88, 0.96),
	AUTUMN: Color(0.88, 0.80, 0.72), WINTER: Color(0.84, 0.87, 0.92),
}
const LIGHT_COLOR := {
	SPRING: Color(1.0, 0.96, 0.88), SUMMER: Color(1.0, 0.94, 0.82),
	AUTUMN: Color(1.0, 0.86, 0.70), WINTER: Color(0.88, 0.92, 1.0),
}
const LIGHT_ENERGY := {SPRING: 1.1, SUMMER: 1.3, AUTUMN: 1.0, WINTER: 0.9}
const AMBIENT_COLOR := {
	SPRING: Color(0.72, 0.78, 0.86), SUMMER: Color(0.74, 0.80, 0.88),
	AUTUMN: Color(0.78, 0.74, 0.74), WINTER: Color(0.70, 0.76, 0.88),
}


static func season_name(season: StringName) -> String:
	return NAMES.get(season, String(season))


static func default_durations() -> Dictionary:
	var d := {}
	for s in ORDER:
		d[s] = DEFAULT_MINUTES[s] * 60.0
	return d


## outdoor_cold 0..1 (хук потребностей) из температуры.
static func cold_from_temp(temp: float) -> float:
	return clampf((COLD_ZERO_TEMP - temp) / (COLD_ZERO_TEMP - COLD_FULL_TEMP), 0.0, 1.0)
