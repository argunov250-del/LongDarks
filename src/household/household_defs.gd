class_name HouseholdDefs
extends RefCounted
## Русский сельский двор (шаг 10b): геометрия двора, ёмкости запасов и ВЕСЬ баланс
## домашнего хозяйства (плейсхолдеры) — одно место.
##
## Система координат: «локальные» — оси здания (X вправо, Z вперёд, начало в центре дома).
## Двор лежит в локальной +Z-стороне дома; «двор-локальные» точки отсчитываются от центра двора.

# ---------- двор ----------
const YARD_SIZE := Vector2(8.0, 6.0)        # ширина (X) и глубина (Z) участка, м
const YARD_OFFSET := Vector2(0.0, 6.0)      # центр двора в локальных координатах здания
const FENCE_HEIGHT := 0.9                   # низкий деревянный забор
const GATE_WIDTH := 1.6                     # проём калитки на стороне дома

## Места во дворе (двор-локальные): где стоит житель и что где стоит.
const WOODPILE_SIZE := Vector2(1.8, 0.8)
const WOODPILE_POS := Vector2(-2.7, -2.2)   # поленница
const WOODPILE_STAND := Vector2(-2.7, -1.4) # где стоит житель, кладущий дрова
const CHOP_STAND := Vector2(-1.3, -1.6)     # колода для колки
const GARDEN_SIZE := Vector2(3.4, 3.6)
const GARDEN_POS := Vector2(2.0, 0.6)       # огород
const GARDEN_STAND := Vector2(0.1, 0.6)     # край грядок
const BARN_SIZE := Vector2(3.0, 2.0)
const BARN_POS := Vector2(-1.7, 1.7)        # сарай (если построен)
const DOOR_LOCAL := Vector2(0.0, 3.3)       # у двери дома (локальные координаты здания)
const SPOT_RADIUS := 0.7                    # допуск «пришёл на место», м

# ---------- запасы ----------
const HOUSE_FOOD_CAPACITY := 30             # еда в доме (единиц)
const HOUSE_WATER_CAPACITY := 12            # вода в доме (единиц)
const CANTEEN_FOOD_CAPACITY := 60
const CANTEEN_WATER_CAPACITY := 30

# ---------- вода ----------
const BUCKET_VOLUME := 3                    # единиц воды в одном ведре
const BUCKETS_CARRIED := 2                  # вёдер за ходку (коромысло/руки)
const WATER_CARRY := BUCKET_VOLUME * BUCKETS_CARRIED
const WELL_DRAW_WORK := 3.0                 # работа на наполнение вёдер (журавль/ворот)

# ---------- огород ----------
const GARDEN_GROW_TIME := 240.0             # с от посадки до урожая (плейсхолдер)
const GARDEN_YIELD := 8                     # единиц урожая за цикл (культура чередуется)
const GARDEN_CROPS: Array[StringName] = [&"potato", &"vegetables"]
const PLANT_WORK := 6.0                     # работа на посадку
const HARVEST_WORK := 6.0                   # работа на сбор

# ---------- сарай ----------
# Цена и работа сарая — обычная стройка, см. BuildingDefs (&"barn").
const CHICKENS := 4                         # куры в сарае (без кормёжки)
const EGG_PERIOD := 40.0                    # с на одно яйцо всего (плейсхолдер)
const COWS := 1
const MILK_PERIOD := 60.0                   # с на единицу молока


## ХУК СЕЗОНОВ: можно ли сажать/собирать сегодня (phase: &"plant" | &"harvest" | &"grow").
## Сейчас всегда да; позже — по календарю (посадка весной, сбор осенью, зимой рост стоит).
static func garden_season_allows(_day: int, _phase: StringName) -> bool:
	return true
