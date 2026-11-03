class_name ResourceDefs
extends RefCounted
## Каталог ресурсов. Только данные: id, название, категория, порча.

enum Category { RAW, FOOD, FUEL, PART }

## Плейсхолдеры баланса: доля запаса, портящаяся за игровые сутки.
const SPOIL_PER_DAY_FRESH := 0.30   # молоко, яйца, мясо, рыба
const SPOIL_PER_DAY_MEDIUM := 0.10  # грибы
const SPOIL_PER_DAY_SLOW := 0.02    # зерно, картофель, рапс

const _DEFS := {
	# сырьё
	&"logs": ["бревно", Category.RAW, 0.0],
	&"planks": ["доски", Category.RAW, 0.0],
	&"stone": ["камень", Category.RAW, 0.0],
	&"clay": ["глина", Category.RAW, 0.0],
	&"scrap_metal": ["металлолом", Category.RAW, 0.0],
	&"coal": ["уголь", Category.RAW, 0.0],
	&"peat": ["торф", Category.RAW, 0.0],
	&"sand": ["песок", Category.RAW, 0.0],
	&"lime": ["известь", Category.RAW, 0.0],
	&"cement": ["цемент", Category.RAW, 0.0],
	# еда
	&"grain": ["зерно", Category.FOOD, SPOIL_PER_DAY_SLOW],
	&"potato": ["картофель", Category.FOOD, SPOIL_PER_DAY_SLOW],
	&"rapeseed": ["рапс", Category.FOOD, SPOIL_PER_DAY_SLOW],
	&"meat": ["мясо", Category.FOOD, SPOIL_PER_DAY_FRESH],
	&"fish": ["рыба", Category.FOOD, SPOIL_PER_DAY_FRESH],
	&"mushrooms": ["грибы", Category.FOOD, SPOIL_PER_DAY_MEDIUM],
	&"milk": ["молоко", Category.FOOD, SPOIL_PER_DAY_FRESH],
	&"eggs": ["яйца", Category.FOOD, SPOIL_PER_DAY_FRESH],
	# топливо
	&"firewood": ["дрова", Category.FUEL, 0.0],
	&"oil": ["масло", Category.FUEL, 0.0],
	&"biodiesel": ["биодизель", Category.FUEL, 0.0],
	&"alcohol": ["спирт", Category.FUEL, 0.0],
	&"biogas": ["биогаз", Category.FUEL, 0.0],
	# детали
	&"spare_parts": ["запчасти", Category.PART, 0.0],
}


static func all_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _DEFS:
		out.append(k)
	return out


static func exists(id: StringName) -> bool:
	return _DEFS.has(id)


static func display_name(id: StringName) -> String:
	return _DEFS[id][0] if _DEFS.has(id) else String(id)


static func category(id: StringName) -> int:
	return _DEFS[id][1] if _DEFS.has(id) else Category.RAW


## Доля запаса, портящаяся за игровые сутки (0 — не портится).
static func spoil_rate(id: StringName) -> float:
	return _DEFS[id][2] if _DEFS.has(id) else 0.0


static func is_perishable(id: StringName) -> bool:
	return spoil_rate(id) > 0.0


static func ids_in_category(cat: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _DEFS:
		if _DEFS[k][1] == cat:
			out.append(k)
	return out
