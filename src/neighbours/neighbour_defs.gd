class_name NeighbourDefs
extends RefCounted
## Баланс соседнего поселения (шаг 24, design/gdd/neighbours.md). Только данные, плейсхолдеры.

## --- Соседи на старте (данные; система поддерживает несколько) ---
## side: 0 верх (z=0), 1 низ, 2 лево (x=0), 3 право; along: доля вдоль края.
const START: Array = [
	{"id": &"zarechye", "name": "Заречье", "side": 3, "along": 0.35, "relation": 0.1, "baseline": 0.05, "greed": 0.4, "aggression": 0.5,
		"pop": 12, "level": 2, "vehicles": 1, "mood": 0.7,
		"stock": {&"potato": 90.0, &"fish": 20.0, &"firewood": 60.0, &"planks": 30.0, &"logs": 40.0, &"spare_parts": 6.0, &"scrap_metal": 12.0}},
]

## --- Экономика соседа (за игровые сутки) ---
const SEASON_FARM := {&"spring": 0.7, &"summer": 1.3, &"autumn": 1.0, &"winter": 0.15}
const WEATHER_PROD_MULT := 0.7           # во время погодного события
const FOOD_EAT := 1.0                    # еды на душу в сутки
const WOOD_BURN := {&"winter": 0.8, &"autumn": 0.3, &"spring": 0.3, &"summer": 0.0}
const FARM_PER_POP := 1.25               # картофель на душу (× сезон × уровень)
const FISH_PER_POP := 0.2
const WOOD_PER_POP := 0.9
const LOGS_PER_POP := 0.5
const PLANKS_PER_POP := 0.25
const PARTS_PER_POP_LEVEL := 0.03
const SCRAP_PER_POP := 0.1
const LEVEL_MULT := 0.15                 # прибавка производства за уровень выше 1
const MAX_LEVEL := 5
const LEVEL_PLANKS_COST := 30            # × текущий уровень
const LEVEL_POP_PER_LEVEL := 6
const POP_MAX_PER_LEVEL := 10
const POP_MIN := 3
const GROW_FOOD_DAYS := 12.0
const GROW_MOOD := 0.6
const GROW_PER_DAY := 0.12
const STARVE_MOOD := 0.2
const STARVE_POP_CHANCE := 0.4
const MOOD_RATE := 0.25
const FOOD_SAFE_DAYS := 10.0
const VEHICLE_PARTS_COST := 6.0
const VEHICLE_MIN_LEVEL := 3
const STOCK_CAP := 400.0
const STOCK_RESERVE := {&"potato": 40.0, &"fish": 5.0, &"firewood": 30.0, &"planks": 10.0, &"logs": 15.0, &"spare_parts": 3.0, &"scrap_metal": 4.0}

## --- Ценность (условные единицы) ---
const BASE_VALUE := {&"logs": 1.0, &"planks": 2.0, &"stone": 1.5, &"scrap_metal": 2.0, &"firewood": 1.0, &"potato": 1.0, &"grain": 1.0,
	&"vegetables": 1.2, &"meat": 3.0, &"fish": 2.5, &"milk": 1.5, &"eggs": 1.5, &"mushrooms": 1.5, &"oil": 4.0, &"biodiesel": 5.0,
	&"alcohol": 4.0, &"spare_parts": 8.0, &"coal": 2.0, &"cement": 4.0}
const VEHICLE_VALUE := {&"pickup": 160.0, &"atv": 220.0, &"snowmobile": 140.0}
const VEHICLE_COND := 0.8
const VEHICLE_FUEL := 15.0
const NEED_PREMIUM := 1.0                # надбавка к цене того, в чём у соседа нужда
const REL_DISCOUNT := 0.3                # покупка у соседа: × (1 − 0.3×отношения)
const REL_BONUS := 0.3                   # их оценка ваших товаров: × (1 + 0.3×отношения)
const VISIT_DISCOUNT := 0.15
const TRADE_RES: Array[StringName] = [&"potato", &"fish", &"firewood", &"planks", &"logs", &"spare_parts", &"scrap_metal"]
const WANT_DEFAULT: Array[StringName] = [&"scrap_metal", &"planks", &"spare_parts"]
const LOT := 20
const MIN_LOT := 6
const OFFER_REFRESH_DAYS := 4.0
const TRADE_REL_GAIN := 0.02

## --- Караваны ---
const CARAVAN_SPEED := 2.0               # м/с пешком (учитывает скорость игры через dt)
const CARAVAN_SPEED_VEHICLE := 5.0
const VISIT_PERIOD_DAYS := 6.0
const VISIT_MIN_REL := -0.2
const VISIT_STAY_DAYS := 2.0
const RAID_SPEED := 2.4

## --- Отношения ---
const REL_NAMES := [[-0.5, "вражда"], [-0.15, "напряжённость"], [0.3, "нейтралитет"], [0.6, "дружба"], [2.0, "союз"]]
const DRIFT_PER_DAY := 0.03
const TREND_SMOOTH := 0.8
const EVENT_CHANCE := 0.08
const EVENT_GOOD := 0.08
const EVENT_BAD := 0.08
const DESPERATION_NEED := 0.7
const DESPERATION_PULL := 0.12

## --- Помощь ---
const REQUEST_NEED := 0.6
const REQUEST_QTY := {&"food": 30, &"firewood": 25, &"spare_parts": 3}
const REQUEST_DAYS := 5.0
const REQUEST_COOLDOWN_DAYS := 6.0
const HELP_GAIN := 0.15
const REFUSE_LOSS := 0.08
const IGNORE_LOSS := 0.04
const ASK_MIN_REL := -0.1
const ASK_COST := 0.02
const ASK_DENIED_COST := 0.03

## --- Дипломатия ---
const GIFT_GAIN := 0.012                 # отношения за единицу ценности
const GIFT_DAILY_CAP := 0.25
const PACT_MIN_REL := 0.0
const PACT_BREAK_REL := -0.6
const PACT_DAYS := 20.0
const PACT_COST := {&"planks": 10, &"potato": 15}
const TRIBUTE_FACTOR := 0.2              # множитель частоты краж/налётов при дани
const TRIBUTE_REL_PER_PAY := 0.03
const TRIBUTE_MISS_LOSS := 0.1

## --- Враждебность, кражи, налёты ---
const HOSTILE_FROM := 0.15
const THEFT_BASE := 0.55
const THEFT_COOLDOWN_DAYS := 2.0
const THEFT_MIN := 3
const THEFT_MAX := 8
const THEFT_POWER := 2.0
const RAID_REL_MAX := -0.4
const RAID_BASE := 0.3
const RAID_COOLDOWN_DAYS := 6.0
const RAID_MIN_POP := 6
const RAID_POWER_BASE := 2.0
const RAID_POWER_PER_POP := 0.25
const RAID_LOOT_FRACTION := 0.25         # доля запаса каждого ресурса
const RAID_LOOT_MAX := 40
const RAID_HURT := 0.35                  # потеря здоровья
const RAID_HURT_FLOOR := 0.15            # налёт не убивает
const RAID_INJURED_MAX := 2
const RAID_FAIL_REL := 0.0               # налёт не меняет отношения

## --- Защита ---
const FENCE_DEF := 0.4
const FENCE_MAX := 6
const TOWER_DEF := 1.5
const GUARD_DEF := 1.2
const GUARD_SHARE := [0.0, 0.05, 0.1, 0.2]   # доля взрослых по приоритету охраны 0..3
const GUARD_SLOTS_PER_POST := 2

## --- Люди ---
const LEFT_REL := 0.02                   # ушедший к соседям: отношения чуть выше
const ATTRACT_MIN := 0.55
const ATTRACT_FOOD_PER_POP := 8.0
const ARRIVE_BASE := 0.25                # вероятность в сутки при attract=1
const NEIGHBOUR_MIN_POP_TO_GIVE := 6


static func rel_word(r: float) -> String:
	for e in REL_NAMES:
		if r < float(e[0]):
			return String(e[1])
	return "союз"


static func value_of(res: StringName) -> float:
	return float(BASE_VALUE.get(res, 1.0))
