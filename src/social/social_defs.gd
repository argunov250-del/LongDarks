class_name SocialDefs
extends RefCounted
## Психика жителей (шаг 22), design/gdd/mental-needs.md: ВЕСЬ баланс (плейсхолдеры) — одно место.
## Психические потребности 0..1 (1 — всё хорошо): общение, семья, надежда (смысл), развлечения.
## Скорости заданы «за игровые сутки» (как в NeedsDefs).

const SOCIAL := &"social"   # общение и дружба
const FAMILY := &"family"   # семья и дети (шаг 23; пока нейтрально, хук set_family)
const HOPE := &"hope"       # смысл и надежда
const FUN := &"fun"         # развлечения (музыка, праздники, баня)
const NEEDS: Array[StringName] = [SOCIAL, FAMILY, HOPE, FUN]
const NAMES := {SOCIAL: "Общение", FAMILY: "Семья", HOPE: "Надежда", FUN: "Досуг"}

# ---------- старт ----------
const START := {SOCIAL: 0.7, FAMILY: 0.7, HOPE: 0.6, FUN: 0.6}
const HERO_START := {SOCIAL: 0.8, FAMILY: 0.7, HOPE: 0.8, FUN: 0.7}
const FAMILY_NEUTRAL := 0.7        # без семьи потребность стоит на месте и настроение не портит

# ---------- настроение ----------
const MOOD_WEIGHTS := {SOCIAL: 0.30, FAMILY: 0.15, HOPE: 0.35, FUN: 0.20}
const PHYSICAL_WEIGHT := 0.4       # настроение -= это * NeedsDefs.suffering(v)
const MOOD_CONTENT := 0.75         # «довольный» и выше
const MOOD_CALM := 0.55            # «спокойный»
const MOOD_TIRED := 0.40           # «уставший душой»
const MOOD_LOW := 0.25             # «подавленный»; ниже — «отчаявшийся»
const MOOD_WORDS := {&"content": "довольный", &"calm": "спокойный", &"tired": "уставший душой", &"low": "подавленный", &"despair": "отчаявшийся"}

# ---------- убыль и восстановление (за сутки) ----------
const SOCIAL_DECAY_PER_DAY := 0.35
const FUN_DECAY_PER_DAY := 0.30
const HOPE_DECAY_PER_DAY := 0.05   # без поводов надежда медленно тает
const STEP := 1.0                  # шаг расчёта психики, игр. с

# ---------- общение ----------
const TALK_BELOW := 0.5            # ниже — идёт поговорить в свободное время
const TALK_DONE := 0.85
const TALK_RADIUS := 2.2
const TALK_SOCIAL_PER_DAY := 3.0
const WORK_SOCIAL_PER_DAY := 0.15  # рядом на одной работе
const MEAL_SOCIAL_PER_DAY := 0.6   # общая трапеза в столовой (хук NeedsDefs.HOOK_SHARED_MEAL)
const MEAL_FUN_PER_DAY := 0.3

# ---------- дружба -1..1 ----------
const FRIEND_AT := 0.5             # «друзья»
const HOSTILE_AT := -0.3           # «в ссоре» (избегают, чаще ссорятся)
const FRIEND_WORK_PER_DAY := 1.0   # вместе работают
const FRIEND_MEAL_PER_DAY := 2.0   # вместе едят в столовой
const FRIEND_TALK_PER_DAY := 3.0
const FRIEND_CLUB_PER_DAY := 1.5
const FRIEND_PARTY_PER_DAY := 3.0
const FRIEND_DECAY_PER_DAY := 0.03 # положительная дружба без встреч остывает
const FRIEND_LIST_MAX := 3
## Черты: множитель роста дружбы (только существующие черты TraitDefs).
const TRAIT_FRIEND_MULT := {&"loner": 0.5, &"diligent": 1.25, &"clever": 1.1}
## Черты: множитель шанса ссоры.
const TRAIT_QUARREL_MULT := {&"loner": 0.7, &"lazy": 1.3, &"absentminded": 1.2, &"hardy": 0.8}
## Черты: множитель убыли общения (нелюдимому нужно меньше компании).
const TRAIT_SOCIAL_DECAY_MULT := {&"loner": 0.5}

# ---------- ссоры ----------
const QUARREL_MOOD_BELOW := 0.45   # ссорятся только при плохом настроении
const QUARREL_PER_DAY := 1.5       # шанс в сутки при настроении 0 (растёт от 1× на пороге до 2×)
const QUARREL_ROLL := 10.0         # интервал броска, игр. с
const QUARREL_RADIUS := 8.0        # ссорятся с тем, кто рядом
const QUARREL_COOLDOWN_DAYS := 0.3
const QUARREL_DROP := 0.25         # дружба пары -= это
const QUARREL_SOCIAL_LOSS := 0.1
const HOSTILE_QUARREL_MULT := 1.5

# ---------- работа и болезнь ----------
const MOOD_RATE_BELOW := 0.5       # ниже — работают медленнее
const MOOD_RATE_FLOOR := 0.6       # множитель при настроении 0
const MOOD_SICK_FLOOR := 0.5       # ниже — растёт шанс заболеть
const MOOD_SICK_WEIGHT := 0.15     # + к шансу заболеть в сутки при настроении 0

# ---------- смысл ----------
const MEANING_SKILL := 0.4         # навык не ниже — работа «по делу» даже без профессии
const MEANING_MATCH_PER_DAY := 0.25
const MEANING_WORK_PER_DAY := 0.08
const IDLE_GRACE_DAYS := 0.2       # без дела дольше этого — надежда падает
const IDLE_HOPE_LOSS_PER_DAY := 0.25

# ---------- надежда от событий ----------
const HOPE_FIRST_BIRDS := 0.35
const HOPE_WARMING_MILESTONE := 0.25
const HOPE_NEWCOMER := 0.05        # приход нового выжившего: всем немного легче
const HOPE_HOLIDAY := 0.15         # участникам праздника

# ---------- клуб ----------
const CLUB_START_HOUR := 17.0      # музыкальные вечера
const CLUB_END_HOUR := 21.0
const CLUB_GO_BELOW := 0.8         # fun ниже — идёт в клуб
const CLUB_STAY_UNTIL := 0.95
const CLUB_MIN_REST := 0.3
const CLUB_CAPACITY := 12
const CLUB_FUN_PER_DAY := 4.0
const CLUB_SOCIAL_PER_DAY := 2.0

# ---------- баня ----------
const BATH_TIME := 25.0            # игр. с
const BATH_MOOD_BELOW := 0.65      # или здоровье ниже BATH_HEALTH_BELOW
const BATH_HEALTH_BELOW := 0.8
const BATH_HEALTH := 0.10
const BATH_FUN := 0.30
const BATH_WARMTH := 0.30
const BATH_COOLDOWN_DAYS := 1.0
const BATH_CAPACITY := 4

# ---------- праздники ----------
const HOLIDAY_START_HOUR := 15.0
const HOLIDAY_HOURS := 4.0
const HOLIDAY_FUN_PER_DAY := 6.0
const HOLIDAY_SOCIAL_PER_DAY := 4.0
const HOLIDAY_FOOD_PER_VILLAGER := 0.5   # единиц еды со складов
const HOLIDAY_NO_FOOD_MULT := 0.5        # без угощения эффект вдвое слабее
const CALL_COOLDOWN_DAYS := 3.0          # праздник по просьбе игрока из клуба
const PARTY_RADIUS := 3.5                # вокруг клуба/центра
## id: [название, сезон, день сезона (1..; -1 — последний; 0 — середина)]
const HOLIDAYS := {
	&"harvest": ["Праздник урожая", SeasonDefs.AUTUMN, -1],
	&"spring": ["Первый день весны", SeasonDefs.SPRING, 1],
	&"new_year": ["Новый год", SeasonDefs.WINTER, 0],
	&"called": ["Праздник в клубе", &"", 0],
}

# ---------- уход ----------
const LEAVE_MOOD := 0.2
const LEAVE_AFTER_DAYS := 2.0      # столько суток подряд в отчаянии — уходит
const LEAVE_RECOVER_MULT := 2.0    # выздоровление счётчика быстрее набора
const LEAVE_MAX_SECONDS := 900.0   # не дошёл до края — исчезает
const LEAVE_REACH := 1.5


static func mood_key(m: float) -> StringName:
	if m >= MOOD_CONTENT:
		return &"content"
	if m >= MOOD_CALM:
		return &"calm"
	if m >= MOOD_TIRED:
		return &"tired"
	if m >= MOOD_LOW:
		return &"low"
	return &"despair"


static func mood_word(m: float) -> String:
	return MOOD_WORDS[mood_key(m)]


static func bar(x: float, cells: int = 10) -> String:
	return NeedsDefs.bar(x, cells)


## Множитель скорости работы от настроения (1.0 при настроении не ниже MOOD_RATE_BELOW).
static func rate_multiplier(mood: float) -> float:
	return lerpf(MOOD_RATE_FLOOR, 1.0, clampf(mood / MOOD_RATE_BELOW, 0.0, 1.0))


## Добавка к шансу заболеть в сутки от плохого настроения.
static func sick_bonus(mood: float) -> float:
	var d := maxf(0.0, MOOD_SICK_FLOOR - mood) / MOOD_SICK_FLOOR
	return MOOD_SICK_WEIGHT * d * d


static func trait_mult(table: Dictionary, traits: Array) -> float:
	var m := 1.0
	for t in traits:
		m *= float(table.get(t, 1.0))
	return m


static func pair_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]
