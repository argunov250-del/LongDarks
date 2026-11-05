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


const WOOD_DARK := Color(0.40, 0.27, 0.16)
const WOOD_LIGHT := Color(0.75, 0.58, 0.36)
const METAL := Color(0.60, 0.62, 0.66)
const BUCKET_COLOR := Color(0.45, 0.45, 0.50)
const BASKET_COLOR := Color(0.62, 0.45, 0.25)
const VEG_COLOR := Color(0.45, 0.70, 0.30)


## Узлы: Body (покачивается; в нём Torso, Head, ArmL/ArmR, Armful), LegL/LegR; у героя ещё Mark.
## Реквизит скрыт, пока им не пользуются (см. VillagerAnim): в руках — Axe/Hoe (ArmR),
## BucketL/BucketR (вёдра), в охапке Armful/{Logs, Firewood, Basket}.
static func make_villager(profession: StringName, hero: bool) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var col: Color = VillagerDefs.PROFESSION_COLORS.get(profession, Color(0.6, 0.6, 0.6))
	_box(body, "Torso", Vector3(0.50, 0.70, 0.30), Vector3(0, 1.10, 0), col)
	var head := _box(body, "Head", Vector3(0.28, 0.28, 0.28), Vector3(0, 1.62, 0), SKIN)
	head.name = "Head"
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "ArmL" if side < 0.0 else "ArmR"
		arm.position = Vector3(side * 0.34, 1.40, 0.0)
		body.add_child(arm)
		_box(arm, "Sleeve", Vector3(0.12, 0.60, 0.14), Vector3(0, -0.30, 0), col)
		_box(arm, "Hand", Vector3(0.10, 0.10, 0.10), Vector3(0, -0.62, 0), SKIN)
		var bucket := _box(arm, "BucketL" if side < 0.0 else "BucketR", Vector3(0.24, 0.26, 0.24), Vector3(0, -0.85, 0), BUCKET_COLOR)
		bucket.visible = false
	var armr := body.get_node("ArmR") as Node3D
	var axe := Node3D.new()
	axe.name = "Axe"
	armr.add_child(axe)
	_box(axe, "Handle", Vector3(0.06, 0.70, 0.06), Vector3(0, -0.85, 0.0), WOOD_DARK)
	_box(axe, "Blade", Vector3(0.05, 0.20, 0.26), Vector3(0, -1.15, 0.12), METAL)
	axe.visible = false
	var hoe := Node3D.new()
	hoe.name = "Hoe"
	armr.add_child(hoe)
	_box(hoe, "Handle", Vector3(0.05, 0.95, 0.05), Vector3(0, -0.95, 0.0), WOOD_DARK)
	_box(hoe, "Blade", Vector3(0.22, 0.05, 0.18), Vector3(0, -1.42, 0.08), METAL)
	hoe.visible = false
	var armful := Node3D.new()
	armful.name = "Armful"
	armful.position = Vector3(0, 1.05, 0.32)
	body.add_child(armful)
	var logs := Node3D.new()
	logs.name = "Logs"
	armful.add_child(logs)
	for i in 3:
		_box(logs, "Log", Vector3(0.50, 0.14, 0.14), Vector3(0, 0.08 * (i % 2) + 0.0, -0.08 + 0.12 * i), WOOD_DARK)
	var fw := Node3D.new()
	fw.name = "Firewood"
	armful.add_child(fw)
	for i in 5:
		_box(fw, "Piece", Vector3(0.40, 0.09, 0.09), Vector3(0, 0.05 * (i % 2), -0.10 + 0.07 * i), WOOD_LIGHT)
	var basket := Node3D.new()
	basket.name = "Basket"
	armful.add_child(basket)
	_box(basket, "Wicker", Vector3(0.40, 0.22, 0.30), Vector3(0, -0.02, 0), BASKET_COLOR)
	_box(basket, "Veg", Vector3(0.34, 0.10, 0.24), Vector3(0, 0.12, 0), VEG_COLOR)
	armful.visible = false
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
