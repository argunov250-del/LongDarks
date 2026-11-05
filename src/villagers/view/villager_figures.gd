class_name VillagerFigures
extends RefCounted
## Low-poly заглушки: человечек (цвет по профессии) и собака. Начало координат — ступни.

const SKIN := Color(0.86, 0.70, 0.58)
const PANTS := Color(0.22, 0.22, 0.26)
const HERO_MARK := Color(1.0, 0.85, 0.15)
const DOG_COLOR := Color(0.55, 0.38, 0.22)
const DOG_DARK := Color(0.30, 0.20, 0.12)

static var _mats: Dictionary = {}


static func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 1.0
		_mats[key] = m
	return _mats[key]


static func _box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mat(c)
	parent.add_child(mi)
	return mi


## Узлы: Body (покачивается), Head, LegL/LegR; у героя ещё Mark.
static func make_villager(profession: StringName, hero: bool) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var col: Color = VillagerDefs.PROFESSION_COLORS.get(profession, Color(0.6, 0.6, 0.6))
	_box(body, "Torso", Vector3(0.50, 0.70, 0.30), Vector3(0, 1.10, 0), col)
	var head := _box(body, "Head", Vector3(0.28, 0.28, 0.28), Vector3(0, 1.62, 0), SKIN)
	head.name = "Head"
	_box(root, "LegL", Vector3(0.18, 0.75, 0.20), Vector3(-0.13, 0.375, 0), PANTS)
	_box(root, "LegR", Vector3(0.18, 0.75, 0.20), Vector3(0.13, 0.375, 0), PANTS)
	if hero:
		var mark := _box(root, "Mark", Vector3(0.22, 0.22, 0.22), Vector3(0, 2.25, 0), HERO_MARK)
		mark.rotation = Vector3(0.6, 0.0, 0.6)
	return root


## Узлы: Body (с головой и хвостом), Legs.
static func make_dog() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	_box(body, "Torso", Vector3(0.32, 0.30, 0.80), Vector3(0, 0.55, 0), DOG_COLOR)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.78, 0.45)
	body.add_child(head)
	_box(head, "Skull", Vector3(0.24, 0.24, 0.28), Vector3.ZERO, DOG_COLOR)
	_box(head, "Snout", Vector3(0.14, 0.12, 0.16), Vector3(0, -0.04, 0.2), DOG_DARK)
	var tail := _box(body, "Tail", Vector3(0.07, 0.07, 0.38), Vector3(0, 0.72, -0.55), DOG_DARK)
	tail.rotation.x = 0.7
	for i in 4:
		var x := -0.1 if i % 2 == 0 else 0.1
		var z := 0.28 if i < 2 else -0.28
		_box(root, "Leg%d" % i, Vector3(0.09, 0.40, 0.09), Vector3(x, 0.2, z), DOG_DARK)
	return root
