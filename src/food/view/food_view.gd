class_name FoodView
extends Node3D
## Step 16 (design/gdd/food.md): draws field cells (by crop/stage) and low-poly wild herds.

const REFRESH := 1.5
const FIELD_LIFT := 0.05
const COLOR_DESIGNATED := Color(0.55, 0.45, 0.28, 0.75)
const COLOR_PLOWED := Color(0.30, 0.20, 0.12)
const COLOR_SOWN := Color(0.25, 0.45, 0.18)
const RIPE_COLORS := {&"grain": Color(0.90, 0.78, 0.25), &"potato": Color(0.45, 0.55, 0.22), &"rapeseed": Color(0.95, 0.88, 0.15)}
const DEER_COLOR := Color(0.50, 0.33, 0.18)
const HARE_COLOR := Color(0.62, 0.58, 0.52)
const MAX_PER_REGION := 12

var food: FoodSystem
var world: WorldMap
var _fields: MeshInstance3D
var _herds: Dictionary = {}     # region id -> Array[Node3D]
var _acc := REFRESH
var _dirty := true
var _last_pos: Dictionary = {}


func setup(food_in: FoodSystem, world_in: WorldMap, sim: Simulation) -> void:
	food = food_in
	world = world_in
	_fields = MeshInstance3D.new()
	_fields.name = "Fields"
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	_fields.material_override = m
	add_child(_fields)
	sim.bus.subscribe(FoodSystem.TOPIC_CHANGED, func(_p: Dictionary) -> void: _dirty = true)


func _process(delta: float) -> void:
	update(delta)


## Frame update (also called directly by tests/screenshots).
func update(delta: float) -> void:
	if food == null:
		return
	_acc += delta
	if _dirty or _acc >= REFRESH:
		_acc = 0.0
		_dirty = false
		rebuild_fields()
	_sync_herds(delta)


func field_color(f: Dictionary) -> Color:
	match f["stage"]:
		FoodSystem.Stage.PLOWED:
			return COLOR_PLOWED
		FoodSystem.Stage.SOWN:
			return COLOR_PLOWED.lerp(COLOR_SOWN, clampf(0.35 + f["growth"], 0.0, 1.0)).lerp(RIPE_COLORS[f["crop"]], clampf(f["growth"] - 0.6, 0.0, 0.4) * 2.0)
		FoodSystem.Stage.RIPE:
			return RIPE_COLORS[f["crop"]]
	return COLOR_DESIGNATED


func rebuild_fields() -> void:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var cs := world.cell_size
	for i in food.fields:
		var f: Dictionary = food.fields[i]
		var c := world.cell_center(i % world.size, i / world.size)
		var col := field_color(f)
		var base := verts.size()
		for k in 4:
			var x := c.x + ((k & 1) - 0.5) * cs
			var z := c.z + ((k >> 1) - 0.5) * cs
			verts.append(Vector3(x, world.height_at(x, z) + FIELD_LIFT, z))
			norms.append(Vector3.UP)
			cols.append(col)
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	if verts.is_empty():
		_fields.mesh = null
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_fields.mesh = mesh


func _make_animal(species: StringName) -> Node3D:
	var n := Node3D.new()
	var col: Color = DEER_COLOR if species == &"deer" else HARE_COLOR
	var s := 1.0 if species == &"deer" else 0.4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	var parts := [[Vector3(0.9, 0.5, 0.4), Vector3(0, 0.85, 0)], [Vector3(0.25, 0.3, 0.25), Vector3(0.55, 1.15, 0)],
		[Vector3(0.12, 0.6, 0.12), Vector3(0.3, 0.3, 0.12)], [Vector3(0.12, 0.6, 0.12), Vector3(0.3, 0.3, -0.12)],
		[Vector3(0.12, 0.6, 0.12), Vector3(-0.3, 0.3, 0.12)], [Vector3(0.12, 0.6, 0.12), Vector3(-0.3, 0.3, -0.12)]]
	for p in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[0] * s
		mi.mesh = bm
		mi.position = p[1] * s
		mi.material_override = mat
		n.add_child(mi)
	add_child(n)
	return n


func _sync_herds(_delta: float) -> void:
	for r in food.regions:
		var want := mini(food.region_visible_animals(r), MAX_PER_REGION)
		var list: Array = _herds.get(r["id"], [])
		while list.size() > want:
			(list.pop_back() as Node3D).queue_free()
		while list.size() < want:
			list.append(_make_animal(r["species"]))
		_herds[r["id"]] = list
		var p: Vector3 = r["pos"]
		for k in list.size():
			var a := float(k) * 2.4 + float(r["id"])
			var off := Vector3(cos(a), 0.0, sin(a)) * (1.5 + 0.8 * float(k % 4))
			var pos := Vector3(p.x + off.x, 0.0, p.z + off.z)
			pos.y = world.height_at(pos.x, pos.z)
			var n: Node3D = list[k]
			var old: Vector3 = n.position
			n.position = pos
			if pos.distance_to(old) > 0.01:
				n.rotation.y = atan2(-(pos.z - old.z), pos.x - old.x)
