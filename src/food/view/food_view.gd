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
## Crops on fields (design/gdd/food.md, step 17): stage by growth, low-poly MultiMesh (9 plants per cell).
enum { CROP_NONE, CROP_SPROUT, CROP_TALL, CROP_RIPE }
const CROP_GRID := 3
const SPROUT_UNTIL := 0.35            # growth fraction: sprouts below, tall plants above
const CROP_COLORS := {
	&"grain": [Color(0.45, 0.65, 0.25), Color(0.55, 0.70, 0.25), Color(0.92, 0.76, 0.22)],
	&"potato": [Color(0.40, 0.62, 0.25), Color(0.28, 0.52, 0.20), Color(0.30, 0.50, 0.18)],
	&"rapeseed": [Color(0.42, 0.64, 0.26), Color(0.38, 0.60, 0.22), Color(0.97, 0.88, 0.12)],
}
## Plant size (x/z radius, height) per crop and stage (sprout, tall, ripe), metres.
const CROP_SIZE := {
	&"grain": [Vector2(0.10, 0.18), Vector2(0.12, 0.65), Vector2(0.12, 0.95)],
	&"potato": [Vector2(0.16, 0.14), Vector2(0.38, 0.38), Vector2(0.44, 0.45)],
	&"rapeseed": [Vector2(0.12, 0.18), Vector2(0.16, 0.7), Vector2(0.30, 0.85)],
}

var food: FoodSystem
var world: WorldMap
var _fields: MeshInstance3D
var _crops: MultiMeshInstance3D
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
	_crops = MultiMeshInstance3D.new()
	_crops.name = "Crops"
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.roughness = 1.0
	_crops.material_override = cm
	add_child(_crops)
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
		rebuild_crops()
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


# ---------- crops ----------

## Visual stage of a field cell dictionary (FoodSystem.fields value).
func crop_stage(f: Dictionary) -> int:
	match f["stage"]:
		FoodSystem.Stage.SOWN:
			return CROP_SPROUT if f["growth"] < SPROUT_UNTIL else CROP_TALL
		FoodSystem.Stage.RIPE:
			return CROP_RIPE
	return CROP_NONE


func crop_color(crop: StringName, stage: int) -> Color:
	return CROP_COLORS[crop][clampi(stage, CROP_SPROUT, CROP_RIPE) - 1]


func crop_count() -> int:
	return _crops.multimesh.visible_instance_count if _crops != null and _crops.multimesh != null else 0


static func _plant_mesh() -> ArrayMesh:
	# 4-sided pyramid, base radius 1, height 1 (scaled per plant)
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var tip := Vector3(0, 1, 0)
	for k in 4:
		var a0 := float(k) * TAU / 4.0
		var a1 := float(k + 1) * TAU / 4.0
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		v.append_array(PackedVector3Array([p0, tip, p1]))
		var nn := (tip - p0).cross(p1 - p0).normalized()
		n.append_array(PackedVector3Array([nn, nn, nn]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func rebuild_crops() -> void:
	if _crops == null or food == null:
		return
	var items: Array = []
	var cs := world.cell_size
	var step := cs / float(CROP_GRID)
	for i in food.fields:
		var f: Dictionary = food.fields[i]
		var st := crop_stage(f)
		if st == CROP_NONE:
			continue
		var cx: int = i % world.size
		var cz: int = i / world.size
		var c := world.cell_center(cx, cz)
		var sz: Vector2 = CROP_SIZE[f["crop"]][st - 1]
		var grow := 1.0
		if st != CROP_RIPE:
			grow = 0.8 + 0.2 * clampf(f["growth"], 0.0, 1.0)
		var col := crop_color(f["crop"], st)
		for gz in CROP_GRID:
			for gx in CROP_GRID:
				var h := world.hash01(cx * 7 + gx, cz * 7 + gz, 733)
				var px := c.x - cs * 0.5 + (gx + 0.5) * step + (h - 0.5) * step * 0.4
				var pz := c.z - cs * 0.5 + (gz + 0.5) * step + (world.hash01(cx * 7 + gx, cz * 7 + gz, 734) - 0.5) * step * 0.4
				var s := Vector3(sz.x, sz.y * grow * (0.85 + 0.3 * h), sz.x)
				items.append([Transform3D(Basis.from_scale(s), Vector3(px, world.height_at(px, pz) + FIELD_LIFT, pz)), col])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _plant_mesh()
	mm.instance_count = items.size()
	for k in items.size():
		mm.set_instance_transform(k, items[k][0])
		mm.set_instance_color(k, items[k][1])
	mm.visible_instance_count = items.size()
	_crops.multimesh = mm
