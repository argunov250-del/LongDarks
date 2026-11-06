class_name ClimateDefs
extends RefCounted
## Потепление климата (шаг 15), design/gdd/climate-warming.md: ВЕСЬ баланс — одно место.
## Все числа — плейсхолдеры для проверки дизайнером.

## Потепление в °C за год без бонусов (копится по четверти в конце каждого сезона).
const BASE_WARMING_PER_YEAR := 0.3
## Бонус ускорения от посаженного леса: + за клетку, потолок суммы (доля к базе).
const FOREST_BONUS_PER_CELL := 0.004
const FOREST_BONUS_MAX := 1.5
## Бонус от вспаханной земли (тёмная почва греется).
const PLOW_BONUS_PER_CELL := 0.01
const PLOW_BONUS_MAX := 1.0
## Предел потепления, °C; при нём зима самая короткая.
const MAX_WARMING := 8.0
## Температурная добавка = потепление * этот коэффициент (°C на °C).
const TEMP_PER_WARMING := 1.0
## Самая короткая зима — эта доля начальной (MAX_WARMING достигнут).
const WINTER_MIN_FRACTION := 0.6
## Освободившиеся минуты зимы: доля уходит весне, остаток лету (год постоянной длины).
const SPRING_SHARE := 0.5
## Первые птицы весной при потеплении не ниже, °C.
const FIRST_BIRDS_WARMING := 0.6
## Вехи потепления (°C): событие warming_milestone на каждую, один раз.
const MILESTONES: Array[float] = [1.0, 2.0, 4.0, 6.0, 8.0]
## Птицы: число при первых птицах и при полном потеплении; в стае — до BIRD_FLOCK_SIZE.
const BIRDS_MIN := 8
const BIRDS_MAX := 48
const BIRD_FLOCK_SIZE := 8

# ---------- визуал птиц ----------
const BIRD_FADE_IN := 0.1          # доля весны, за которую птицы прилетают
const BIRD_FADE_OUT := 0.08        # доля весны в конце: улетают
const BIRD_SPEED := 9.0            # м/с
const BIRD_ALTITUDE_MIN := 9.0     # м над землёй в полёте
const BIRD_ALTITUDE_MAX := 18.0
const BIRD_ARC := 3.0              # амплитуда дуги полёта, м
const BIRD_WAYPOINT_RADIUS := 45.0 # новая цель — не дальше от фокуса камеры, м
const BIRD_LAND_CHANCE := 0.6      # шанс сесть на дерево в точке назначения
const BIRD_PERCH_TIME_MIN := 4.0
const BIRD_PERCH_TIME_MAX := 9.0
const BIRD_TREE_TOP := 3.4         # высота верхушки дерева над землёй, м
const BIRD_SCALE := 0.9
