class_name SeasonSystem
extends SimSystem
## Календарь и климат (шаг 13). Год = весна, лето, осень, зима; длительности настраиваемы
## (ХУК потепления/сложности: set_duration_minutes). Время года копится из dt симуляции.
## Выставляет хуки других систем (bind): отопление, холод/расход, мерзлота, скорость стройки,
## распутица, порча еды. API: season(), progress(), day_of_season(), outdoor_temp().

const TOPIC_SEASON_CHANGED := &"season_changed"  # {"season", "previous", "year"}
const APPLY_INTERVAL := 1.0                       # как часто обновлять хуки, игр. с

var _durations: Dictionary = SeasonDefs.default_durations()  # сезон -> секунды
var _year_t: float = 0.0       # секунд от начала года (начало весны)
var _elapsed: float = 0.0      # секунд всего (для шума погоды)
var _year: int = 1
var _season: StringName = SeasonDefs.SPRING
var _sim: Simulation
var _acc: float = APPLY_INTERVAL

var economy: EconomySystem
var construction: ConstructionSystem
var villagers: VillagerSystem


func attach(sim: Simulation) -> void:
	_sim = sim


## Подключает системы, чьи хуки выставляет календарь.
func bind(economy_in: EconomySystem, construction_in: ConstructionSystem, villagers_in: VillagerSystem) -> void:
	economy = economy_in
	construction = construction_in
	villagers = villagers_in
	if villagers != null:
		villagers.household.seasons = self
	apply_hooks()


# ---------- календарь ----------

func year_length() -> float:
	var t := 0.0
	for s in SeasonDefs.ORDER:
		t += _durations[s]
	return t


func duration(season: StringName) -> float:
	return _durations.get(season, 0.0)


## ХУК потепления/сложности (шаг 15): новая длительность сезона в реальных минутах при 1x.
## Текущая доля года сохраняется по сезону (сезон не перескакивает).
func set_duration_minutes(season: StringName, minutes: float) -> void:
	if not _durations.has(season) or minutes <= 0.0:
		return
	var p := progress()
	_durations[season] = minutes * 60.0
	_set_position(_season, p)


func duration_minutes(season: StringName) -> float:
	return duration(season) / 60.0


func season_start(season: StringName) -> float:
	var t := 0.0
	for s in SeasonDefs.ORDER:
		if s == season:
			return t
		t += _durations[s]
	return t


func _season_at(year_t: float) -> StringName:
	var t := 0.0
	for s in SeasonDefs.ORDER:
		t += _durations[s]
		if year_t < t:
			return s
	return SeasonDefs.WINTER


func season() -> StringName:
	return _season


func season_name() -> String:
	return SeasonDefs.season_name(_season)


func season_index() -> int:
	return SeasonDefs.ORDER.find(_season)


func year() -> int:
	return _year


## Доля текущего сезона 0..1.
func progress() -> float:
	return clampf((_year_t - season_start(_season)) / maxf(duration(_season), 0.001), 0.0, 1.0)


func day_length() -> float:
	return _sim.clock.day_seconds() if _sim != null else GameClock.DEFAULT_DAY_LENGTH


## День внутри сезона, с 1.
func day_of_season() -> int:
	return int((_year_t - season_start(_season)) / day_length()) + 1


func days_in_season(season_id: StringName) -> int:
	return maxi(1, roundi(duration(season_id) / day_length()))


## Ставит календарь: сезон и доля сезона 0..1 (новая игра, тесты).
func start_at(season_id: StringName, p: float) -> void:
	_set_position(season_id, p)
	_elapsed = _year_t
	_acc = APPLY_INTERVAL
	apply_hooks()


func _set_position(season_id: StringName, p: float) -> void:
	_year_t = season_start(season_id) + clampf(p, 0.0, 0.999999) * duration(season_id)
	_season = _season_at(_year_t)


## Игровые секунды от начала года для (сезон, доля) — чтобы выставить часы.
func year_time_for(season_id: StringName, p: float) -> float:
	return season_start(season_id) + clampf(p, 0.0, 1.0) * duration(season_id)


# ---------- температура ----------

## Плавное значение между серединами сезонов: values — сезон -> float|Color, t — секунды года.
func blend(values: Dictionary, t: float = -1.0) -> Variant:
	if t < 0.0:
		t = _year_t
	var yl := year_length()
	var pts: Array = []   # [центр, значение]
	var cur := 0.0
	var centers: Array[float] = []
	for s in SeasonDefs.ORDER:
		centers.append(cur + _durations[s] * 0.5)
		cur += _durations[s]
	pts.append([centers[3] - yl, values[SeasonDefs.WINTER]])
	for i in 4:
		pts.append([centers[i], values[SeasonDefs.ORDER[i]]])
	pts.append([centers[0] + yl, values[SeasonDefs.SPRING]])
	for i in pts.size() - 1:
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		if t >= float(a[0]) and t <= float(b[0]):
			var f: float = (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			f = (1.0 - cos(f * PI)) * 0.5
			return lerp(a[1], b[1], f)
	return values[SeasonDefs.WINTER]


## Сезонная средняя температура (без суточных колебаний и шума).
func base_temp() -> float:
	return blend(SeasonDefs.SEASON_TEMP)


static func _hash_noise(n: int) -> float:
	var x := (n * 374761393 + SeasonDefs.NOISE_SEED * 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	x = x ^ (x >> 16)
	return float(x & 0xffff) / 32767.5 - 1.0


func weather_noise() -> float:
	var x := _elapsed / day_length() - 0.5
	var i := floori(x)
	var f := x - float(i)
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(_hash_noise(i), _hash_noise(i + 1), f) * SeasonDefs.NOISE_AMPLITUDE


func _hour() -> float:
	return _sim.clock.get_hour() if _sim != null else 12.0


## Час суток по часам симуляции (12 — без симуляции).
func hour() -> float:
	return _hour()


## Температура воздуха снаружи, °C: сезонная кривая + суточный размах + детерминированный шум.
func outdoor_temp() -> float:
	var swing: float = blend(SeasonDefs.DAY_SWING)
	var day := cos((_hour() - SeasonDefs.DAY_PEAK_HOUR) / 24.0 * TAU)
	return base_temp() + swing * day + weather_noise()


## Печи топят при +5 °C и ниже.
func heating_needed() -> bool:
	return outdoor_temp() <= SeasonDefs.HEATING_MAX_TEMP


## Земля промёрзла: зимой, пока сезонная средняя ниже порога.
func ground_frozen() -> bool:
	return _season == SeasonDefs.WINTER and base_temp() < SeasonDefs.FROST_BELOW


func build_speed_multiplier() -> float:
	var t := outdoor_temp()
	if t >= 0.0:
		return 1.0
	return lerpf(1.0, SeasonDefs.FROST_BUILD_MIN, clampf(t / SeasonDefs.FROST_BUILD_FULL_TEMP, 0.0, 1.0))


func consumption_multiplier() -> float:
	var k := clampf((SeasonDefs.CONSUMPTION_FROM_TEMP - base_temp()) / (SeasonDefs.CONSUMPTION_FROM_TEMP - SeasonDefs.CONSUMPTION_FULL_TEMP), 0.0, 1.0)
	return 1.0 + SeasonDefs.CONSUMPTION_WINTER_EXTRA * k


## Распутица 0..1 (весна). ХУК для техники: она будет вязнуть пропорционально.
func mud_level() -> float:
	if _season != SeasonDefs.SPRING:
		return 0.0
	var p := progress()
	var up := smoothstep(0.0, SeasonDefs.MUD_RAMP_IN, p)
	var down := 1.0 - smoothstep(SeasonDefs.MUD_PEAK_END, 1.0, p)
	return up * down


func walk_speed_multiplier() -> float:
	return 1.0 - SeasonDefs.MUD_WALK_SLOW * mud_level()


## Снежный покров 0..1 (визуал): зима 1, весной тает, осенью возвращается.
func snow_cover() -> float:
	var p := progress()
	match _season:
		SeasonDefs.WINTER:
			return 1.0
		SeasonDefs.SPRING:
			return 1.0 - smoothstep(SeasonDefs.SNOW_SPRING_MELT_FROM, SeasonDefs.SNOW_SPRING_MELT_TO, p)
		SeasonDefs.AUTUMN:
			return smoothstep(SeasonDefs.SNOW_AUTUMN_FROM, 1.0, p)
	return 0.0


# ---------- хуки других систем ----------

func apply_hooks() -> void:
	var temp := outdoor_temp()
	if villagers != null:
		var hs := villagers.household
		hs.heating_needed = temp <= SeasonDefs.HEATING_MAX_TEMP
		hs.outdoor_cold = SeasonDefs.cold_from_temp(temp)
		hs.consumption_multiplier = consumption_multiplier()
		villagers.mud_level = mud_level()
		villagers.walk_speed_multiplier = walk_speed_multiplier()
	if construction != null:
		construction.ground_frozen = ground_frozen()
		construction.build_speed_multiplier = build_speed_multiplier()
	if economy != null:
		economy.ambient_cold = temp < SeasonDefs.SPOIL_COLD_BELOW


# ---------- тик ----------

func tick(sim: Simulation, dt: float) -> void:
	_sim = sim
	if dt <= 0.0:
		return
	_elapsed += dt
	_year_t += dt
	var yl := year_length()
	while _year_t >= yl:
		_year_t -= yl
		_year += 1
	var s := _season_at(_year_t)
	if s != _season:
		var prev := _season
		_season = s
		sim.bus.emit(TOPIC_SEASON_CHANGED, {"season": s, "previous": prev, "year": _year})
	_acc += dt
	if _acc >= APPLY_INTERVAL:
		_acc = 0.0
		apply_hooks()


# ---------- сохранение ----------

func get_save_key() -> StringName:
	return &"seasons"


func save_state() -> Dictionary:
	var dur := {}
	for s in SeasonDefs.ORDER:
		dur[String(s)] = _durations[s]
	return {"year_t": _year_t, "elapsed": _elapsed, "year": _year, "durations": dur}


func load_state(d: Dictionary) -> void:
	if d.get("durations") is Dictionary:
		for s in SeasonDefs.ORDER:
			var v := float(d["durations"].get(String(s), _durations[s]))
			if v > 0.0:
				_durations[s] = v
	_year = maxi(1, SaveManager.to_int(d.get("year"), 1))
	_elapsed = maxf(0.0, float(d.get("elapsed", 0.0)))
	_year_t = fposmod(float(d.get("year_t", 0.0)), year_length())
	_season = _season_at(_year_t)
	_acc = APPLY_INTERVAL
	apply_hooks()
