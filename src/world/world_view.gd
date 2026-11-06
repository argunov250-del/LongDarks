class_name WorldView
extends Node3D
## Отрисовка WorldMap: low-poly рельеф с плоскими гранями, вода, декор через MultiMesh.

var map: WorldMap
var terrain_vertex_count := 0
var _ruin_slots: Dictionary = {}   # индекс клетки -> [индекс экземпляра, исходный Transform3D]
var _ruin_mm: MultiMesh
var _tree_slots: Dictionary = {}   # индекс клетки -> [[индекс экземпляра, исходный Transform3D], ...]
var _tree_mm: MultiMesh
var _trees_rev := -1

const COLORS := {
	WorldMap.Terrain.GROUND: Color(0.50, 0.46, 0.34),
	WorldMap.Terrain.RIVER: Color(0.22, 0.27, 0.30),
	WorldMap.Terrain.LAKE: Color(0.20, 0.25, 0.29),
	WorldMap.Terrain.FOREST: Color(0.27, 0.34, 0.24),
	WorldMap.Terrain.RUINS: Color(0.40, 0.38, 0.36),
	WorldMap.Terrain.POISON: Color(0.55, 0.48, 0.24),  # больная жёлто-бурая земля
}
const SNOW := Color(0.90, 0.93, 0.97)
## Доля «травяного» оттенка по типу клетки (летом земля зеленее).
const GRASSINESS := {
	WorldMap.Terrain.GROUND: 1.0, WorldMap.Terrain.FOREST: 0.6, WorldMap.Terrain.RUINS: 0.3,
	WorldMap.Terrain.POISON: 0.0, WorldMap.Terrain.RIVER: 0.0, WorldMap.Terrain.LAKE: 0.0,
}
const TERRAIN_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform float snow_cover = 1.0;
uniform vec3 grass_tint = vec3(1.0);
uniform float grass_amount = 0.0;
uniform vec3 snow_color = vec3(0.90, 0.93, 0.97);
uniform vec3 poison_snow = vec3(0.80, 0.72, 0.46);   // грязный жёлто-бурый снег над отравой
uniform vec3 poison_grass = vec3(1.08, 0.92, 0.62);  // летом трава там чахлая, не зелёная
varying vec3 base;
varying float affinity;
varying float grass;
varying float poison;
void vertex() {
	base = COLOR.rgb;
	affinity = COLOR.a;
	grass = UV.x;
	poison = UV.y;
}
void fragment() {
	vec3 c = mix(base, base * grass_tint, grass * grass_amount);
	c = mix(c, base * poison_grass, poison * grass_amount);
	float t = clamp((snow_cover - (1.0 - affinity) * 0.55) / 0.45, 0.0, 1.0);
	ALBEDO = mix(c, mix(snow_color, poison_snow, poison), t * affinity);
	ROUGHNESS = 1.0;
}
"""

var terrain_material: ShaderMaterial
var _tree_mat: StandardMaterial3D
var _water_mat: StandardMaterial3D
var _tree_sm: ShaderMaterial        # деревья качаются на ветру (uniform sway, шаг 14)
const TREE_SHADER := """
shader_type spatial;
uniform vec3 albedo = vec3(0.2, 0.3, 0.2);
uniform float sway = 0.0;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y + 1.5, 0.0);
	float ph = wp.x * 0.3 + wp.z * 0.23;
	float s = sin(TIME * 2.5 + ph) + 0.5 * sin(TIME * 5.3 + ph * 1.7);
	VERTEX.x += s * sway * h * 0.35;
	VERTEX.z += cos(TIME * 2.1 + ph) * sway * h * 0.2;
}
void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
}
"""
const TREE_COLOR := Color(0.18, 0.28, 0.20)


func build(world_map: WorldMap) -> void:
	map = world_map
	for c in get_children():
		c.queue_free()
	_build_terrain()
	_build_water()
	_build_props()


func _snow_amount(t: int, h: float, cx: int, cz: int) -> float:
	var base := 0.55
	match t:
		WorldMap.Terrain.FOREST: base = 0.30
		WorldMap.Terrain.POISON: base = 0.6  # зимой тоже под снегом (снег там жёлто-бурый, см. шейдер)
		WorldMap.Terrain.RUINS: base = 0.35
		WorldMap.Terrain.RIVER, WorldMap.Terrain.LAKE: return 0.0
	return clampf(base + h * 0.02 + (map.hash01(cx, cz, 5) - 0.5) * 0.25, 0.0, 0.9)


func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := map.size
	var cs := map.cell_size
	for cz in n:
		for cx in n:
			var t := map.cell_type(cx, cz)
			var p00 := Vector3(cx * cs, map.node_height(cx, cz), cz * cs)
			var p10 := Vector3((cx + 1) * cs, map.node_height(cx + 1, cz), cz * cs)
			var p01 := Vector3(cx * cs, map.node_height(cx, cz + 1), (cz + 1) * cs)
			var p11 := Vector3((cx + 1) * cs, map.node_height(cx + 1, cz + 1), (cz + 1) * cs)
			var avg := (p00.y + p10.y + p01.y + p11.y) * 0.25
			var base: Color = COLORS[t]
			var shade := 0.94 + map.hash01(cx, cz, 1) * 0.12
			# rgb — цвет без снега, a — «сколько снега» ложится (см. TERRAIN_SHADER).
			var col := Color(base.r * shade, base.g * shade, base.b * shade, _snow_amount(t, avg, cx, cz))
			var grassy: float = GRASSINESS.get(t, 0.0)
			# Диагональ выбирается по перепаду высот — меньше артефактов.
			var tris: Array
			if absf(p00.y - p11.y) < absf(p10.y - p01.y):
				tris = [p00, p11, p01, p00, p10, p11]
			else:
				tris = [p00, p10, p01, p10, p11, p01]
			for v: Vector3 in tris:
				st.set_color(col)
				st.set_uv(Vector2(grassy, 1.0 if t == WorldMap.Terrain.POISON else 0.0))
				st.add_vertex(v)
	terrain_vertex_count = n * n * 6
	st.generate_normals()  # без индексов => плоское затенение
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = st.commit()
	var shader := Shader.new()
	shader.code = TERRAIN_SHADER
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = shader
	mi.material_override = terrain_material
	add_child(mi)
	apply_season(1.0, Color.WHITE, 0.0)


## Сезонный вид (SeasonVisuals): снег 0..1, оттенок и доля «травы» на земле, цвет деревьев.
func apply_season(snow: float, grass_tint: Color, grass_amount: float) -> void:
	if terrain_material != null:
		terrain_material.set_shader_parameter("snow_cover", snow)
		terrain_material.set_shader_parameter("grass_tint", Vector3(grass_tint.r, grass_tint.g, grass_tint.b))
		terrain_material.set_shader_parameter("grass_amount", grass_amount)
	if _tree_mat != null:
		var tint := Color.WHITE.lerp(grass_tint, grass_amount * 0.5)
		var c := TREE_COLOR.lerp(SNOW, 0.35 * snow)
		_tree_mat.albedo_color = Color(c.r * tint.r, c.g * tint.g, c.b * tint.b)
		if _tree_sm != null:
			_tree_sm.set_shader_parameter("albedo", Vector3(_tree_mat.albedo_color.r, _tree_mat.albedo_color.g, _tree_mat.albedo_color.b))


## Ветер: амплитуда качания деревьев (0 — штиль). WeatherVisuals зовёт при ветреных событиях.
func set_tree_sway(amount: float) -> void:
	if _tree_sm != null:
		_tree_sm.set_shader_parameter("sway", amount)


func _build_water() -> void:
	var ws := map.get_world_size()
	var pm := PlaneMesh.new()
	pm.size = Vector2(ws, ws)
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = pm
	mi.position = Vector3(ws * 0.5, WorldMap.WATER_LEVEL - 0.05, ws * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.45, 0.55, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.25
	mi.material_override = mat
	_water_mat = mat
	add_child(mi)


## Чистота воды 0..1 (шаг 17): грязная — мутная жёлто-бурая, чистая — прозрачно-голубая.
func set_water_clarity(c: float) -> void:
	if _water_mat != null:
		var k := clampf(c, 0.0, 1.0)
		_water_mat.albedo_color = Color(0.36, 0.38, 0.30, 0.92).lerp(Color(0.22, 0.48, 0.62, 0.78), k)


func _make_multimesh(node_name: String, mesh: Mesh, color: Color, xforms: Array[Transform3D]) -> StandardMaterial3D:
	if xforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)
	return mat


func _build_props() -> void:
	var trees: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var blocks: Array[Transform3D] = []
	var cs := map.cell_size
	for cz in map.size:
		for cx in map.size:
			var t := map.cell_type(cx, cz)
			var jx := map.hash01(cx, cz, 11)
			var jz := map.hash01(cx, cz, 12)
			var x := (cx + 0.2 + jx * 0.6) * cs
			var z := (cz + 0.2 + jz * 0.6) * cs
			var y := map.height_at(x, z)
			match t:
				WorldMap.Terrain.FOREST:
					for k in 2:
						var tx := x + (map.hash01(cx, cz, 20 + k) - 0.5) * cs * 0.7
						var tz := z + (map.hash01(cx, cz, 30 + k) - 0.5) * cs * 0.7
						var s := 0.8 + map.hash01(cx, cz, 40 + k) * 0.7
						var b := Basis.from_scale(Vector3(s, s, s))
						var txf := Transform3D(b, Vector3(tx, map.height_at(tx, tz) + 1.5 * s, tz))
						if not _tree_slots.has(cz * map.size + cx):
							_tree_slots[cz * map.size + cx] = []
						_tree_slots[cz * map.size + cx].append([trees.size(), txf])
						trees.append(txf)
				WorldMap.Terrain.GROUND, WorldMap.Terrain.POISON:
					if map.hash01(cx, cz, 50) < 0.06:
						var s := 0.4 + map.hash01(cx, cz, 51) * 0.6
						var b := Basis.from_euler(Vector3(0, jx * TAU, 0)).scaled(Vector3(s * 1.3, s, s))
						rocks.append(Transform3D(b, Vector3(x, y + s * 0.3, z)))
				WorldMap.Terrain.RUINS:
					var w := 1.0 + map.hash01(cx, cz, 60) * 0.8
					var hgt := 0.8 + map.hash01(cx, cz, 61) * 2.2
					var b := Basis.from_euler(Vector3(0, (jx - 0.5) * 0.6, 0)).scaled(Vector3(w, hgt, w))
					var xf := Transform3D(b, Vector3((cx + 0.5) * cs, y + hgt * 0.5 - 0.1, (cz + 0.5) * cs))
					_ruin_slots[cz * map.size + cx] = [blocks.size(), xf]
					blocks.append(xf)
	# Заводское здание и труба в центре.
	var fc := map.factory_cell
	var fp := map.cell_center(fc.x, fc.y)
	blocks.append(Transform3D(Basis.from_scale(Vector3(5.0, 5.0, 3.5)), fp + Vector3(0, 2.4, 0)))
	var chim: Array[Transform3D] = [Transform3D(Basis.from_scale(Vector3(1.0, 9.0, 1.0)), fp + Vector3(3.2, 4.5, 1.0))]

	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.7
	cone.height = 3.0
	cone.radial_segments = 5
	cone.rings = 1
	_tree_mat = _make_multimesh("Trees", cone, TREE_COLOR.lerp(SNOW, 0.25), trees)
	var trees_node := get_node_or_null("Trees") as MultiMeshInstance3D
	if trees_node != null:
		var tsh := Shader.new()
		tsh.code = TREE_SHADER
		_tree_sm = ShaderMaterial.new()
		_tree_sm.shader = tsh
		trees_node.material_override = _tree_sm
	_tree_mm = trees_node.multimesh if trees_node != null else null
	_trees_rev = -1

	var rock := SphereMesh.new()
	rock.radial_segments = 5
	rock.rings = 3
	rock.radius = 0.5
	rock.height = 1.0
	_make_multimesh("Rocks", rock, Color(0.45, 0.45, 0.45), rocks)

	_make_multimesh("Ruins", BoxMesh.new(), Color(0.42, 0.40, 0.38), blocks)
	var ruins_node := get_node_or_null("Ruins") as MultiMeshInstance3D
	_ruin_mm = ruins_node.multimesh if ruins_node != null else null

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.4
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	_make_multimesh("Chimney", cyl, Color(0.33, 0.30, 0.28), chim)


## Показывает блоки только активных руин (разобранные/восстановленные скрываются).
func sync_ruins(con: ConstructionSystem) -> void:
	if _ruin_mm == null:
		return
	for cell_idx in _ruin_slots:
		var slot: Array = _ruin_slots[cell_idx]
		var xf: Transform3D = slot[1]
		if not con.is_ruin_active(cell_idx):
			xf = Transform3D(Basis.from_scale(Vector3.ZERO), xf.origin)
		_ruin_mm.set_instance_transform(slot[0], xf)


## Скрывает деревья клеток, где лес вырублен (запас Deposits = 0).
func sync_trees(deposits: Deposits) -> void:
	if _tree_mm == null or deposits.revision == _trees_rev:
		return
	_trees_rev = deposits.revision
	for idx in _tree_slots:
		var gone := deposits.remaining(Vector2i(idx % map.size, idx / map.size)) <= 0
		for slot in _tree_slots[idx]:
			var xf: Transform3D = slot[1]
			if gone:
				xf = Transform3D(Basis.from_scale(Vector3.ZERO), xf.origin)
			_tree_mm.set_instance_transform(slot[0], xf)
