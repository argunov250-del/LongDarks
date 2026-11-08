class_name GameSettings
extends SimSystem
## Настройки партии (режим + сложность). Часть сохранения (ключ `game_settings`).
## Дизайн: design/gdd/modes-difficulty.md. Ручки: длина зимы, поведение соседей, частота непогоды.

var mode: StringName = ModeDefs.SANDBOX
var preset: StringName = ModeDefs.DEFAULT_PRESET
var winter_mult := 1.0
var neighbour_mode: StringName = ModeDefs.NORMAL
var weather_mult := 1.0

var seasons: SeasonSystem
var weather: WeatherSystem
var neighbours: NeighbourSystem


func _init(preset_id: StringName = ModeDefs.DEFAULT_PRESET) -> void:
	set_preset(preset_id)


func bind(seasons_in: SeasonSystem, weather_in: WeatherSystem, neighbours_in: NeighbourSystem) -> void:
	seasons = seasons_in
	weather = weather_in
	neighbours = neighbours_in


## Заполняет ручки пресетом. Неизвестный id отвергается (false).
func set_preset(id: StringName) -> bool:
	if not ModeDefs.PRESETS.has(id):
		return false
	var p: Dictionary = ModeDefs.PRESETS[id]
	preset = id
	winter_mult = p["winter_mult"]
	neighbour_mode = p["neighbour_mode"]
	weather_mult = p["weather_mult"]
	return true


func set_mode(id: StringName) -> bool:
	if not ModeDefs.MODES.has(id) or not ModeDefs.MODES[id]["enabled"]:
		return false
	mode = id
	return true


func set_winter_mult(v: float) -> void:
	winter_mult = clampf(v, ModeDefs.WINTER_MULT_RANGE.x, ModeDefs.WINTER_MULT_RANGE.y)
	_mark_custom()


func set_weather_mult(v: float) -> void:
	weather_mult = clampf(v, ModeDefs.WEATHER_MULT_RANGE.x, ModeDefs.WEATHER_MULT_RANGE.y)
	_mark_custom()


func set_neighbour_mode(id: StringName) -> bool:
	if not ModeDefs.NEIGHBOUR_MODES.has(id):
		return false
	neighbour_mode = id
	_mark_custom()
	return true


## Пресет, чьи ручки совпадают с текущими, иначе «custom».
func _mark_custom() -> void:
	preset = ModeDefs.CUSTOM
	for id in ModeDefs.PRESET_ORDER:
		var p: Dictionary = ModeDefs.PRESETS[id]
		if is_equal_approx(float(p["winter_mult"]), winter_mult) and p["neighbour_mode"] == neighbour_mode \
				and is_equal_approx(float(p["weather_mult"]), weather_mult):
			preset = id


func winter_minutes() -> float:
	return float(SeasonDefs.DEFAULT_MINUTES[SeasonDefs.WINTER]) * winter_mult


## Прокидывает ручки в системы (сезоны, погода, соседи). Безопасно без привязки.
func apply() -> void:
	if seasons != null:
		seasons.set_duration_minutes(SeasonDefs.WINTER, winter_minutes())
	if weather != null:
		weather.set_frequency_multiplier(weather_mult)
	if neighbours != null:
		var nm: Dictionary = ModeDefs.NEIGHBOUR_MODES[neighbour_mode]
		neighbours.aggression_scale = nm["aggression_mult"]
		neighbours.incident_scale = nm["incident_mult"]


func get_save_key() -> StringName:
	return &"game_settings"


func save_state() -> Dictionary:
	return to_dict()


func load_state(d: Dictionary) -> void:
	from_dict(d)
	apply()


func to_dict() -> Dictionary:
	return {"mode": String(mode), "preset": String(preset), "winter_mult": winter_mult,
		"neighbour_mode": String(neighbour_mode), "weather_mult": weather_mult}


func from_dict(d: Dictionary) -> void:
	if ModeDefs.MODES.has(StringName(d.get("mode", ""))):
		mode = StringName(d["mode"])
	if ModeDefs.NEIGHBOUR_MODES.has(StringName(d.get("neighbour_mode", ""))):
		neighbour_mode = StringName(d["neighbour_mode"])
	winter_mult = clampf(float(d.get("winter_mult", winter_mult)), ModeDefs.WINTER_MULT_RANGE.x, ModeDefs.WINTER_MULT_RANGE.y)
	weather_mult = clampf(float(d.get("weather_mult", weather_mult)), ModeDefs.WEATHER_MULT_RANGE.x, ModeDefs.WEATHER_MULT_RANGE.y)
	var p := StringName(d.get("preset", ""))
	preset = p if (ModeDefs.PRESETS.has(p) or p == ModeDefs.CUSTOM) else ModeDefs.CUSTOM
