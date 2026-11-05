class_name Recipes
extends RefCounted
## Каталог одношаговых рецептов производственных зданий. Только данные.
## Весь баланс (плейсхолдеры) — в константах ниже.

## Скорость работы здания: игровых секунд рецепта за секунду симуляции.
## Плейсхолдер: позже её будет задавать число работников (жители).
const WORKER_RATE := 1.0

## Ремонт в мастерской (плейсхолдеры).
const REPAIR_STEP_TIME := 10.0                 # секунд работы на один шаг ремонта
const REPAIR_STEP_GAIN := 0.1                  # прирост состояния за шаг
const REPAIR_STEP_COST := {&"spare_parts": 1}  # цена шага (по умолчанию)
const REPAIR_BUILDING := &"workshop"

# id: [здание, название, вход, выход, время цикла (с)]
const _DEFS := {
	&"sawmill_planks": [&"sawmill", "Доски из бревён", {&"logs": 2}, {&"planks": 3}, 20.0],
	&"oil_press_oil": [&"oil_press", "Масло из рапса", {&"rapeseed": 3}, {&"oil": 1}, 30.0],
	&"workshop_parts": [&"workshop", "Запчасти из металлолома", {&"scrap_metal": 2}, {&"spare_parts": 1}, 40.0],
}


static func exists(id: StringName) -> bool:
	return _DEFS.has(id)


static func building_of(id: StringName) -> StringName:
	return _DEFS[id][0] if _DEFS.has(id) else &""


static func display_name(id: StringName) -> String:
	return _DEFS[id][1] if _DEFS.has(id) else String(id)


static func inputs(id: StringName) -> Dictionary:
	return (_DEFS[id][2] as Dictionary).duplicate() if _DEFS.has(id) else {}


static func outputs(id: StringName) -> Dictionary:
	return (_DEFS[id][3] as Dictionary).duplicate() if _DEFS.has(id) else {}


static func duration(id: StringName) -> float:
	return float(_DEFS[id][4]) if _DEFS.has(id) else 0.0


## Рецепты здания данного типа (порядок объявления).
static func for_building(type: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _DEFS:
		if _DEFS[k][0] == type:
			out.append(k)
	return out


static func is_production(type: StringName) -> bool:
	return not for_building(type).is_empty()


static func can_repair(type: StringName) -> bool:
	return type == REPAIR_BUILDING
