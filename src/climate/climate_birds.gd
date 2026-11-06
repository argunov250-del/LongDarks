class_name ClimateBirds
extends Node3D
## Птицы весной (шаг 15), design/gdd/climate-warming.md: стаи низкополигональных птиц (один MultiMesh,
## взмах крыльев в вершинном шейдере), «boids-lite»: стая летит по дуге к точке рядом с камерой,
## садится на дерево, сидит, взлетает. Появляются весной после first_birds, чем теплее — тем больше.
## Мобильно: до BIRDS_MAX экземпляров, 1 draw call, позиции считаются только пока птицы видны.

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 albedo = vec3(0.12, 0.12, 0.14);
uniform float flap_speed = 14.0;
void vertex() {
	float ph = float(INSTANCE_ID) * 1.7;
	VERTEX.y += abs(VERTEX.x) * 0.9 * sin(TIME * flap_speed + ph) * step(0.01, abs(VERTEX.x));
}
void fragment() { ALBEDO = albedo; }
"""

var climate: ClimateSystem
var seasons: SeasonSystem
var world_map: WorldMap
var deposits: Deposits
var focus_provider: Callable = Callable()   # () -> Vector3, фокус камеры (иначе центр карты)
var multimesh: MultiMesh
var visible_count := 0                       # сколько птиц сейчас показано (для тестов)

var _rng := RandomNumberGenerator.new()
var _forest: Array[Vector2i] = []
var _flocks: Array = []                      # словари стай
var _birds: Array = []                       # словари птиц: flock, offset, pos, dir


func setup(climate_in: ClimateSystem, seasons_in: SeasonSystem, map_in: WorldMap, deposits_in: Deposits, focus: Callable = Callable()) -> void:
	climate = climate_in
	seasons = seasons_in
	world_map = map_in
	deposits = deposits_in
	focus_provider = focus
	_rng.seed = 15
	for cz in world_map.size:
		for cx in world_map.size:
			if world_map.cell_type(cx, cz) == WorldMap.Terrain.FOREST:
				_forest.append(Vector2i(cx, cz))
	var mi := MultiMeshInstance3D.new()
	mi.name = "BirdsMM"
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _bird_mesh()
	multimesh.instance_count = ClimateDefs.BIRDS_MAX
	multimesh.visible_instance_count = 0
	mi.multimesh = multimesh
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 200.0
	add_child(mi)
	set_process(true)


## Тело и два крыла: 3 треугольника (крылья машут шейдером по |x|).
static func _bird_mesh() -> ArrayMesh:
	var v := PackedVector3Array([
		Vector3(0, 0, -0.45), Vector3(-0.12, 0, 0.2), Vector3(0.12, 0, 0.2),          # тело, нос к -Z
		Vector3(-0.1, 0, -0.1), Vector3(-0.9, 0, 0.15), Vector3(-0.1, 0, 0.2),         # левое крыло
		Vector3(0.1, 0, -0.1), Vector3(0.1, 0, 0.2), Vector3(0.9, 0, 0.15),            # правое
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Сколько птиц показывать сейчас: только весной, с прилётом и отлётом по доле весны.
func target_count() -> int:
	if climate == null or seasons == null or seasons.season() != SeasonDefs.SPRING:
		return 0
	var n := climate.bird_count()
	var p := seasons.progress()
	var k := smoothstep(0.0, ClimateDefs.BIRD_FADE_IN, p) * (1.0 - smoothstep(1.0 - ClimateDefs.BIRD_FADE_OUT, 1.0, p))
	return roundi(float(n) * k)


func _process(delta: float) -> void:
	step(minf(delta, 0.1))


## Один шаг анимации (вызывается и из тестов/скриншотов).
func step(delta: float) -> void:
	var want := target_count()
	_resize(want)
	visible_count = want
	multimesh.visible_instance_count = want
	if want == 0:
		return
	for f in _flocks:
		_update_flock(f, delta)
	for i in _birds.size():
		var b: Dictionary = _birds[i]
		var f: Dictionary = _flocks[b["flock"]]
		var landed: bool = f["state"] == &"perch"
		var spread: float = 1.2 if landed else 3.0
		var o: Vector3 = b["offset"]
		var target: Vector3 = f["pos"] + Vector3(o.x * spread, o.y * (0.3 if landed else 1.0), o.z * spread)
		if landed:  # сидят на вершине дерева, лицом по ветру
			target.y = f["pos"].y + 0.0
		var prev: Vector3 = b["pos"]
		var np := prev.lerp(target, clampf(delta * (2.5 if landed else 4.0), 0.0, 1.0))
		var vel := np - prev
		if vel.length() > 0.01:
			b["dir"] = Vector3(vel.x, 0.0, vel.z).normalized() if (vel.x != 0.0 or vel.z != 0.0) else b["dir"]
		b["pos"] = np
		var fwd: Vector3 = b["dir"]
		var basis := Basis.looking_at(fwd, Vector3.UP).scaled(Vector3.ONE * ClimateDefs.BIRD_SCALE)
		if not landed:
			basis = basis * Basis.from_euler(Vector3(0.0, 0.0, sin(f["t"] * 2.0 + float(i)) * 0.25))
		multimesh.set_instance_transform(i, Transform3D(basis, np))


func _resize(want: int) -> void:
	while _birds.size() < want:
		var fi := _birds.size() / ClimateDefs.BIRD_FLOCK_SIZE
		if fi >= _flocks.size():
			_flocks.append(_new_flock())
		var f: Dictionary = _flocks[fi]
		_birds.append({"flock": fi, "offset": Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-1, 1)),
			"pos": f["pos"], "dir": Vector3(0, 0, -1)})
	# лишние птицы просто скрыты (visible_instance_count); массивы не сжимаем, чтобы стаи не прыгали


func _focus() -> Vector3:
	if focus_provider.is_valid():
		return focus_provider.call()
	var ws := world_map.get_world_size()
	return Vector3(ws * 0.5, 0.0, ws * 0.5)


func _random_near_focus() -> Vector3:
	var fc := _focus()
	var a := _rng.randf() * TAU
	var r := sqrt(_rng.randf()) * ClimateDefs.BIRD_WAYPOINT_RADIUS
	var ws := world_map.get_world_size()
	return Vector3(clampf(fc.x + cos(a) * r, 2.0, ws - 2.0), 0.0, clampf(fc.z + sin(a) * r, 2.0, ws - 2.0))


func _new_flock() -> Dictionary:
	var start := _random_near_focus()
	var alt := _rng.randf_range(ClimateDefs.BIRD_ALTITUDE_MIN, ClimateDefs.BIRD_ALTITUDE_MAX)
	var f := {"pos": Vector3(start.x, world_map.height_at(start.x, start.z) + alt, start.z), "state": &"fly", "t": 0.0,
		"from": Vector3.ZERO, "to": Vector3.ZERO, "u": 0.0, "dur": 1.0, "perch_left": 0.0, "land": false, "alt": alt}
	_pick_waypoint(f)
	return f


## Новая цель полёта; с шансом BIRD_LAND_CHANCE — вершина ближайшего леса с деревьями.
func _pick_waypoint(f: Dictionary) -> void:
	var from: Vector3 = f["pos"]
	var wp := _random_near_focus()
	var land := _rng.randf() < ClimateDefs.BIRD_LAND_CHANCE
	var alt := _rng.randf_range(ClimateDefs.BIRD_ALTITUDE_MIN, ClimateDefs.BIRD_ALTITUDE_MAX)
	var target := Vector3(wp.x, world_map.height_at(wp.x, wp.z) + alt, wp.z)
	if land:
		var c := _tree_near(wp)
		if c.x >= 0:
			var cc := world_map.cell_center(c.x, c.y)
			target = Vector3(cc.x, world_map.height_at(cc.x, cc.z) + ClimateDefs.BIRD_TREE_TOP, cc.z)
		else:
			land = false
	f["from"] = from
	f["to"] = target
	f["land"] = land
	f["u"] = 0.0
	f["dur"] = maxf(1.0, from.distance_to(target) / ClimateDefs.BIRD_SPEED)
	f["state"] = &"fly"


func _tree_near(p: Vector3) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := INF
	for k in 24:  # выборка вместо полного перебора: дёшево
		var c: Vector2i = _forest[_rng.randi() % _forest.size()] if not _forest.is_empty() else Vector2i(-1, -1)
		if c.x < 0:
			break
		if deposits != null and deposits.remaining(c) <= 0:
			continue
		var cc := world_map.cell_center(c.x, c.y)
		var d := Vector2(cc.x - p.x, cc.z - p.z).length_squared()
		if d < bd:
			bd = d
			best = c
	return best


func _update_flock(f: Dictionary, delta: float) -> void:
	f["t"] = float(f["t"]) + delta
	if f["state"] == &"perch":
		f["perch_left"] = float(f["perch_left"]) - delta
		if float(f["perch_left"]) <= 0.0:
			_pick_waypoint(f)
		return
	f["u"] = minf(1.0, float(f["u"]) + delta / float(f["dur"]))
	var u: float = f["u"]
	var from: Vector3 = f["from"]
	var to: Vector3 = f["to"]
	var pos := from.lerp(to, u)
	var side := Vector3(to.z - from.z, 0.0, -(to.x - from.x)).normalized()
	pos += side * sin(u * PI) * ClimateDefs.BIRD_ARC + Vector3(0.0, sin(u * PI) * 1.5, 0.0)   # дуга
	f["pos"] = pos
	if u >= 1.0:
		if f["land"]:
			f["state"] = &"perch"
			f["perch_left"] = _rng.randf_range(ClimateDefs.BIRD_PERCH_TIME_MIN, ClimateDefs.BIRD_PERCH_TIME_MAX)
		else:
			_pick_waypoint(f)
