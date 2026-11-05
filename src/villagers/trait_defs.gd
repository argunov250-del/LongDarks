class_name TraitDefs
extends RefCounted
## ЕДИНАЯ таблица черт. Черта меняет скорость работы по категориям задач
## (TaskDefs.WORK_CATEGORIES): +0.3 = на 30% быстрее, -0.3 = на 30% медленнее.
## Суммируется по всем чертам жителя; пол — TaskDefs.MIN_RATE_MULT.
## Черты нужны, чтобы игрок видел, кого куда ставить (хорошие — зелёные, плохие — красные).

const B := TaskDefs.BUILD
const F := TaskDefs.FELL
const D := TaskDefs.DISMANTLE
const P := TaskDefs.PRODUCTION
const R := TaskDefs.REPAIR
const C := TaskDefs.CHORES

# id: [название, хорошая?, {категория: поправка}]
const _DEFS := {
	&"strong": ["сильный", true, {B: 0.3, F: 0.3, D: 0.2}],
	&"careful": ["аккуратный", true, {P: 0.2, R: 0.3}],
	&"hardy": ["выносливый", true, {B: 0.1, F: 0.1, D: 0.1, P: 0.1, C: 0.1}],
	&"diligent": ["трудолюбивый", true, {B: 0.2, F: 0.2, D: 0.2, P: 0.2, R: 0.2, C: 0.2}],
	&"nimble": ["расторопный", true, {C: 0.3, P: 0.1}],
	&"clever": ["смекалистый", true, {R: 0.3, P: 0.15}],
	&"handy": ["рукастый", true, {B: 0.2, R: 0.2}],
	&"lazy": ["ленивый", false, {B: -0.3, F: -0.3, D: -0.3, P: -0.3, R: -0.3, C: -0.3}],
	&"clumsy": ["неуклюжий", false, {R: -0.4, P: -0.1}],
	&"absentminded": ["рассеянный", false, {P: -0.25, R: -0.25, B: -0.1}],
	&"loner": ["нелюдимый", false, {B: -0.15, P: -0.1}],
	&"weak": ["слабый", false, {B: -0.25, F: -0.3, D: -0.2}],
	&"sluggish": ["медлительный", false, {C: -0.3, F: -0.1}],
}

## Несовместимые пары (не выпадают вместе).
const EXCLUSIVE: Array = [
	[&"strong", &"weak"], [&"lazy", &"diligent"], [&"lazy", &"hardy"],
	[&"nimble", &"sluggish"], [&"careful", &"clumsy"], [&"careful", &"absentminded"],
]


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _DEFS:
		out.append(k)
	return out


static func exists(id: StringName) -> bool:
	return _DEFS.has(id)


static func display_name(id: StringName) -> String:
	return _DEFS[id][0] if _DEFS.has(id) else String(id)


static func is_good(id: StringName) -> bool:
	return _DEFS.has(id) and _DEFS[id][1]


static func modifiers(id: StringName) -> Dictionary:
	return (_DEFS[id][2] as Dictionary).duplicate() if _DEFS.has(id) else {}


static func are_exclusive(a: StringName, b: StringName) -> bool:
	for p in EXCLUSIVE:
		if (p[0] == a and p[1] == b) or (p[0] == b and p[1] == a):
			return true
	return false


## Множитель скорости работы категории от набора черт.
static func rate_multiplier(trait_ids: Array, category: StringName) -> float:
	var sum := 0.0
	for t in trait_ids:
		if _DEFS.has(t):
			sum += _DEFS[t][2].get(category, 0.0)
	return maxf(TaskDefs.MIN_RATE_MULT, 1.0 + sum)
