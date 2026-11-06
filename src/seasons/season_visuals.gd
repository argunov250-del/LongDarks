class_name SeasonVisuals
extends Node
## Сезонный вид (шаг 13): снег и зелень на рельефе (параметры шейдера, без перестройки меша),
## оттенок неба и света по сезону; смена дня и ночи (направление/цвет/яркость света, ambient, небо)
## по часу GameClock. Обновляется редко — дёшево для мобильных.

const UPDATE_INTERVAL := 0.25   # реальные секунды

var seasons: SeasonSystem
var weather: WeatherSystem   # шаг 14: небо, свет и туман погодных событий (null — без погоды)
var world_view: WorldView
var environment: Environment
var light: DirectionalLight3D
var _acc := 1.0e9


func setup(seasons_in: SeasonSystem, view: WorldView, world_env: WorldEnvironment, light_in: DirectionalLight3D) -> void:
	seasons = seasons_in
	world_view = view
	environment = world_env.environment if world_env != null else null
	light = light_in
	apply_now()


func _process(delta: float) -> void:
	_acc += delta
	if _acc >= UPDATE_INTERVAL:
		apply_now()


func apply_now() -> void:
	_acc = 0.0
	if seasons == null:
		return
	var tint: Color = seasons.blend(SeasonDefs.GRASS_TINT)
	var amount: float = seasons.blend(SeasonDefs.GRASS_AMOUNT)
	if world_view != null:
		world_view.apply_season(seasons.snow_cover(), tint, amount)
	var hour := seasons.hour()
	var day := SeasonDefs.daylight(hour)
	if light != null:
		light.rotation = sun_rotation(hour)
		var sun: Color = seasons.blend(SeasonDefs.LIGHT_COLOR)
		var low := 1.0 - SeasonDefs.sun_height(hour)
		sun = sun.lerp(SeasonDefs.DUSK_COLOR, low * low * 0.6)  # у горизонта свет теплее
		light.light_color = SeasonDefs.MOON_COLOR.lerp(sun, day)
		light.light_energy = lerpf(SeasonDefs.NIGHT_LIGHT_ENERGY, seasons.blend(SeasonDefs.LIGHT_ENERGY), day)
	if environment != null:
		var amb: Color = seasons.blend(SeasonDefs.AMBIENT_COLOR)
		environment.ambient_light_color = SeasonDefs.NIGHT_AMBIENT_COLOR.lerp(amb, day)
		environment.ambient_light_energy = lerpf(SeasonDefs.NIGHT_AMBIENT_ENERGY, SeasonDefs.DAY_AMBIENT_ENERGY, day)
		var sky := environment.sky
		if sky != null and sky.sky_material is ProceduralSkyMaterial:
			var m := sky.sky_material as ProceduralSkyMaterial
			m.sky_top_color = SeasonDefs.NIGHT_SKY.lerp(seasons.blend(SeasonDefs.SKY_TOP), day)
			m.sky_horizon_color = SeasonDefs.NIGHT_SKY.lerp(seasons.blend(SeasonDefs.SKY_HORIZON), day)
			m.ground_horizon_color = m.sky_horizon_color
	_apply_weather_look(day)


## Направление света: днём — солнце по дуге (выше в полдень), ночью — луна, плавно между ними.
static func sun_rotation(hour: float) -> Vector3:
	var h := SeasonDefs.sun_height(hour)
	var span := SeasonDefs.SUNSET_HOUR - SeasonDefs.SUNRISE_HOUR
	var f := clampf((hour - SeasonDefs.SUNRISE_HOUR) / span, 0.0, 1.0)
	var sun_pitch := lerpf(SeasonDefs.SUN_MIN_PITCH, SeasonDefs.SUN_MAX_PITCH, h)
	var sun_yaw := SeasonDefs.SUN_YAW_NOON + (f - 0.5) * SeasonDefs.SUN_YAW_ARC
	var day := SeasonDefs.daylight(hour)
	var pitch := lerpf(SeasonDefs.MOON_PITCH, sun_pitch, day)
	var yaw := lerpf(SeasonDefs.MOON_YAW, sun_yaw, day)
	return Vector3(-deg_to_rad(pitch), deg_to_rad(yaw), 0.0)


## Погодный вид поверх сезонного: небо и горизонт к цвету события, свет и ambient тусклее,
## туман (метель, дымка засухи), оттенок солнца. Сила — WeatherSystem.intensity().
func _apply_weather_look(day: float) -> void:
	if weather == null:
		return
	var id := weather.look_id()
	var k := weather.intensity()
	var look: Dictionary = WeatherDefs.LOOKS.get(id, {})
	if look.is_empty() or k <= 0.0:
		if environment != null:
			environment.fog_enabled = false
		return
	var bright := 0.3 + 0.7 * day
	if light != null:
		light.light_energy *= lerpf(1.0, float(look["light"]), k)
		var sun: Color = look["sun"]
		light.light_color = light.light_color * Color.WHITE.lerp(sun, k)
	if environment == null:
		return
	environment.ambient_light_energy *= lerpf(1.0, float(look["ambient"]), k)
	var mix := float(look["mix"]) * k
	var sky_c: Color = (look["sky"] as Color) * bright
	if environment.sky != null and environment.sky.sky_material is ProceduralSkyMaterial:
		var m := environment.sky.sky_material as ProceduralSkyMaterial
		m.sky_top_color = m.sky_top_color.lerp(sky_c, mix)
		m.sky_horizon_color = m.sky_horizon_color.lerp(sky_c, mix)
		m.ground_horizon_color = m.sky_horizon_color
	var dens := float(look["fog"]) * k
	environment.fog_enabled = dens > 0.0
	if dens > 0.0:
		environment.fog_density = dens
		environment.fog_light_color = (look["fog_color"] as Color) * bright
