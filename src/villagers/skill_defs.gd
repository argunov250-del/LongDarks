class_name SkillDefs
extends RefCounted
## ВЕСЬ баланс навыков жителей (плейсхолдеры) — одно место.
## Навык хранится по категориям работы (TaskDefs.WORK_CATEGORIES, включая ремонт), 0..1.
## Растёт от времени реальной работы в категории: dS = GAIN_RATE * (1-S)^DIMINISH * учёба * dt.
## Обучение: если на том же объекте работает житель с навыком выше на TEACH_GAP и более,
## ученик учится в TEACH_BONUS раз быстрее. Учитель НЕ замедляется (проще и честнее:
## наставничество ничего не стоит, но требует, чтобы мастер был рядом).

const MAX_SKILL := 1.0
const BASE_SKILL := 0.1            # стартовый навык во всех категориях

## Рост: скорость при навыке 0 (навык/с работы). 0.0002 -> ~0.5 за ~1 ч работы.
const GAIN_RATE := 0.0002
const DIMINISH_EXP := 2.0          # затухание (1-S)^exp: чем выше навык, тем медленнее рост

## Множитель скорости работы: MIN при навыке 0, MAX при навыке 1 (линейно).
const RATE_MULT_MIN := 0.75
const RATE_MULT_MAX := 1.5

## Обучение вместе
const TEACH_GAP := 0.2             # на сколько учитель должен быть сильнее
const TEACH_BONUS := 1.75          # множитель роста ученика

## Минимальный множитель скорости учёбы от черт (TraitDefs.LEARN)
const MIN_LEARN_MULT := 0.3

## Стартовый уровень профессии по категориям (остальные — BASE_SKILL).
const PROFESSION_START := {
	&"mechanic": {TaskDefs.REPAIR: 0.5, TaskDefs.PRODUCTION: 0.35, TaskDefs.DISMANTLE: 0.3},
	&"doctor": {TaskDefs.CHORES: 0.25},
	&"farmer": {TaskDefs.PRODUCTION: 0.3, TaskDefs.CHORES: 0.3, TaskDefs.FIELD: 0.4, TaskDefs.GREENHOUSE: 0.4},
	&"driver": {TaskDefs.CHORES: 0.25, TaskDefs.DISMANTLE: 0.2},
	&"builder": {TaskDefs.BUILD: 0.5, TaskDefs.DISMANTLE: 0.4},
	&"carpenter": {TaskDefs.FELL: 0.5, TaskDefs.BUILD: 0.35, TaskDefs.PRODUCTION: 0.3},
	&"hunter": {TaskDefs.FELL: 0.3, TaskDefs.CHORES: 0.2, TaskDefs.HUNT: 0.4},
	&"fisher": {TaskDefs.CHORES: 0.3, TaskDefs.FISH: 0.4},
	&"cook": {TaskDefs.CHORES: 0.4, TaskDefs.PRODUCTION: 0.2},
}


static func initial(profession: StringName) -> Dictionary:
	var out := {}
	var start: Dictionary = PROFESSION_START.get(profession, {})
	for c in TaskDefs.WORK_CATEGORIES:
		out[c] = maxf(BASE_SKILL, start.get(c, 0.0))
	return out


## Множитель скорости работы от навыка.
static func rate_multiplier(skill: float) -> float:
	return lerpf(RATE_MULT_MIN, RATE_MULT_MAX, clampf(skill, 0.0, MAX_SKILL))


## Прирост навыка за dt секунд работы. learn — множитель учёбы (черты), teach — обучение.
static func gain(skill: float, dt: float, learn: float = 1.0, teach: float = 1.0) -> float:
	var s := clampf(skill, 0.0, MAX_SKILL)
	return GAIN_RATE * pow(1.0 - s / MAX_SKILL, DIMINISH_EXP) * learn * teach * dt


## Текстовая шкала навыка: «████░░░░░░».
static func bar(skill: float, cells: int = 10) -> String:
	var n := clampi(roundi(skill * cells), 0, cells)
	return "█".repeat(n) + "░".repeat(cells - n)


## Строки «Стройка  ████░░░░░░ 40%» по всем категориям.
static func card_lines(skills: Dictionary) -> String:
	var lines: Array[String] = []
	for c in TaskDefs.WORK_CATEGORIES:
		var s: float = skills.get(c, BASE_SKILL)
		lines.append("%s  %s %d%%" % [TaskDefs.NAMES[c], bar(s), roundi(s * 100.0)])
	return "\n".join(lines)
