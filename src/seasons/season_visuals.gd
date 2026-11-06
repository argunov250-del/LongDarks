class_name SeasonVisuals
extends Node
## Сезонный вид (шаг 13): снег и зелень на рельефе (параметры шейдера, без перестройки меша),
## оттенок неба и света. Обновляется редко — дёшево для мобильных.

const UPDATE_INTERVAL := 0.25   # реальные секунды

var seasons: SeasonSystem
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
	if light != null:
		light.light_color = seasons.blend(SeasonDefs.LIGHT_COLOR)
		light.light_energy = seasons.blend(SeasonDefs.LIGHT_ENERGY)
	if environment != null:
		environment.ambient_light_color = seasons.blend(SeasonDefs.AMBIENT_COLOR)
		var sky := environment.sky
		if sky != null and sky.sky_material is ProceduralSkyMaterial:
			var m := sky.sky_material as ProceduralSkyMaterial
			m.sky_top_color = seasons.blend(SeasonDefs.SKY_TOP)
			m.sky_horizon_color = seasons.blend(SeasonDefs.SKY_HORIZON)
			m.ground_horizon_color = m.sky_horizon_color
