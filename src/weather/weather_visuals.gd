class_name WeatherVisuals
extends Node3D
## Вид погоды (шаг 14), дёшево для мобильных: частицы снега/дождя вокруг камеры, вспышки молний
## (оверлей), качание деревьев, огонь на горящих клетках, гарь на выгоревшей земле, вода паводка.
## Небо, свет и туман событий — в SeasonVisuals (WeatherDefs.LOOKS). Никакой информации о будущем
## событии: показывается только идущее.

const UPDATE_INTERVAL := 0.3     # реальные секунды: огонь, гарь, вода
const FIRE_CELL_MAX := 60        # узлов огня на лесных клетках

var weather: WeatherSystem
var world_view: WorldView
var construction: ConstructionSystem
var camera: Camera3D
var flash_rect: ColorRect
var flashes := 0                  # сколько вспышек было (для тестов)

var _precip: Dictionary = {}      # вид -> CPUParticles3D
var _acc := 1.0e9
var _flash_left := 0.0
var _flash_gap := 3.0
var _fire_nodes: Dictionary = {}  # индекс клетки -> Node3D
var _fire_rev := -1
var _burnt: MeshInstance3D
var _burnt_sig := ""
var _water: MeshInstance3D
var _water_sig := ""
var _layer: CanvasLayer


func setup(weather_in: WeatherSystem, view: WorldView, construction_in: ConstructionSystem, camera_in: Camera3D) -> void:
	weather = weather_in
	world_view = view
	construction = construction_in
	camera = camera_in
	_layer = CanvasLayer.new()
	_layer.layer = 0
	add_child(_layer)
	flash_rect = ColorRect.new()
	flash_rect.color = Color(0.9, 0.93, 1.0, 0.0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(flash_rect)
	for kind in [&"snow", &"rain"]:
		var p := WeatherFx.make_precip(kind, WeatherDefs.SNOW_AMOUNT if kind == &"snow" else WeatherDefs.RAIN_AMOUNT, WeatherDefs.PARTICLE_BOX)
		_precip[kind] = p
		add_child(p)
	var bus := weather.bus()
	if bus != null:
		bus.subscribe(WeatherSystem.TOPIC_LIGHTNING, func(_p: Dictionary) -> void: flash())


## Вспышка молнии.
func flash() -> void:
	_flash_left = WeatherDefs.FLASH_TIME
	flashes += 1


func _focus_point() -> Vector3:
	if camera == null or not camera.is_inside_tree():
		return Vector3.ZERO
	var o := camera.global_position
	var d := -camera.global_transform.basis.z
	if d.y < -0.05:
		return o + d * ((o.y - 4.0) / -d.y)
	return o


func _process(delta: float) -> void:
	if weather == null:
		return
	var id := weather.look_id()
	var k := weather.intensity()
	_update_precip(id, k)
	_update_flash(id, k, delta)
	if world_view != null:
		var sway := 0.0
		if k > 0.0:
			sway = WeatherDefs.TREE_SWAY_HURRICANE if id == WeatherDefs.HURRICANE else (WeatherDefs.TREE_SWAY_STORM if id in [WeatherDefs.THUNDERSTORM, WeatherDefs.BLIZZARD] else 0.0)
		world_view.set_tree_sway(sway * k)
	_acc += delta
	if _acc >= UPDATE_INTERVAL:
		_acc = 0.0
		refresh_ground()


func _update_precip(id: StringName, k: float) -> void:
	var cfg: Dictionary = WeatherDefs.PARTICLES.get(id, {})
	var focus := _focus_point()
	for kind in _precip:
		var p: CPUParticles3D = _precip[kind]
		var on: bool = not cfg.is_empty() and cfg["kind"] == kind and k > 0.0
		if on:
			var wind: float = cfg["wind"]
			var fall: float = cfg["fall"]
			var vel := Vector3(wind, -fall, wind * 0.3)
			p.direction = vel.normalized()
			p.initial_velocity_min = vel.length()
			p.initial_velocity_max = vel.length() * 1.15
			p.global_position = focus + Vector3(-wind * 0.6, WeatherDefs.PARTICLE_BOX.y * 0.5 - 2.0, 0.0)
		p.emitting = on


func _update_flash(id: StringName, _k: float, delta: float) -> void:
	if WeatherDefs.def(id).get("lightning", false) and weather.is_active(id):
		_flash_gap -= delta
		if _flash_gap <= 0.0:  # гроза гремит и без попаданий в лес
			_flash_gap = randf_range(3.0, 8.0)
			flash()
	if _flash_left > 0.0:
		_flash_left -= delta
		var t := clampf(_flash_left / WeatherDefs.FLASH_TIME, 0.0, 1.0)
		flash_rect.color.a = WeatherDefs.FLASH_ALPHA * (0.5 + 0.5 * sin(t * PI * 3.0)) * t
	else:
		flash_rect.color.a = 0.0


## Огонь, гарь и вода паводка (пересборка только при изменении).
func refresh_ground() -> void:
	_sync_fire()
	_sync_burnt()
	_sync_water()


func _sync_fire() -> void:
	var f := weather.fire
	if f == null:
		return
	var cs := weather.world.cell_size
	for i in _fire_nodes.keys():
		if not f.cells.has(i):
			(_fire_nodes[i] as Node3D).queue_free()
			_fire_nodes.erase(i)
	for i in f.cells:
		if _fire_nodes.has(i) or _fire_nodes.size() >= FIRE_CELL_MAX:
			continue
		var c := f.cell_of_idx(i)
		var n := WeatherFx.make_fire(cs * 0.45, 2.6, 14, false)
		add_child(n)
		n.position = weather.world.cell_center(c.x, c.y)
		_fire_nodes[i] = n


func _sync_burnt() -> void:
	var w := weather.world
	var sig := str(weather.fertility.size()) + ":" + str(snappedf(_fert_sum(), 0.05))
	if sig == _burnt_sig:
		return
	_burnt_sig = sig
	if _burnt != null:
		_burnt.queue_free()
		_burnt = null
	if weather.fertility.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in weather.fertility:
		var cx: int = i % w.size
		var cz: int = i / w.size
		var a := clampf(float(weather.fertility[i]) / WeatherDefs.BURN_FERTILITY, 0.0, 1.0) * WeatherDefs.BURNT_ALPHA_MAX
		var col := Color(WeatherDefs.BURNT_COLOR.r, WeatherDefs.BURNT_COLOR.g, WeatherDefs.BURNT_COLOR.b, a)
		var cs := w.cell_size
		var p00 := Vector3(cx * cs, w.node_height(cx, cz) + 0.06, cz * cs)
		var p10 := Vector3((cx + 1) * cs, w.node_height(cx + 1, cz) + 0.06, cz * cs)
		var p01 := Vector3(cx * cs, w.node_height(cx, cz + 1) + 0.06, (cz + 1) * cs)
		var p11 := Vector3((cx + 1) * cs, w.node_height(cx + 1, cz + 1) + 0.06, (cz + 1) * cs)
		for v: Vector3 in [p00, p10, p01, p10, p11, p01]:
			st.set_color(col)
			st.add_vertex(v)
	st.generate_normals()
	_burnt = MeshInstance3D.new()
	_burnt.name = "Burnt"
	_burnt.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	_burnt.material_override = mat
	add_child(_burnt)


func _fert_sum() -> float:
	var s := 0.0
	for i in weather.fertility:
		s += float(weather.fertility[i])
	return s


func _sync_water() -> void:
	var fl := weather.flood
	if fl == null:
		return
	var sig := "%d:%s" % [fl.revision, str(snappedf(fl.level, WeatherDefs.FLOOD_LEVEL_STEP))]
	if sig == _water_sig:
		return
	_water_sig = sig
	if _water != null:
		_water.queue_free()
		_water = null
	if fl.flooded.is_empty():
		return
	var w := weather.world
	var y := WorldMap.WATER_LEVEL + fl.level
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cs := w.cell_size
	for i in fl.flooded:
		var cx: int = i % w.size
		var cz: int = i / w.size
		var p00 := Vector3(cx * cs, y, cz * cs)
		var p10 := Vector3((cx + 1) * cs, y, cz * cs)
		var p01 := Vector3(cx * cs, y, (cz + 1) * cs)
		var p11 := Vector3((cx + 1) * cs, y, (cz + 1) * cs)
		for v: Vector3 in [p00, p10, p01, p10, p11, p01]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	_water = MeshInstance3D.new()
	_water.name = "FloodWater"
	_water.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WeatherDefs.FLOOD_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_water.material_override = mat
	add_child(_water)
