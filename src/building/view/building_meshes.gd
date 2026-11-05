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
