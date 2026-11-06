class_name RestorationView
extends Node3D
## Step 17 (design/gdd/land-restoration.md): saplings, restored trees on bare ground, marks, healing poison
## (sickly colour fades to normal), cleansing vegetation, water colour. Low-poly MultiMesh, refreshed on change.

const REFRESH := 2.0
const LIFT := 0.06
const MARK_COLOR := Color(0.35, 0.65, 0.30, 0.55)
const SICK := Color(0.55, 0.48, 0.24)
const HEALTHY := Color(0.30, 0.42, 0.20)
const SAPLING_COLOR := Color(0.30, 0.58, 0.22)
const TREE_COLOR := Color(0.20, 0.38, 0.20)
const HERB_COLOR := Color(0.45, 0.70, 0.30)

var rs: RestorationSystem
var world: WorldMap
var deposits: Deposits
var world_view: WorldView
var _overlay: MeshInstance3D
var _plants: MultiMeshInstance3D
var _dirty := true
var _acc := REFRESH
var _rev := -1
var plant_count := 0        # drawn plants (tests/screenshots)


func setup(rs_in: RestorationSystem, world_in: WorldMap, deposits_in: Deposits, wv: WorldView, sim: Simulation) -> void:
	rs = rs_in
	world = world_in
	deposits = deposits_in
	world_view = wv
	_overlay = MeshInstance3D.new()
	_overlay.name = "Overlay"
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	_overlay.material_override = m
	add_child(_overlay)
	_plants = MultiMeshInstance3D.new()
	_plants.name = "Plants"
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	_plants.material_override = pm
	add_child(_plants)
	sim.bus.subscribe(RestorationSystem.TOPIC_CHANGED, func(_p: Dictionary) -> void: _dirty = true)


func _process(delta: float) -> void:
	update(delta)


func update(delta: float) -> void:
	if rs == null:
		return
	_acc += delta
	if _dirty or _acc >= REFRESH or deposits.revision != _rev:
		_acc = 0.0
		_dirty = false
		_rev = deposits.revision
		rebuild()
	if world_view != null:
		world_view.set_water_clarity(rs.water_clarity())


## Colour of a poison cell by level (1 sickly .. 0 normal).
static func poison_color(level: float) -> Color:
	return HEALTHY.lerp(SICK, clampf(level, 0.0, 1.0))


func rebuild() -> void:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var quad := func(i: int, col: Color) -> void:
		var c := world.cell_center(i % world.size, i / world.size)
		var cs := world.cell_size
		var base := verts.size()
		for k in 4:
			var x: float = c.x + ((k & 1) - 0.5) * cs
			var z: float = c.z + ((k >> 1) - 0.5) * cs
			verts.append(Vector3(x, world.height_at(x, z) + LIFT, z))
			norms.append(Vector3.UP)
			cols.append(col)
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	for i in rs.plant_marks:
		quad.call(i, MARK_COLOR)
	for i in rs.treat_marks:
		quad.call(i, Color(0.6, 0.55, 0.2, 0.6))
	for i in rs.treated:
		var c := Vector2i(i % world.size, i / world.size)
		quad.call(i, poison_color(rs.poison_at(c)))
	for i in rs.poison:
		if not rs.treated.has(i) and rs.poison[i] <= RestorationDefs.POISON_EPS:
			quad.call(i, poison_color(0.0))
	if verts.is_empty():
		_overlay.mesh = null
	else:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_overlay.mesh = mesh
	_rebuild_plants()


func _rebuild_plants() -> void:
	var items: Array = []
	var add := func(i: int, h: float, r: float, col: Color, n: int) -> void:
		var cx: int = i % world.size
		var cz: int = i / world.size
		var c := world.cell_center(cx, cz)
		for k in n:
			var ox := (world.hash01(cx, cz, 900 + k) - 0.5) * world.cell_size * 0.7
			var oz := (world.hash01(cx, cz, 950 + k) - 0.5) * world.cell_size * 0.7
			var x: float = c.x + ox
			var z: float = c.z + oz
			items.append([Transform3D(Basis.from_scale(Vector3(r, h, r)), Vector3(x, world.height_at(x, z), z)), col])
	for i in rs.saplings:
		var g: float = rs.saplings[i]
		add.call(i, 0.5 + 1.0 * g, 0.18 + 0.2 * g, SAPLING_COLOR, 1)
	for i in rs.grown:
		var c := Vector2i(i % world.size, i / world.size)
		if world.cell_type(c.x, c.y) != WorldMap.Terrain.FOREST and deposits.remaining(c) > 0:
			add.call(i, 3.2, 0.8, TREE_COLOR, 2)  # bare-ground trees (forest cells are drawn by WorldView)
	for i in rs.treated:
		var c := Vector2i(i % world.size, i / world.size)
		add.call(i, 0.45, 0.22, HERB_COLOR, 4)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = FoodView._plant_mesh()
	mm.instance_count = items.size()
	for k in items.size():
		mm.set_instance_transform(k, items[k][0])
		mm.set_instance_color(k, items[k][1])
	_plants.multimesh = mm
	plant_count = items.size()
