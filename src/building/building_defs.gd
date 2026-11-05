class_name BuildingDefs
extends RefCounted
## Каталог зданий: только данные. Весь баланс (плейсхолдеры) — в константах ниже.

enum Stage { FOUNDATION, WALLS, ROOF, DONE }
enum Tab { HOUSING, PRODUCTION, SOCIAL, DEFENSE }

const STAGE_NAMES: Array[String] = ["Фундамент", "Стены", "Крыша", "Готово"]

## --- Плейсхолдеры баланса ---
const BUILD_RATE := 1.0               # единиц работы в секунду на стройку (потом — жители)
const MAX_SLOPE := 0.35               # макс. перепад высот / длинная сторона основания
const BUILD_GAP := 0.3                # зазор между зданиями, м
const MAP_MARGIN := 0.5               # отступ от края карты, м
const RESTORE_COST_FACTOR := 0.5      # восстановление руин: доля цены (вверх)
const RESTORE_WORK_FACTOR := 0.5      # и доля работы
const DISMANTLE_WORK := 20.0          # работа на разбор руины
const DISMANTLE_STONE_MIN := 1        # плюс случайно 0..2 по хешу клетки
const DISMANTLE_PLANKS_MIN := 0       # плюс случайно 0..2
const SALT_DISMANTLE_STONE := 301
const SALT_DISMANTLE_PLANKS := 302
const FELL_WORK_PER_LOG := 2.0        # работа на одно бревно (потом — жители)
const WAREHOUSE_CAPACITY := 400
const CELLAR_CAPACITY := 150

# id: [название, вкладка, размер(x,z) м, [цены стадий], [работа стадий], след. улучшение, высота стен, свойства]
# Цены стадий: фундамент / стены / крыша.
const _DEFS := {
	# жильё (цепочка улучшений)
	&"dugout": ["Землянка", Tab.HOUSING, Vector2(4, 4), [{&"logs": 2}, {&"logs": 4}, {&"logs": 2}], [8.0, 12.0, 8.0], &"izba", 1.4, {}],
	&"izba": ["Изба", Tab.HOUSING, Vector2(5, 5), [{&"stone": 3, &"logs": 2}, {&"logs": 8, &"planks": 2}, {&"planks": 6}], [12.0, 20.0, 14.0], &"stone_house", 2.4, {}],
	&"stone_house": ["Каменный дом", Tab.HOUSING, Vector2(6, 6), [{&"stone": 8}, {&"stone": 14, &"cement": 2}, {&"planks": 8, &"scrap_metal": 4}], [18.0, 30.0, 20.0], &"", 3.0, {}],
	# производство
	&"sawmill": ["Пилорама", Tab.PRODUCTION, Vector2(6, 4), [{&"stone": 3, &"logs": 2}, {&"logs": 6, &"planks": 2}, {&"planks": 4, &"scrap_metal": 4}], [12.0, 18.0, 12.0], &"", 2.2, {}],
	&"oil_press": ["Маслобойня", Tab.PRODUCTION, Vector2(4, 4), [{&"stone": 3}, {&"planks": 6, &"scrap_metal": 3}, {&"planks": 4}], [10.0, 16.0, 10.0], &"", 2.2, {}],
	&"workshop": ["Мастерская", Tab.PRODUCTION, Vector2(5, 4), [{&"stone": 4}, {&"planks": 6, &"scrap_metal": 6}, {&"planks": 5, &"scrap_metal": 4}], [12.0, 20.0, 14.0], &"", 2.4, {}],
	&"warehouse": ["Склад", Tab.PRODUCTION, Vector2(6, 5), [{&"logs": 3, &"stone": 2}, {&"planks": 8}, {&"planks": 6}], [10.0, 16.0, 10.0], &"", 2.2, {"storage": WAREHOUSE_CAPACITY}],
	&"cellar": ["Погреб", Tab.PRODUCTION, Vector2(4, 3), [{&"stone": 6}, {&"stone": 6, &"logs": 2}, {&"logs": 3}], [10.0, 12.0, 6.0], &"", 1.0, {"storage": CELLAR_CAPACITY, "cellar": true}],
	# социальные
	&"hospital": ["Больница", Tab.SOCIAL, Vector2(7, 5), [{&"stone": 6}, {&"planks": 10, &"stone": 8}, {&"planks": 8, &"spare_parts": 3}], [16.0, 28.0, 18.0], &"", 2.6, {}],
	&"school": ["Школа", Tab.SOCIAL, Vector2(6, 5), [{&"stone": 4}, {&"planks": 8, &"logs": 4}, {&"planks": 6}], [14.0, 22.0, 14.0], &"", 2.4, {}],
	&"club": ["Клуб", Tab.SOCIAL, Vector2(6, 5), [{&"stone": 4}, {&"planks": 8, &"logs": 4}, {&"planks": 6}], [14.0, 22.0, 14.0], &"", 2.4, {}],
	&"bathhouse": ["Баня", Tab.SOCIAL, Vector2(4, 4), [{&"stone": 3}, {&"logs": 8}, {&"planks": 4}], [10.0, 16.0, 10.0], &"", 2.0, {}],
	# защита
	&"fence": ["Забор", Tab.DEFENSE, Vector2(4, 0.6), [{&"logs": 1}, {&"planks": 2}, {}], [3.0, 5.0, 0.0], &"", 1.5, {}],
	&"watchtower": ["Вышка", Tab.DEFENSE, Vector2(2.5, 2.5), [{&"stone": 3}, {&"logs": 6, &"planks": 2}, {&"planks": 3}], [8.0, 16.0, 8.0], &"", 6.0, {}],
}

## Порядок показа внутри вкладки = порядок в _DEFS.


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _DEFS:
		out.append(k)
	return out


static func exists(id: StringName) -> bool:
	return _DEFS.has(id)


static func display_name(id: StringName) -> String:
	return _DEFS[id][0] if _DEFS.has(id) else String(id)


static func tab_of(id: StringName) -> int:
	return _DEFS[id][1]


static func ids_in_tab(tab: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _DEFS:
		if _DEFS[k][1] == tab:
			out.append(k)
	return out


static func footprint(id: StringName) -> Vector2:
	return _DEFS[id][2]


static func wall_height(id: StringName) -> float:
	return _DEFS[id][6]


## Цена стадии (FOUNDATION..ROOF) в целых; factor<1 — скидка (округление вверх).
static func stage_cost(id: StringName, stage: int, factor: float = 1.0) -> Dictionary:
	if not _DEFS.has(id) or stage < 0 or stage >= Stage.DONE:
		return {}
	var out := {}
	var src: Dictionary = _DEFS[id][3][stage]
	for k in src:
		var n := int(ceil(float(src[k]) * factor - 0.0001))
		if n > 0:
			out[k] = n
	return out


static func stage_work(id: StringName, stage: int, factor: float = 1.0) -> float:
	if not _DEFS.has(id) or stage < 0 or stage >= Stage.DONE:
		return 0.0
	return float(_DEFS[id][4][stage]) * factor


static func total_cost(id: StringName, factor: float = 1.0) -> Dictionary:
	var out := {}
	for s in Stage.DONE:
		var c := stage_cost(id, s, factor)
		for k in c:
			out[k] = out.get(k, 0) + c[k]
	return out


## Следующее здание цепочки улучшений или &"".
static func upgrade_of(id: StringName) -> StringName:
	return _DEFS[id][5] if _DEFS.has(id) else &""


## Типы, доступные как «восстановить из руин»: все, кроме верхних звеньев цепочки.
static func is_restorable(id: StringName) -> bool:
	return _DEFS.has(id) and id != &"izba" and id != &"stone_house"


## Номер звена в цепочке улучшений (0 — первое/не в цепочке).
static func upgrade_tier(id: StringName) -> int:
	var n := 0
	for k in _DEFS:
		if _DEFS[k][5] == id:
			n = upgrade_tier(k) + 1
	return n


static func storage_capacity(id: StringName) -> int:
	return _DEFS[id][7].get("storage", 0) if _DEFS.has(id) else 0


static func is_cellar(id: StringName) -> bool:
	return _DEFS.has(id) and _DEFS[id][7].get("cellar", false)
