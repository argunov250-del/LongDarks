class_name VehiclesView
extends Node3D
## Vehicle meshes (low-poly placeholders, distinct silhouettes) and the three ground layers:
## footpaths (light beaten earth blobs), ruts (two dark wheel tracks, deeper in mud, packed track in snow),
## roads (gravel strip). Design: design/gdd/vehicles.md.

const REFRESH := 0.5
var vs: VehicleSystem
var world: WorldMap
var _nodes: Dictionary = {}
var _overlay: MeshInstance3D
var _rev := -1
var _acc := REFRESH
var layer_counts := {"foot": 0, "ruts": 0, "roads": 0}   # drawn cells (tests/screenshots)


func setup(vs_in: VehicleSystem, world_in: WorldMap, sim: Simulation) -> void:
	vs = vs_in
	world = world_in
	_overlay = MeshInstance3D.new()
	_overlay.name = "TrailOverlay"
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_is_srgb = true
	_overlay.material_override = m
	add_child(_overlay)


func _process(delta: float) -> void:
	update(delta)


func update(delta: float) -> void:
	if vs == null:
		return
	_sync_vehicles()
	_acc += delta
	if _acc >= REFRESH or vs.trails.view_revision != _rev:
		_acc = 0.0
		if vs.trails.view_revision != _rev:
			_rev = vs.trails.view_revision
			rebuild_trails()


func _sync_vehicles() -> void:
	for id in _nodes.keys():
		if not vs.vehicles.has(id):
			_nodes[id].queue_free()
			_nodes.erase(id)
	for id in vs.vehicles:
		var v: Vehicle = vs.vehicles[id]
		if not _nodes.has(id):
			var n := build_mesh(v.type)
			n.name = "Vehicle%d" % id
			add_child(n)
			_nodes[id] = n
		var nd: Node3D = _nodes[id]
		nd.position = v.pos
		nd.rotation.y = v.facing


func vehicle_node(id: int) -> Node3D:
	return _nodes.get(id)


# ---------- meshes ----------

static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot_x := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation.x = rot_x
	parent.add_child(mi)


static func _wheel(parent: Node3D, r: float, w: float, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = w
	cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = _mat(Color(0.08, 0.08, 0.08))
	mi.rotation.z = PI / 2.0
	mi.position = pos
	parent.add_child(mi)


## Forward is +Z. Dimensions in metres.
static func build_mesh(type: StringName) -> Node3D:
	var n := Node3D.new()
	var c: Color = VehicleDefs.def(type)["color"]
	var dark := c.darkened(0.35)
	var glass := Color(0.25, 0.32, 0.38)
	match type:
		&"truck":
			_box(n, Vector3(2.4, 1.8, 1.8), Vector3(0, 1.5, 2.2), c)
			_box(n, Vector3(2.2, 0.3, 4.2), Vector3(0, 0.9, -1.0), dark)
			_box(n, Vector3(2.3, 1.1, 4.0), Vector3(0, 1.6, -1.0), c.darkened(0.15))
			for z in [2.2, -0.4, -2.4]:
				_wheel(n, 0.55, 0.4, Vector3(1.1, 0.55, z))
				_wheel(n, 0.55, 0.4, Vector3(-1.1, 0.55, z))
		&"pickup":
			_box(n, Vector3(1.8, 1.3, 1.5), Vector3(0, 1.1, 0.9), c)
			_box(n, Vector3(1.6, 0.35, 0.05), Vector3(0, 1.4, 1.65), glass)
			_box(n, Vector3(1.8, 0.7, 1.8), Vector3(0, 0.85, -1.2), dark)
			for z in [1.0, -1.3]:
				_wheel(n, 0.4, 0.3, Vector3(0.9, 0.4, z))
				_wheel(n, 0.4, 0.3, Vector3(-0.9, 0.4, z))
		&"offroad":
			_box(n, Vector3(2.0, 1.7, 2.2), Vector3(0, 1.5, 1.4), c)
			_box(n, Vector3(2.0, 0.5, 3.0), Vector3(0, 1.1, -1.4), dark)
			_box(n, Vector3(0.1, 0.9, 3.0), Vector3(1.0, 1.7, -1.4), dark)
			_box(n, Vector3(0.1, 0.9, 3.0), Vector3(-1.0, 1.7, -1.4), dark)
			for z in [1.5, -1.8]:
				_wheel(n, 0.7, 0.5, Vector3(1.05, 0.7, z))
				_wheel(n, 0.7, 0.5, Vector3(-1.05, 0.7, z))
		&"tractor":
			_box(n, Vector3(1.0, 0.9, 1.8), Vector3(0, 1.1, 1.2), c)
			_box(n, Vector3(1.6, 1.8, 1.4), Vector3(0, 1.8, -0.6), c.darkened(0.1))
			_box(n, Vector3(1.4, 0.4, 1.2), Vector3(0, 2.8, -0.6), dark)
			_wheel(n, 0.9, 0.55, Vector3(1.1, 0.9, -0.8))
			_wheel(n, 0.9, 0.55, Vector3(-1.1, 0.9, -0.8))
			_wheel(n, 0.5, 0.3, Vector3(0.8, 0.5, 1.6))
			_wheel(n, 0.5, 0.3, Vector3(-0.8, 0.5, 1.6))
		&"combine":
			_box(n, Vector3(5.0, 0.5, 0.8), Vector3(0, 0.6, 3.4), dark)
			_box(n, Vector3(3.0, 2.2, 4.0), Vector3(0, 1.9, 0.0), c)
			_box(n, Vector3(1.8, 1.4, 1.6), Vector3(0, 3.6, 1.2), glass)
			_box(n, Vector3(1.0, 1.0, 2.6), Vector3(1.0, 3.5, -1.8), c.darkened(0.2))
			_wheel(n, 0.9, 0.6, Vector3(1.5, 0.9, 1.0))
			_wheel(n, 0.9, 0.6, Vector3(-1.5, 0.9, 1.0))
			_wheel(n, 0.6, 0.4, Vector3(1.3, 0.6, -1.7))
			_wheel(n, 0.6, 0.4, Vector3(-1.3, 0.6, -1.7))
		&"excavator":
			_box(n, Vector3(0.9, 0.8, 4.0), Vector3(1.0, 0.4, 0), Color(0.15, 0.15, 0.15))
			_box(n, Vector3(0.9, 0.8, 4.0), Vector3(-1.0, 0.4, 0), Color(0.15, 0.15, 0.15))
			_box(n, Vector3(2.6, 1.0, 3.0), Vector3(0, 1.3, -0.3), c)
			_box(n, Vector3(1.4, 1.4, 1.4), Vector3(0.4, 2.4, 0.4), glass)
			_box(n, Vector3(0.5, 0.5, 3.6), Vector3(-0.6, 2.4, 2.4), c.darkened(0.2), -0.5)
			_box(n, Vector3(0.4, 0.4, 2.4), Vector3(-0.6, 2.2, 4.4), dark, 0.9)
		&"bulldozer":
			_box(n, Vector3(0.9, 0.9, 4.0), Vector3(1.1, 0.45, 0), Color(0.15, 0.15, 0.15))
			_box(n, Vector3(0.9, 0.9, 4.0), Vector3(-1.1, 0.45, 0), Color(0.15, 0.15, 0.15))
			_box(n, Vector3(2.0, 1.1, 2.8), Vector3(0, 1.4, 0.3), c)
			_box(n, Vector3(1.6, 1.4, 1.3), Vector3(0, 2.5, -0.7), c.darkened(0.1))
			_box(n, Vector3(3.8, 1.3, 0.3), Vector3(0, 1.0, 2.8), dark)
		&"crane":
			_box(n, Vector3(2.4, 1.0, 6.0), Vector3(0, 1.0, 0), c)
			_box(n, Vector3(1.8, 1.6, 1.6), Vector3(0, 2.2, 2.2), glass)
			_box(n, Vector3(0.5, 0.5, 8.0), Vector3(0, 5.0, -1.0), dark, -0.55)
			_box(n, Vector3(0.1, 3.0, 0.1), Vector3(0, 7.2, 2.6), Color(0.1, 0.1, 0.1))
			for z in [2.0, 0.0, -2.2]:
				_wheel(n, 0.6, 0.4, Vector3(1.2, 0.6, z))
				_wheel(n, 0.6, 0.4, Vector3(-1.2, 0.6, z))
		&"atv":
			_box(n, Vector3(1.8, 1.0, 3.8), Vector3(0, 0.9, 0), c)
			_box(n, Vector3(1.4, 0.8, 1.6), Vector3(0, 1.7, 0.4), c.darkened(0.1))
			for z in [1.3, 0.0, -1.3]:
				_wheel(n, 0.65, 0.6, Vector3(1.1, 0.65, z))
				_wheel(n, 0.65, 0.6, Vector3(-1.1, 0.65, z))
		&"snowmobile":
			_box(n, Vector3(0.7, 0.5, 1.6), Vector3(0, 0.65, -0.2), c)
			_box(n, Vector3(0.4, 0.4, 0.8), Vector3(0, 0.55, 0.9), c.darkened(0.2))
			_box(n, Vector3(0.12, 0.08, 1.0), Vector3(0.3, 0.1, 1.0), dark)
			_box(n, Vector3(0.12, 0.08, 1.0), Vector3(-0.3, 0.1, 1.0), dark)
			_box(n, Vector3(0.5, 0.2, 1.4), Vector3(0, 0.15, -0.7), Color(0.1, 0.1, 0.1))
	return n


# ---------- ground layers ----------

func _h(x: float, z: float) -> float:
	return world.height_at(x, z) + 0.07


func rebuild_trails() -> void:
	var tm := vs.trails
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var snow := vs.snow_override if vs.snow_override >= 0.0 else (vs.seasons.snow_cover() if vs.seasons != null else 0.0)
	var mud := vs.mud_override if vs.mud_override >= 0.0 else (vs.seasons.mud_level() if vs.seasons != null else 0.0)
	# oriented quad: centre, unit axis (a), half-length hl along a, half-width hw across
	var quad := func(cx: float, cz: float, ax: float, az: float, hl: float, hw: float, col: Color) -> void:
		var b := verts.size()
		for p in [Vector2(-hl, -hw), Vector2(hl, -hw), Vector2(hl, hw), Vector2(-hl, hw)]:
			var x: float = cx + ax * p.x - az * p.y
			var z: float = cz + az * p.x + ax * p.y
			verts.append(Vector3(x, _h(x, z), z))
			cols.append(col)
			norms.append(Vector3.UP)
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var cs := world.cell_size
	layer_counts = {"foot": 0, "ruts": 0, "roads": 0}
	for i in tm.roads:
		var c := world.cell_center(i % world.size, i / world.size)
		quad.call(c.x, c.z, 1.0, 0.0, cs * 0.5, cs * 0.5, Color(0.50, 0.46, 0.40, 1.0))
		quad.call(c.x, c.z, 1.0, 0.0, cs * 0.5, cs * 0.18, Color(0.62, 0.58, 0.50, 1.0))
		layer_counts["roads"] += 1
	for i in tm.foot:
		var lv := tm.foot_level(i)
		if lv < VehicleDefs.TRAIL_VISIBLE:
			continue
		var c := world.cell_center(i % world.size, i / world.size)
		var a := world.hash01(i % world.size, i / world.size, 9) * PI
		quad.call(c.x, c.z, cos(a), sin(a), cs * 0.45, cs * 0.28, Color(0.62, 0.52, 0.36, 0.25 + 0.6 * lv))
		layer_counts["foot"] += 1
	for i in tm.ruts:
		var lv := tm.rut_level(i)
		if lv < VehicleDefs.TRAIL_VISIBLE:
			continue
		var cx: int = i % world.size
		var cz: int = i / world.size
		var c := world.cell_center(cx, cz)
		var ax := 1.0
		var az := 0.0
		if not (tm.ruts.has(i + 1) or tm.ruts.has(i - 1)) and (tm.ruts.has(i + world.size) or tm.ruts.has(i - world.size)):
			ax = 0.0
			az = 1.0
		var col := Color(0.14, 0.10, 0.07, 0.35 + 0.55 * lv).lerp(Color(0.06, 0.04, 0.03, 0.9), mud * 0.7)
		if snow > 0.5:
			col = Color(0.78, 0.82, 0.88, 0.5 + 0.4 * lv)
		for side in [-1.0, 1.0]:
			quad.call(c.x - az * side * 0.45, c.z + ax * side * 0.45, ax, az, cs * 0.5, 0.24, col)
		layer_counts["ruts"] += 1
	if verts.is_empty():
		_overlay.mesh = null
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_overlay.mesh = mesh
