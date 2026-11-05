class_name BuildingMeshes
extends RefCounted
## Low-poly заглушки зданий: плита фундамента, стены, крыша-призма.
## Геометрия видна по стадиям: на текущей стадии элемент растёт вместе с прогрессом.
## Начало координат — центр основания на земле; ось X — ширина, Z — глубина.

const SLAB_H := 0.35
const SLAB_PAD := 0.3
const ROOF_PAD := 0.3
const TAB_COLORS := {
	BuildingDefs.Tab.HOUSING: Color(0.62, 0.45, 0.30),
	BuildingDefs.Tab.PRODUCTION: Color(0.45, 0.50, 0.58),
	BuildingDefs.Tab.SOCIAL: Color(0.55, 0.62, 0.45),
	BuildingDefs.Tab.DEFENSE: Color(0.50, 0.30, 0.28),
}
const SLAB_COLOR := Color(0.55, 0.55, 0.55)
const ROOF_COLOR := Color(0.28, 0.22, 0.20)
const GHOST_OK := Color(0.25, 0.90, 0.35, 0.55)
const GHOST_BAD := Color(0.95, 0.25, 0.20, 0.55)


static func wall_color(type: StringName) -> Color:
	var c: Color = TAB_COLORS[BuildingDefs.tab_of(type)]
	return c.lerp(Color(0.9, 0.9, 0.95), 0.15 * float(BuildingDefs.upgrade_tier(type)))


## Какая геометрия видна: [доля плиты, доля стен, доля крыши], каждая в [0,1].
static func stage_parts(stage: int, frac: float) -> Array[float]:
	var f := clampf(frac, 0.0, 1.0)
	var slab := 1.0 if stage > BuildingDefs.Stage.FOUNDATION else (f if stage == BuildingDefs.Stage.FOUNDATION else 1.0)
	var walls := 0.0
	if stage > BuildingDefs.Stage.WALLS:
		walls = 1.0
	elif stage == BuildingDefs.Stage.WALLS:
		walls = f
	var roof := 0.0
	if stage > BuildingDefs.Stage.ROOF:
		roof = 1.0
	elif stage == BuildingDefs.Stage.ROOF:
		roof = f
	return [slab, walls, roof]


static func _mat(c: Color, ghost: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	if ghost:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


## frac — прогресс текущей стадии. ghost_color != null -> полупрозрачный призрак целого здания.
static func make(type: StringName, stage: int, frac: float, ghost_color = null) -> Node3D:
	var root := Node3D.new()
	var ghost := ghost_color != null
	var parts := stage_parts(BuildingDefs.Stage.DONE if ghost else stage, frac)
	var size := BuildingDefs.footprint(type)
	var wh := BuildingDefs.wall_height(type)
	var slab_c: Color = ghost_color if ghost else SLAB_COLOR
	var wall_c: Color = ghost_color if ghost else wall_color(type)
	var roof_c: Color = ghost_color if ghost else ROOF_COLOR
	var thin := size.y < 1.0  # забор: узкая стенка без плиты и крыши
	if parts[0] > 0.0 and not thin:
		var h := SLAB_H * maxf(parts[0], 0.15)
		_box(root, "Foundation", Vector3(size.x + SLAB_PAD, h, size.y + SLAB_PAD), Vector3(0, h * 0.5 - 0.1, 0), _mat(slab_c, ghost))
	var base := SLAB_H - 0.1 if not thin else 0.0
	if thin and parts[0] > 0.0:
		var h2 := 0.25 * maxf(parts[0], 0.15)  # у забора «фундамент» — ленточка у земли
		_box(root, "Foundation", Vector3(size.x, h2, size.y + 0.1), Vector3(0, h2 * 0.5 - 0.05, 0), _mat(slab_c, ghost))
		base = 0.2
	var wall_top := base
	if parts[1] > 0.0:
		var h3 := wh * parts[1]
		_box(root, "Walls", Vector3(size.x, h3, size.y), Vector3(0, base + h3 * 0.5, 0), _mat(wall_c, ghost))
		wall_top = base + h3
	if parts[2] > 0.0 and not thin:
		var rh := (1.2 if type != &"watchtower" else 1.6) * parts[2]
		var pm := PrismMesh.new()
		pm.size = Vector3(size.x + ROOF_PAD, rh, size.y + ROOF_PAD)
		var mi := MeshInstance3D.new()
		mi.name = "Roof"
		mi.mesh = pm
		mi.position = Vector3(0, base + wh + rh * 0.5, 0)
		mi.material_override = _mat(roof_c, ghost)
		root.add_child(mi)
	return root


# ---------- двор жилья: забор, поленница, огород, сарай, печная труба ----------

const YARD_GROUND := Color(0.42, 0.34, 0.22)
const FENCE_COLOR := Color(0.55, 0.40, 0.25)
const LOG_COLOR := Color(0.50, 0.34, 0.20)
const FIREWOOD_COLOR := Color(0.72, 0.55, 0.34)
const SOIL_COLOR := Color(0.30, 0.22, 0.14)
const CROP_COLORS := {&"potato": Color(0.35, 0.60, 0.25), &"vegetables": Color(0.42, 0.70, 0.30)}
const RIPE_COLORS := {&"potato": Color(0.85, 0.80, 0.45), &"vegetables": Color(0.85, 0.35, 0.25)}
const BARN_COLOR := Color(0.55, 0.42, 0.30)
const WOODPILE_MAX_H := 0.9
const FENCE_POST_STEP := 1.0
const CHIMNEY_COLOR := Color(0.45, 0.42, 0.42)


static func _yl(local: Vector2) -> Vector3:
	return Vector3(HouseholdDefs.YARD_OFFSET.x + local.x, 0.0, HouseholdDefs.YARD_OFFSET.y + local.y)


static func _fence_side(parent: Node3D, from: Vector2, to: Vector2, mat: Material, gap_at_center: bool) -> void:
	var len := from.distance_to(to)
	var dir := (to - from) / len
	var n := int(round(len / FENCE_POST_STEP))
	for i in n + 1:
		var q := from + dir * (len * float(i) / float(n))
		if gap_at_center and absf(q.x) < HouseholdDefs.GATE_WIDTH * 0.5 and absf(dir.x) > 0.5:
			continue
		_box(parent, "Post", Vector3(0.12, HouseholdDefs.FENCE_HEIGHT, 0.12), _yl(q) + Vector3(0, HouseholdDefs.FENCE_HEIGHT * 0.5, 0), mat)
	var along := Vector3(absf(dir.x), 0.0, absf(dir.y))
	var rail_size := Vector3(len if along.x > 0.5 else 0.06, 0.08, len if along.z > 0.5 else 0.06)
	for hy in [0.35, 0.7]:
		if gap_at_center and along.x > 0.5:  # у калитки рейки разбиты на две части
			var seg := (len - HouseholdDefs.GATE_WIDTH) * 0.5
			for sgn in [-1.0, 1.0]:
				_box(parent, "Rail", Vector3(seg, 0.08, 0.06), _yl(Vector2(sgn * (HouseholdDefs.GATE_WIDTH * 0.5 + seg * 0.5), from.y)) + Vector3(0, hy, 0), mat)
		else:
			_box(parent, "Rail", rail_size, _yl((from + to) * 0.5) + Vector3(0, hy, 0), mat)


## Двор жилья (дочерний узел здания, начало — центр дома): грунт и низкий забор с калиткой.
## state (для готового жилья): {"wood": 0..1, "garden": StringName, "garden_frac": 0..1,
## "crop": StringName, "barn": bool, "done": bool (труба)}. ghost_color — призрак (только забор).
static func make_yard(type: StringName, state: Dictionary = {}, ghost_color = null) -> Node3D:
	var root := Node3D.new()
	root.name = "Yard"
	var ghost := ghost_color != null
	var half := HouseholdDefs.YARD_SIZE * 0.5
	var fence_mat := _mat(ghost_color if ghost else FENCE_COLOR, ghost)
	_box(root, "Ground", Vector3(HouseholdDefs.YARD_SIZE.x, 0.04, HouseholdDefs.YARD_SIZE.y), _yl(Vector2.ZERO) + Vector3(0, 0.02, 0), _mat(ghost_color if ghost else YARD_GROUND, ghost))
	var fence := Node3D.new()
	fence.name = "Fence"
	root.add_child(fence)
	_fence_side(fence, Vector2(-half.x, -half.y), Vector2(half.x, -half.y), fence_mat, true)  # со стороны дома — калитка
	_fence_side(fence, Vector2(-half.x, half.y), Vector2(half.x, half.y), fence_mat, false)
	_fence_side(fence, Vector2(-half.x, -half.y), Vector2(-half.x, half.y), fence_mat, false)
	_fence_side(fence, Vector2(half.x, -half.y), Vector2(half.x, half.y), fence_mat, false)
	if ghost or state.is_empty():
		return root
	# поленница: две стойки и штабель, высота = запас
	var wp := Node3D.new()
	wp.name = "Woodpile"
	root.add_child(wp)
	var wsz := HouseholdDefs.WOODPILE_SIZE
	var wpos := _yl(HouseholdDefs.WOODPILE_POS)
	for sx in [-1.0, 1.0]:
		_box(wp, "Stake", Vector3(0.1, WOODPILE_MAX_H + 0.1, 0.1), wpos + Vector3(sx * wsz.x * 0.5, (WOODPILE_MAX_H + 0.1) * 0.5, 0), _mat(FENCE_COLOR, false))
	var wh := WOODPILE_MAX_H * clampf(float(state.get("wood", 0.0)), 0.0, 1.0)
	if wh > 0.02:
		_box(wp, "Stack", Vector3(wsz.x, wh, wsz.y), wpos + Vector3(0, wh * 0.5, 0), _mat(FIREWOOD_COLOR, false))
	# огород: грядки, растения по росту
	var g := Node3D.new()
	g.name = "Garden"
	root.add_child(g)
	var gpos := _yl(HouseholdDefs.GARDEN_POS)
	_box(g, "Soil", Vector3(HouseholdDefs.GARDEN_SIZE.x, 0.08, HouseholdDefs.GARDEN_SIZE.y), gpos + Vector3(0, 0.06, 0), _mat(SOIL_COLOR, false))
	var gs: StringName = state.get("garden", &"empty")
	var gf := clampf(float(state.get("garden_frac", 0.0)), 0.0, 1.0)
	if gs != &"empty":
		var crop: StringName = state.get("crop", &"potato")
		var col: Color = RIPE_COLORS[crop] if gs == &"ripe" else CROP_COLORS[crop]
		var ph := 0.12 + 0.3 * gf
		for row in 3:
			for k in 4:
				var o := Vector2(-1.0 + float(row) * 1.0, -1.3 + float(k) * 0.85)
				_box(g, "Plant", Vector3(0.3, ph, 0.3), gpos + Vector3(o.x, 0.1 + ph * 0.5, o.y), _mat(col, false))
	# сарай с курами и коровой
	if state.get("barn", false):
		var b := Node3D.new()
		b.name = "Barn"
		root.add_child(b)
		var bpos := _yl(HouseholdDefs.BARN_POS)
		var bsz := HouseholdDefs.BARN_SIZE
		_box(b, "Walls", Vector3(bsz.x, 1.5, bsz.y), bpos + Vector3(0, 0.75, 0), _mat(BARN_COLOR, false))
		var pm := PrismMesh.new()
		pm.size = Vector3(bsz.x + 0.3, 0.7, bsz.y + 0.3)
		var roof := MeshInstance3D.new()
		roof.name = "Roof"
		roof.mesh = pm
		roof.position = bpos + Vector3(0, 1.5 + 0.35, 0)
		roof.material_override = _mat(ROOF_COLOR, false)
		b.add_child(roof)
		_box(b, "Cow", Vector3(0.5, 0.5, 0.9), bpos + Vector3(0.9, 0.25, bsz.y * 0.5 + 0.7), _mat(Color(0.92, 0.92, 0.9), false))
		for i in HouseholdDefs.CHICKENS:
			_box(b, "Chicken", Vector3(0.18, 0.18, 0.22), bpos + Vector3(-1.2 + 0.35 * i, 0.09, bsz.y * 0.5 + 0.5 + 0.15 * (i % 2)), _mat(Color(0.9, 0.75, 0.3), false))
	# печная труба на крыше готового дома (печь внутри)
	if state.get("done", false):
		var size := BuildingDefs.footprint(type)
		var top := SLAB_H - 0.1 + BuildingDefs.wall_height(type) + 0.9
		_box(root, "Chimney", Vector3(0.45, 1.1, 0.45), Vector3(size.x * 0.25, top, -size.y * 0.15), _mat(CHIMNEY_COLOR, false))
	return root
