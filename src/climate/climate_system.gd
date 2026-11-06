class_name ClimateSystem
extends SimSystem
## Потепление климата (шаг 15), design/gdd/climate-warming.md. Индекс потепления (°C) растёт в конце
## каждого сезона; ускоряют посаженный лес и вспаханная почва. Вырубка леса НЕ охлаждает — убирает
## только бонус (потепление никогда не падает). Управляет SeasonSystem: длительности сезонов
## (зима короче, год постоянный), добавка к температуре, раннее таяние снега. Без UI и шкалы.
## События для будущей системы надежды: first_birds, warming_milestone.
## Посадка и вспашка появятся в шагах 16-17: register_planted_forest_cells / set_plowed_cells
## или провайдеры-колбэки (set_planted_provider / set_plowed_provider).

const TOPIC_FIRST_BIRDS := &"first_birds"                  # {"year", "warming"}
const TOPIC_WARMING_MILESTONE := &"warming_milestone"      # {"level", "warming", "year"}

var seasons: SeasonSystem
var _sim: Simulation
var _warming: float = 0.0
var _planted_cells: int = 0
var _plowed_cells: int = 0
var _planted_provider: Callable = Callable()
var _plowed_provider: Callable = Callable()
var _first_birds: bool = false
## Шаг 17: восстановление земли 0..1 (задаёт RestorationSystem) — больше птиц.
var land_recovery: float = 0.0
var _milestones_done: int = 0


func attach(sim: Simulation) -> void:
	_sim = sim
	sim.bus.subscribe(SeasonSystem.TOPIC_SEASON_CHANGED, _on_season_changed)


func bind(seasons_in: SeasonSystem) -> void:
	seasons = seasons_in
	apply_to_seasons()


# ---------- API бонусов (шаги 16-17) ----------

## Добавляет n посаженных/выросших клеток леса (отрицательное n — вырублено). Природный лес на старте не считается.
func register_planted_forest_cells(n: int) -> void:
	_planted_cells = maxi(0, _planted_cells + n)


func set_planted_forest_cells(n: int) -> void:
	_planted_cells = maxi(0, n)


func set_plowed_cells(n: int) -> void:
	_plowed_cells = maxi(0, n)


## Провайдеры вместо ручных счётчиков: Callable() -> int, опрашиваются в конце сезона.
func set_planted_provider(cb: Callable) -> void:
	_planted_provider = cb


func set_plowed_provider(cb: Callable) -> void:
	_plowed_provider = cb


func planted_forest_cells() -> int:
	if _planted_provider.is_valid():
		return maxi(0, int(_planted_provider.call()))
	return _planted_cells


func plowed_cells() -> int:
	if _plowed_provider.is_valid():
		return maxi(0, int(_plowed_provider.call()))
	return _plowed_cells


# ---------- расчёт ----------

## Бонус ускорения (доля к базе, >= 0) от существующего посаженного леса и вспаханной земли.
func acceleration_bonus() -> float:
	var f := minf(ClimateDefs.FOREST_BONUS_MAX, float(planted_forest_cells()) * ClimateDefs.FOREST_BONUS_PER_CELL)
	var p := minf(ClimateDefs.PLOW_BONUS_MAX, float(plowed_cells()) * ClimateDefs.PLOW_BONUS_PER_CELL)
	return maxf(0.0, f) + maxf(0.0, p)


## Потепление за год при текущих бонусах, °C.
func warming_per_year() -> float:
	return ClimateDefs.BASE_WARMING_PER_YEAR * (1.0 + acceleration_bonus())


func warming() -> float:
	return _warming


## Потепление 0..1 от предела.
func warm_fraction() -> float:
	return clampf(_warming / ClimateDefs.MAX_WARMING, 0.0, 1.0)


func temp_offset() -> float:
	return _warming * ClimateDefs.TEMP_PER_WARMING


func first_birds_seen() -> bool:
	return _first_birds


func milestones_reached() -> int:
	return _milestones_done


## Сколько птиц в мире весной (0 — пока не было первых птиц).
func bird_count() -> int:
	if not _first_birds:
		return 0
	var base := lerpf(float(ClimateDefs.BIRDS_MIN), float(ClimateDefs.BIRDS_MAX), warm_fraction())
	return roundi(base * (1.0 + ClimateDefs.BIRD_RECOVERY_BONUS * clampf(land_recovery, 0.0, 1.0)))


## Длительность сезона в реальных минутах при текущем потеплении (год постоянной длины).
static func season_minutes(season: StringName, warm: float) -> float:
	var f := clampf(warm, 0.0, 1.0)
	var w0: float = SeasonDefs.DEFAULT_MINUTES[SeasonDefs.WINTER]
	var freed := w0 * (1.0 - ClimateDefs.WINTER_MIN_FRACTION) * f
	var base: float = SeasonDefs.DEFAULT_MINUTES[season]
	match season:
		SeasonDefs.WINTER:
			return base - freed
		SeasonDefs.SPRING:
			return base + freed * ClimateDefs.SPRING_SHARE
		SeasonDefs.SUMMER:
			return base + freed * (1.0 - ClimateDefs.SPRING_SHARE)
	return base


## Применяет климат к календарю: температура, длительности сезонов, раннее таяние снега.
func apply_to_seasons() -> void:
	if seasons == null:
		return
	seasons.climate_temp_offset = temp_offset()
	seasons.climate_warm_fraction = warm_fraction()
	for s in SeasonDefs.ORDER:
		var m := season_minutes(s, warm_fraction())
		if absf(seasons.duration_minutes(s) - m) > 0.0001:
			seasons.set_duration_minutes(s, m)


## Первая весна игры: прилетают первые птицы (один раз, независимо от потепления).
func tick(_sim_in: Simulation, _dt: float) -> void:
	if not _first_birds and seasons != null and seasons.season() == SeasonDefs.SPRING:
		_first_birds = true
		_emit(TOPIC_FIRST_BIRDS, {"year": seasons.year(), "warming": _warming})


func _on_season_changed(_p: Dictionary) -> void:
	advance_season()


## Конец сезона: четверть годового потепления (не отрицательная), затем применение и события.
func advance_season() -> void:
	_warming = minf(ClimateDefs.MAX_WARMING, _warming + maxf(0.0, warming_per_year()) * 0.25)
	apply_to_seasons()
	_check_milestones()


func _check_milestones() -> void:
	var year := seasons.year() if seasons != null else 1
	while _milestones_done < ClimateDefs.MILESTONES.size() and _warming >= ClimateDefs.MILESTONES[_milestones_done] - 0.00001:
		_emit(TOPIC_WARMING_MILESTONE, {"level": ClimateDefs.MILESTONES[_milestones_done], "warming": _warming, "year": year})
		_milestones_done += 1


func _emit(topic: StringName, payload: Dictionary) -> void:
	if _sim != null:
		_sim.bus.emit(topic, payload)


# ---------- сохранение ----------

func get_save_key() -> StringName:
	return &"climate"


func save_state() -> Dictionary:
	return {"warming": _warming, "planted": _planted_cells, "plowed": _plowed_cells,
		"first_birds": _first_birds, "milestones": _milestones_done}


func load_state(d: Dictionary) -> void:
	_warming = clampf(float(d.get("warming", 0.0)), 0.0, ClimateDefs.MAX_WARMING)
	_planted_cells = maxi(0, SaveManager.to_int(d.get("planted"), 0))
	_plowed_cells = maxi(0, SaveManager.to_int(d.get("plowed"), 0))
	_first_birds = bool(d.get("first_birds", false))
	_milestones_done = clampi(SaveManager.to_int(d.get("milestones"), 0), 0, ClimateDefs.MILESTONES.size())
	apply_to_seasons()
