class_name TaskDefs
extends RefCounted
## Категории задач и ВЕСЬ баланс работы жителей (плейсхолдеры) — одно место.
## Приоритет категории (0 выкл .. 3 высокий) задаёт игрок; жители выбирают сами.

const BUILD := &"build"            # стройка (стадии)
const FELL := &"fell"              # вырубка
const DISMANTLE := &"dismantle"    # разбор руин
const PRODUCTION := &"production"  # слот работника в производственном здании
const CHORES := &"chores"          # повседневные дела (дрова)
## Только для черт/профессий: ремонт в мастерской (приоритет — в PRODUCTION).
const REPAIR := &"repair"
## Step 16 (food): field work, hunting, fishing, gathering, greenhouse.
const FIELD := &"field"
const HUNT := &"hunt"
const FISH := &"fish"
const FORAGE := &"forage"
const GREENHOUSE := &"greenhouse"
## Step 17 (land restoration): planting saplings, treating poisoned land.
const PLANT := &"plant"
const HEAL_LAND := &"heal_land"
## Step 18 (vehicles): driving (design/gdd/vehicles.md).
const DRIVE := &"drive"

const CATEGORIES: Array[StringName] = [BUILD, FELL, DISMANTLE, PRODUCTION, CHORES, FIELD, HUNT, FISH, FORAGE, GREENHOUSE, PLANT, HEAL_LAND, DRIVE]
const WORK_CATEGORIES: Array[StringName] = [BUILD, FELL, DISMANTLE, PRODUCTION, REPAIR, CHORES, FIELD, HUNT, FISH, FORAGE, GREENHOUSE, PLANT, HEAL_LAND, DRIVE]
const NAMES := {
	BUILD: "Стройка", FELL: "Вырубка", DISMANTLE: "Разбор",
	PRODUCTION: "Производство", CHORES: "Повседневные дела", REPAIR: "Ремонт",
	FIELD: "Поле", HUNT: "Охота", FISH: "Рыбалка", FORAGE: "Сбор", GREENHOUSE: "Теплица", PLANT: "Посадка", HEAL_LAND: "Лечение земли", DRIVE: "Вождение",
}

const PRIORITY_MIN := 0
const PRIORITY_MAX := 3
const DEFAULT_PRIORITY := {BUILD: 2, FELL: 2, DISMANTLE: 2, PRODUCTION: 2, CHORES: 1,
	FIELD: 2, HUNT: 1, FISH: 1, FORAGE: 1, GREENHOUSE: 2, PLANT: 1, HEAL_LAND: 1, DRIVE: 2}
const PRIORITY_NAMES: Array[String] = ["выкл", "низкий", "средний", "высокий"]

## --- Выбор задачи: score = приоритет*W + (множитель пригодности-1)*W - расстояние*W ---
const PRIORITY_WEIGHT := 10.0
const SUITABILITY_WEIGHT := 6.0
const DISTANCE_WEIGHT := 0.04      # за метр
const STICKY_BONUS := 3.0          # бонус текущей задаче (против дёрганья)
const ASSIGN_INTERVAL := 1.0       # как часто житель пересматривает задачу, игр. с
const JOB_CACHE_TICKS := 5         # возраст списка задач, тиков
const BAN_TIME := 30.0             # сколько не ходить к недостижимой цели, игр. с

## --- Скорость работы (работа/с жителя до модификаторов) ---
const BASE_RATE := {
	BUILD: BuildingDefs.BUILD_RATE, FELL: BuildingDefs.BUILD_RATE,
	DISMANTLE: BuildingDefs.BUILD_RATE, PRODUCTION: Recipes.WORKER_RATE,
	REPAIR: Recipes.WORKER_RATE, CHORES: 1.0,
	FIELD: 1.0, HUNT: 1.0, FISH: 1.0, FORAGE: 1.0, GREENHOUSE: 1.0, PLANT: 1.0, HEAL_LAND: 1.0, DRIVE: 1.0,
}
## Профессия, подходящая задаче -> множитель скорости. Нет в таблице — 1.0.
const PROFESSION_BONUS := {
	BUILD: {&"builder": 1.5, &"carpenter": 1.25},
	FELL: {&"carpenter": 1.5, &"hunter": 1.15},
	DISMANTLE: {&"builder": 1.3, &"mechanic": 1.25},
	REPAIR: {&"mechanic": 1.5},
	FIELD: {&"farmer": 1.5}, GREENHOUSE: {&"farmer": 1.5}, PLANT: {&"farmer": 1.25}, HEAL_LAND: {&"farmer": 1.25},
	HUNT: {&"hunter": 1.5}, FISH: {&"fisher": 1.5}, DRIVE: {&"driver": 1.5},
}
## Производство: профессия, подходящая зданию (множитель PRODUCTION_MATCH_BONUS).
const PRODUCTION_PROFESSION := {&"sawmill": &"carpenter", &"oil_press": &"farmer", &"workshop": &"mechanic", &"biodiesel_plant": &"mechanic", &"distillery": &"farmer", &"biogas_plant": &"farmer"}
const PRODUCTION_MATCH_BONUS := 1.5
const MIN_RATE_MULT := 0.2         # пол суммарного множителя черт

## --- Слоты: сколько жителей одновременно на объекте ---
const BUILD_SLOTS := 3
const FELL_SLOTS := 2
const DISMANTLE_SLOTS := 2
const PRODUCTION_SLOTS := 1
const CHORE_SLOTS := 1
const FOOD_SLOTS := 1                  # one villager per field cell / herd / fishing spot / greenhouse job

## --- Повседневные дела: дрова ---
const CHOP_WORK := 4.0                 # работа на колку одного бревна (у колоды во дворе)
const FIREWOOD_PER_LOG := 2
const CHORE_LOGS_RESERVE := 10         # бревна ниже этого запаса на дрова не идут
const CHOP_LOGS_PER_TRIP := 3          # брёвен за ходку со склада к колоде
const CARRY_CAPACITY := 6              # единиц за ходку в руках/корзине (охапка дров, корзина овощей, еда)
const PICKUP_WORK := 1.5               # работа на погрузку у склада
const DELIVER_WORK := 1.5              # работа на выгрузку (поленница, печь, дом, столовая)
const CANTEEN_COOK_BONUS := 1.5        # повар быстрее носит еду и воду в столовую
const ARRIVE_RADIUS_HUB := 5.0         # новичок «пришёл» на этом расстоянии от центра
