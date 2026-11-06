class_name WeatherSystem
extends SimSystem
## Погодные события (шаг 14, GDD design/gdd/weather-events.md): метель, мороз, ливень, паводок, засуха,
## гроза, ураган. Планировщик детерминирован (хеш от seed симуляции, года, суток, id), события идут
## по одному: очередь (lead: собака тревожится) -> активно -> после (AFTER_TIME).
## Единственное предупреждение игроку — Dog.set_anxious. Эффекты — через хуки существующих систем:
## SeasonSystem.weather_* (температура, стройка, ходьба, грязь), HouseholdSystem (огород, колодцы,
## вода, укрытие и потери на улице), ConstructionSystem.flood_check + Pathfinder.set_blocked_cells
## (паводок), WeatherFire (пожар), fertility (плодородие выгоревших клеток).
## Тикать должна ПОСЛЕ SeasonSystem и ConstructionSystem; сохраняется в ключе "weather".

const TOPIC_STARTED := &"weather_event_started"   # {"id"}
const TOPIC_ENDED := &"weather_event_ended"       # {"id"}
const TOPIC_LIGHTNING := &"weather_lightning"     # {"cell": Vector2i}
const TOPIC_FIRE := &"weather_fire"               # события WeatherFire: {"type", ...}

var seasons: SeasonSystem
var construction: ConstructionSystem
var villagers: VillagerSystem
var world: WorldMap
var fire: WeatherFire
var flood: WeatherFlood
## Множитель частоты событий (ХУК сложности): 0 — события не планируются.
var frequency_multiplier: float = 1.0
## Плодородие: индекс клетки -> бонус 0..1 (разреженное, сохраняется).
var fertility: Dictionary = {}
var fertility_revision: int = 0
var cooldown_left: float = 0.0

var _sim: Simulation
var _queued: Dictionary = {}      # {"id","start_in","duration"} — ждёт старта
var _active: Dictionary = {}      # {"id","elapsed","duration"}
var _after: Dictionary = {}       # {"peak","left","id"}
var _rolled_day: int = 0
var _lightning_acc: float = 0.0
var _garden_after_left: float = 0.0
var _garden_after_mult: float = 1.0
var _flood_level_applied: float = -1.0
var _apply_acc: float = 1.0e9


func attach(sim: Simulation) -> void:
	_sim = sim


## Подключает системы и ставит хуки.
func bind(seasons_in: SeasonSystem, construction_in: ConstructionSystem, villagers_in: VillagerSystem) -> void:
	seasons = seasons_in
	construction = construction_in
	villagers = villagers_in
	world = construction.world
	fire = WeatherFire.new(world, construction)
	flood = WeatherFlood.new(world)
	construction.flood_check = Callable(self, "is_flooded_cell")
	if villagers != null:
		villagers.weather = self
		villagers.household.weather = self
	apply_hooks()


## Шина событий симуляции (визуал подписывается на молнии), null — без симуляции.
func bus() -> EventBus:
	return _sim.bus if _sim != null else null


func set_frequency_multiplier(x: float) -> void:
	frequency_multiplier = maxf(0.0, x)


# ---------- запросы ----------

func current_id() -> StringName:
	return _active.get("id", &"")


func queued_id() -> StringName:
	return _queued.get("id", &"")


## Секунд до старта поставленного в очередь события (-1 — очереди нет).
func time_to_start() -> float:
	return float(_queued["start_in"]) if not _queued.is_empty() else -1.0


func elapsed() -> float:
	return float(_active.get("elapsed", 0.0))


func is_active(id: StringName = &"") -> bool:
	return not _active.is_empty() and (id == &"" or _active["id"] == id)


func is_flooded_cell(c: Vector2i) -> bool:
	return flood != null and flood.is_flooded(c)


func flood_level() -> float:
	return flood.level if flood != null else 0.0


func fertility_at(c: Vector2i) -> float:
	if world == null or c.x < 0 or c.y < 0 or c.x >= world.size or c.y >= world.size:
		return 0.0
	return float(fertility.get(c.y * world.size + c.x, 0.0))


func set_fertility(c: Vector2i, v: float) -> void:
	var i := c.y * world.size + c.x
	if v <= 0.0:
		fertility.erase(i)
	else:
		fertility[i] = clampf(v, 0.0, WeatherDefs.FERTILITY_MAX)
	fertility_revision += 1


## ХУК техники (техники пока нет): вязкость 0..1 = max(событие, распутица).
func vehicle_stuck_multiplier() -> float:
	var s := WeatherDefs.f(current_id(), "stuck", 0.0) * _ramp() if is_active() else 0.0
	var mud := seasons.mud_level() if seasons != null else 0.0
	return maxf(s, mud)


## Доля «силы» события 0..1: нарастает за RAMP_IN, держится, гаснет за AFTER_TIME.
func _ramp() -> float:
	if not _active.is_empty():
		return clampf(float(_active["elapsed"]) / WeatherDefs.RAMP_IN, 0.0, 1.0)
	if not _after.is_empty():
		return clampf(float(_after["left"]) / WeatherDefs.AFTER_TIME, 0.0, 1.0)
	return 0.0


## Событие, определяющее вид (активное или только что закончившееся) и его сила для визуала.
func look_id() -> StringName:
	return _active["id"] if not _active.is_empty() else _after.get("id", &"")


func intensity() -> float:
	if _active.is_empty() and _after.is_empty():
		return 0.0
	if not _active.is_empty():
		return clampf(float(_active["elapsed"]) / WeatherDefs.FADE, 0.0, 1.0)
	return clampf(float(_after["left"]) / WeatherDefs.AFTER_TIME, 0.0, 1.0)


## Тревога собаки 0..1: максимум по очереди (линейно за lead), событию (пик) и «после» (спад).
func anxiety_level() -> float:
	var a := 0.0
	if not _queued.is_empty():
		var id: StringName = _queued["id"]
		var lead := WeatherDefs.f(id, "lead", 60.0)
		var left := float(_queued["start_in"])
		if left < lead:
			a = maxf(a, WeatherDefs.f(id, "peak", 0.5) * (1.0 - left / lead))
	if not _active.is_empty():
		a = maxf(a, WeatherDefs.f(_active["id"], "peak", 0.5))
	if not _after.is_empty():
		a = maxf(a, float(_after["peak"]) * float(_after["left"]) / WeatherDefs.AFTER_TIME)
	return a


# ---------- планировщик ----------

func _seed() -> int:
	return _sim.rng.seed if _sim != null else 0


## Бросок «будет ли событие id в эти сутки»: чистая функция от (seed, год, сутки, сезон, доля сезона).
static func roll(seed_value: int, year: int, day: int, id: StringName, season: StringName, p: float, days_in_season: int, mult: float) -> bool:
	var freq := WeatherDefs.freq_in(id, season, p)
	if freq <= 0.0 or mult <= 0.0:
		return false
	var chance := freq / float(maxi(1, days_in_season)) * mult
	return WeatherDefs.hash01(seed_value, year, day, id, WeatherDefs.SALT_ROLL) < chance


func _roll_day(day: int) -> void:
	if not _active.is_empty() or not _queued.is_empty() or cooldown_left > 0.0 or seasons == null:
		return
	var season := seasons.season()
	var p := seasons.progress()
	for id in WeatherDefs.ORDER:
		if roll(_seed(), seasons.year(), day, id, season, p, seasons.days_in_season(season), frequency_multiplier):
			var lead := WeatherDefs.f(id, "lead", 60.0)
			var day_len := _sim.clock.day_seconds() if _sim != null else GameClock.DEFAULT_DAY_LENGTH
			var start := lead + WeatherDefs.hash01(_seed(), seasons.year(), day, id, WeatherDefs.SALT_START) * maxf(0.0, day_len - lead)
			var dur := WeatherDefs.duration_for(id, WeatherDefs.hash01(_seed(), seasons.year(), day, id, WeatherDefs.SALT_DURATION))
			_queued = {"id": id, "start_in": start, "duration": dur}
			return


## Ставит событие в очередь (тесты, отладка): через lead секунд (0 — сразу), длительность dur (<0 — по таблице).
func queue_event(id: StringName, start_in: float = 0.0, dur: float = -1.0) -> bool:
	if not WeatherDefs.exists(id):
		return false
	if dur < 0.0:
		dur = WeatherDefs.duration_for(id, 0.5)
	_queued = {"id": id, "start_in": maxf(0.0, start_in), "duration": dur}
	return true


## Немедленный старт (без lead).
func start_event(id: StringName, dur: float = -1.0) -> bool:
	if not queue_event(id, 0.0, dur):
		return false
	_start_queued()
	return true


func end_event() -> void:
	if not _active.is_empty():
		_end_active()


func _start_queued() -> void:
	var q := _queued
	_queued = {}
	_active = {"id": q["id"], "elapsed": 0.0, "duration": q["duration"]}
	_after = {}
	_lightning_acc = 0.0
	if _sim != null:
		_sim.bus.emit(TOPIC_STARTED, {"id": q["id"]})
	if WeatherDefs.def(q["id"]).get("extinguish", false) and fire != null:
		fire.extinguish_all()
	apply_hooks()


func _total(a: Dictionary) -> float:
	if a["id"] == WeatherDefs.FLOOD:
		return WeatherDefs.flood_total(float(a["duration"]))
	return float(a["duration"])


func _end_active() -> void:
	var id: StringName = _active["id"]
	var d := WeatherDefs.def(id)
	var was := float(_active["duration"])
	_after = {"id": id, "peak": float(d.get("peak", 0.5)), "left": WeatherDefs.AFTER_TIME}
	_active = {}
	cooldown_left = WeatherDefs.COOLDOWN
	if d.get("rain", false):
		_garden_after_left = WeatherDefs.GARDEN_RAIN_AFTER
		_garden_after_mult = float(d.get("garden", 1.0))
	if id == WeatherDefs.FLOOD:
		_set_flood_level(0.0)
	if _sim != null:
		_sim.bus.emit(TOPIC_ENDED, {"id": id})
	# ливень подольше вне зимы может вызвать паводок (без паузы)
	if id == WeatherDefs.DOWNPOUR and was >= WeatherDefs.FLOOD_AFTER_RAIN_MIN and seasons != null and seasons.season() != SeasonDefs.WINTER and frequency_multiplier > 0.0:
		var r := WeatherDefs.hash01(_seed(), seasons.year(), _sim.clock.get_day() if _sim != null else 0, id, WeatherDefs.SALT_FLOOD_RAIN)
		if r < WeatherDefs.FLOOD_AFTER_RAIN_CHANCE * frequency_multiplier and _queued.is_empty():
			var dur := WeatherDefs.duration_for(WeatherDefs.FLOOD, r)
			_queued = {"id": WeatherDefs.FLOOD, "start_in": WeatherDefs.f(WeatherDefs.FLOOD, "lead", 120.0), "duration": dur}
	apply_hooks()


# ---------- хуки ----------

## Выставляет хуки систем по текущему событию (вызывается при смене фазы и раз в APPLY_INTERVAL).
func apply_hooks() -> void:
	var id := current_id()
	var d := WeatherDefs.def(id)
	var on := not _active.is_empty()
	var ramp := _ramp()
	var tid := look_id()
	var td := WeatherDefs.def(tid)
	if seasons != null:
		seasons.weather_temp_offset = float(td.get("temp", 0.0)) * ramp if (on or not _after.is_empty()) else 0.0
		seasons.weather_build_multiplier = float(d.get("build", 1.0)) if on else 1.0
		seasons.weather_walk_multiplier = lerpf(1.0, float(d.get("walk", 1.0)), ramp) if on else 1.0
		seasons.weather_mud_floor = float(d.get("mud", 0.0)) if on else 0.0
		seasons.apply_hooks()
	if villagers != null:
		var hs := villagers.household
		var garden := float(d.get("garden", 1.0)) if on else 1.0
		if not on and _garden_after_left > 0.0:
			garden = _garden_after_mult
		hs.garden_growth_multiplier = garden
		hs.garden_dry_rate = float(d.get("dry", 0.0)) if on else 0.0
		hs.well_work_multiplier = float(d.get("well", 1.0)) if on else 1.0
		hs.water_decay_multiplier = float(d.get("water_decay", 1.0)) if on else 1.0
		hs.shelter_required = on and bool(d.get("shelter", false))
		hs.exposure_warmth_mult = float(d.get("exp_warmth", 1.0)) if on else 1.0
		hs.exposure_health_drain = float(d.get("exp_drain", 0.0)) if on else 0.0


# ---------- паводок ----------

func _set_flood_level(level: float) -> void:
	if flood == null:
		return
	_flood_level_applied = level
	var changed := flood.set_level(level)
	if changed or level == 0.0:
		_on_flood_changed()


func _on_flood_changed() -> void:
	if construction == null:
		return
	for b: Building in construction.buildings.values():
		b.flooded = b.is_done() and construction.building_flooded(b)
	if villagers == null:
		return
	var pf := villagers.pathfinder
	pf.set_blocked_cells(flood.flooded)
	for v: Villager in villagers.villagers.values():
		v.path.clear()
		v.path_goal = Vector2i(-1, -1)
		if not pf.is_walkable(v.pos):  # застигнутого водой переносит на сухое место
			v.pos = villagers._ground(pf.nearest_walkable(v.pos))
	if villagers.dog != null:
		var dg := villagers.dog
		dg.path.clear()
		dg.path_goal = Vector2i(-1, -1)
		if not pf.is_walkable(dg.pos):
			dg.pos = villagers._ground(pf.nearest_walkable(dg.pos))
	villagers._jobs_dirty = true


# ---------- пожар и молнии ----------

func ignite_cell(c: Vector2i) -> bool:
	return fire != null and fire.ignite_cell(c)


## Выливает воду на очаг (вызывает житель, дошедший с вёдрами).
func douse(dest: StringName, target: int, water: int) -> bool:
	if fire == null:
		return false
	var out: bool = fire.douse_building(target, water) if dest == &"building" else fire.douse_cell(target, water)
	if out and _sim != null:
		_sim.bus.emit(TOPIC_FIRE, {"type": WeatherFire.EV_BUILDING_SAVED if dest == &"building" else WeatherFire.EV_CELL_SAVED, "target": target})
	if out:
		_changed_jobs()
	return out


func _changed_jobs() -> void:
	if villagers != null:
		villagers._jobs_dirty = true


func _lightning() -> void:
	var rng := _sim.rng
	var c := Vector2i(rng.randi_range(0, world.size - 1), rng.randi_range(0, world.size - 1))
	if _sim != null:
		_sim.bus.emit(TOPIC_LIGHTNING, {"cell": c})
	if rng.randf() < fire.ignite_chance and fire.ignite_cell(c):
		_sim.bus.emit(TOPIC_FIRE, {"type": WeatherFire.EV_CELL_IGNITED, "cell": c})


func _tick_fire(dt: float) -> void:
	if fire == null:
		return
	if is_active() and WeatherDefs.def(current_id()).get("extinguish", false):
		fire.extinguish_all()
	var events := fire.tick(dt, _sim.rng if _sim != null else RandomNumberGenerator.new())
	for e in events:
		match e["type"]:
			WeatherFire.EV_CELL_BURNT:
				var i: int = fire.idx(e["cell"])
				fertility[i] = minf(WeatherDefs.FERTILITY_MAX, float(fertility.get(i, 0.0)) + WeatherDefs.BURN_FERTILITY)
				fertility_revision += 1
		if _sim != null:
			_sim.bus.emit(TOPIC_FIRE, e)
	if not events.is_empty():
		_changed_jobs()


func _tick_fertility(dt: float) -> void:
	if fertility.is_empty() or seasons == null:
		return
	var rate := WeatherDefs.BURN_FERTILITY / (WeatherDefs.FERTILITY_LIFETIME_YEARS * seasons.year_length())
	for i in fertility.keys():
		var v: float = float(fertility[i]) - rate * dt
		if v <= 0.0:
			fertility.erase(i)
		else:
			fertility[i] = v
	fertility_revision += 1


# ---------- тик ----------

func tick(sim: Simulation, dt: float) -> void:
	_sim = sim
	if dt <= 0.0 or seasons == null:
		return
	var day := sim.clock.get_day()
	if day != _rolled_day:
		_rolled_day = day
		if day > WeatherDefs.NO_EVENTS_FIRST_DAYS:
			_roll_day(day)
	if cooldown_left > 0.0:
		cooldown_left = maxf(0.0, cooldown_left - dt)
	if not _queued.is_empty():
		_queued["start_in"] = float(_queued["start_in"]) - dt
		if float(_queued["start_in"]) <= 0.0 and _active.is_empty():
			_start_queued()
		elif float(_queued["start_in"]) <= 0.0:
			_queued["start_in"] = 0.0
	if not _active.is_empty():
		_active["elapsed"] = float(_active["elapsed"]) + dt
		var id: StringName = _active["id"]
		if id == WeatherDefs.FLOOD:
			var lvl := WeatherDefs.flood_level(float(_active["elapsed"]), float(_active["duration"]))
			if absf(lvl - _flood_level_applied) >= WeatherDefs.FLOOD_LEVEL_STEP or ((lvl == 0.0 or lvl == WeatherDefs.FLOOD_HEIGHT) and _flood_level_applied != lvl):
				_set_flood_level(lvl)
		if WeatherDefs.def(id).get("lightning", false):
			_lightning_acc += dt
			while _lightning_acc >= WeatherDefs.LIGHTNING_PERIOD:
				_lightning_acc -= WeatherDefs.LIGHTNING_PERIOD
				_lightning()
		if float(_active["elapsed"]) >= _total(_active):
			_end_active()
	elif not _after.is_empty():
		_after["left"] = float(_after["left"]) - dt
		if float(_after["left"]) <= 0.0:
			_after = {}
			apply_hooks()
	if _garden_after_left > 0.0 and _active.is_empty():
		_garden_after_left = maxf(0.0, _garden_after_left - dt)
		if _garden_after_left == 0.0:
			apply_hooks()
	_tick_fire(dt)
	_tick_fertility(dt)
	_apply_acc += dt
	if _apply_acc >= SeasonSystem.APPLY_INTERVAL:
		_apply_acc = 0.0
		apply_hooks()
	if villagers != null and villagers.dog != null:
		villagers.dog.set_anxious(anxiety_level())


# ---------- сохранение ----------

func get_save_key() -> StringName:
	return &"weather"


func save_state() -> Dictionary:
	var fert := {}
	for i in fertility:
		fert[str(i)] = fertility[i]
	return {
		"queued": _stringify(_queued), "active": _stringify(_active), "after": _stringify(_after),
		"cooldown": cooldown_left, "rolled_day": _rolled_day, "lightning_acc": _lightning_acc,
		"garden_after_left": _garden_after_left, "garden_after_mult": _garden_after_mult,
		"frequency_multiplier": frequency_multiplier, "fertility": fert,
		"fire": fire.save_state() if fire != null else {},
	}


static func _stringify(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[String(k)] = String(d[k]) if d[k] is StringName else d[k]
	return out


func _read_state(d) -> Dictionary:
	var out := {}
	if d is Dictionary and WeatherDefs.exists(StringName(String(d.get("id", "")))):
		out["id"] = StringName(String(d["id"]))
		for k in ["start_in", "duration", "elapsed", "peak", "left"]:
			if d.has(k):
				out[k] = float(d[k])
	return out


func load_state(d: Dictionary) -> void:
	_queued = _read_state(d.get("queued"))
	_active = _read_state(d.get("active"))
	_after = _read_state(d.get("after"))
	if not _queued.is_empty() and (not _queued.has("start_in") or not _queued.has("duration")):
		_queued = {}
	if not _active.is_empty() and (not _active.has("elapsed") or not _active.has("duration")):
		_active = {}
	if not _after.is_empty() and (not _after.has("left") or not _after.has("peak")):
		_after = {}
	cooldown_left = maxf(0.0, float(d.get("cooldown", 0.0)))
	_rolled_day = SaveManager.to_int(d.get("rolled_day"), 0)
	_lightning_acc = float(d.get("lightning_acc", 0.0))
	_garden_after_left = maxf(0.0, float(d.get("garden_after_left", 0.0)))
	_garden_after_mult = float(d.get("garden_after_mult", 1.0))
	frequency_multiplier = maxf(0.0, float(d.get("frequency_multiplier", 1.0)))
	fertility.clear()
	if d.get("fertility") is Dictionary:
		for k in d["fertility"]:
			var v := float(d["fertility"][k])
			if v > 0.0:
				fertility[SaveManager.to_int(k, -1)] = clampf(v, 0.0, WeatherDefs.FERTILITY_MAX)
	fertility_revision += 1
	if fire != null:
		fire.load_state(d.get("fire", {}) if d.get("fire") is Dictionary else {})
	# затопление не хранится: пересчитывается из фазы события
	_flood_level_applied = -1.0
	if flood != null:
		if is_active(WeatherDefs.FLOOD):
			_set_flood_level(WeatherDefs.flood_level(float(_active["elapsed"]), float(_active["duration"])))
		else:
			flood.clear()
			_on_flood_changed()
	apply_hooks()
