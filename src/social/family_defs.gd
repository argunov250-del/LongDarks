class_name FamilyDefs
extends RefCounted
## Семья и дети (шаг 23), design/gdd/families.md: ВЕСЬ баланс (плейсхолдеры) — одно место.
## Время: «сутки» — игровые сутки. Детство ускорено (1 сутки = 1 год жизни), взрослая жизнь идёт по
## календарному году посёлка (ADULT_YEAR_DAYS суток на год возраста).

const INFANT := &"infant"   # младенец
const CHILD := &"child"     # ребёнок
const TEEN := &"teen"       # подросток
const ADULT := &"adult"     # взрослый
const STAGE_NAMES := {INFANT: "младенец", CHILD: "ребёнок", TEEN: "подросток", ADULT: "взрослый"}
const STAGE_NAMES_ELDER := "пожилой"
const INFANT_UNTIL := 3.0     # лет (рост в сутках = лет)
const CHILD_UNTIL := 12.0
const ADULT_AT_DAYS := 18.0   # взрослым становится в 18 «лет» = 18 игровых суток (~2.4 ч реального времени)
const ADULT_AGE := 18

# ---------- возраст взрослых ----------
const ADULT_YEAR_DAYS := 12.0   # суток на год возраста взрослого
const ELDER_AT := 60            # с этого возраста работают медленнее
const ELDER_FULL := 80          # к этому возрасту множитель падает до пола
const ELDER_WORK_FLOOR := 0.6
const DEATH_FROM := 70          # с этого возраста возможна естественная смерть
const DEATH_PER_YEAR_PER_AGE := 0.04   # шанс умереть за год = 0.04 * (возраст - 69)

# ---------- пары ----------
const COUPLE_FRIENDSHIP := 0.75  # дружба не ниже этого — могут стать парой
const COUPLE_MAX_AGE_GAP := 20
const COUPLE_RATE_PER_DAY := 0.6 # шанс в сутки для подходящей пары
const COUPLE_GRIEF_BELOW := 0.2  # овдовевший ждёт, пока горе утихнет
const HOPE_WEDDING := 0.10
const ROLL := 10.0               # интервал бросков семьи, игр. с
const STEP := 1.0

# ---------- беременность и рождение ----------
const CONCEIVE_RATE_PER_DAY := 0.15
const FERTILE_MAX_AGE := 45
const CONCEIVE_MIN_FOOD := 0.4
const CONCEIVE_MIN_HEALTH := 0.5
const MAX_CHILDREN := 4          # детей у пары (живых несовершеннолетних + выросших в посёлке)
const PREGNANCY_DAYS := 2.0
const POSTPARTUM_DAYS := 3.0
const BIRTH_COMPLICATION := 0.2
const COMPLICATION_DOCTOR_MULT := 0.4
const COMPLICATION_HOSPITAL_MULT := 0.5
const COMPLICATION_MOTHER_HEALTH := 0.35
const COMPLICATION_BABY_HEALTH := 0.6
const HOPE_BIRTH_MOTHER := 0.2
const HOPE_BIRTH_ALL := 0.05

# ---------- наследование ----------
const INHERIT_TRAIT_CHANCE := 0.4   # каждая черта родителя
const MAX_TRAITS := 3

# ---------- дети: потребности и забота ----------
const CONSUME_MULT := {INFANT: 0.4, CHILD: 0.6, TEEN: 0.85}   # еда и вода
const WARMTH_MULT := {INFANT: 1.3, CHILD: 1.15, TEEN: 1.0}    # скорость замерзания
const CARE_DECAY_PER_DAY := 0.6     # младенцам x CARE_INFANT_MULT
const CARE_INFANT_MULT := 1.5
const CARE_RESTORE_PER_DAY := 4.0   # рядом взрослый опекун или школа
const CARE_RADIUS := 4.0
const CARE_CALL := 0.35             # ниже — опекун бросает дела и идёт к ребёнку
const CARE_DONE := 0.8
const CARE_STUNT := 0.2             # ниже — рост вдвое медленнее
const STUNT_GROWTH_MULT := 0.5
const TEEN_WORK_MULT := 0.5         # подросток помогает только по хозяйству, вполсилы

# ---------- школа ----------
const SCHOOL_START_HOUR := 8.0
const SCHOOL_END_HOUR := 14.0
const SCHOOL_FULL_DAYS := 8.0       # суток в школе для полной пользы
const SCHOOL_BONUS_ALL := 0.10      # + ко всем навыкам при полной школе
const HOME_TRAINING_SHARE := 0.5    # без школы — только половина профессионального старта

# ---------- горе ----------
const GRIEF_PARTNER := 1.0
const GRIEF_CHILD := 1.0
const GRIEF_PARENT := 0.7
const GRIEF_SIBLING := 0.4
const GRIEF_DECAY_PER_DAY := 0.12
const GRIEF_NEED_WEIGHT := 0.7      # потребность семьи -= горе * вес
const GRIEF_MOOD_WEIGHT := 0.4      # настроение -= горе * вес

# ---------- потребность «семья» ----------
const NEED_PARTNER := 0.95
const NEED_PER_CHILD := 0.05
const NEED_ALONE := 0.7             # = SocialDefs.FAMILY_NEUTRAL: одиночке семья настроение не портит

const KINDS: Array[StringName] = [&"school", &"play", &"care"]


static func is_family_kind(kind: StringName) -> bool:
	return KINDS.has(kind)


static func stage_for_years(years: float) -> StringName:
	if years < INFANT_UNTIL:
		return INFANT
	if years < CHILD_UNTIL:
		return CHILD
	if years < ADULT_AT_DAYS:
		return TEEN
	return ADULT


## Масштаб фигурки по стадии.
static func body_scale(stage: StringName, growth: float) -> float:
	match stage:
		INFANT: return 0.45
		CHILD: return 0.6 + 0.15 * clampf((growth - INFANT_UNTIL) / (CHILD_UNTIL - INFANT_UNTIL), 0.0, 1.0)
		TEEN: return 0.85
	return 1.0


static func stage_label(v: Villager) -> String:
	if v.stage == ADULT and v.age >= ELDER_AT:
		return STAGE_NAMES_ELDER
	return STAGE_NAMES.get(v.stage, "")


## Множитель скорости работы от возраста взрослого (1 до ELDER_AT, линейно до пола к ELDER_FULL).
static func elder_multiplier(age: int) -> float:
	return lerpf(1.0, ELDER_WORK_FLOOR, clampf(float(age - ELDER_AT) / float(ELDER_FULL - ELDER_AT), 0.0, 1.0))


## Фамилия отца в нужной форме для ребёнка: «Иван Смирнов» -> «Смирнова» для девочки.
static func surname_for(father_name: String, sex: StringName) -> String:
	var last := father_name.get_slice(" ", father_name.get_slice_count(" ") - 1)
	for pair in VillagerDefs.SURNAMES:
		if pair[0] == last or pair[1] == last:
			return pair[0 if sex == &"m" else 1]
	return last
