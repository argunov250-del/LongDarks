class_name VillagersView
extends Node3D
## Визуал жителей и собаки: по фигуре на сущность, позиции берутся из VillagerSystem
## каждый кадр. Позы и ноша — VillagerAnim (ходьба, топор, ворот колодца, укладка, огород), тревога собаки — метание и
## подёргивание головы (плейсхолдер, см. Dog.set_anxious).

const SELECT_COLOR := Color(1.0, 0.95, 0.4, 0.8)

var vs: VillagerSystem
var selected_id := -1
var _nodes: Dictionary = {}   # id -> {"node": Node3D, "prof": StringName}
var _dog_node: Node3D
var _ring: MeshInstance3D
var _t := 0.0
var _last_dog_pos := Vector3.ZERO


func setup(system: VillagerSystem) -> void:
	vs = system
	_sync()


func set_selected(id: int) -> void:
	selected_id = id


func node_for(id: int) -> Node3D:
	return _nodes[id]["node"] if _nodes.has(id) else null


func dog_node() -> Node3D:
	return _dog_node


func _process(dt: float) -> void:
	if vs == null:
		return
	_t += dt
	VillagerAnim.clock = _t
	_sync()
	for id in _nodes:
		var v := vs.get_villager(id)
		if v != null:
			_pose_villager(_nodes[id]["node"], v)
	_pose_dog()
	_update_ring()


func _sync() -> void:
	for id in _nodes.keys():
		if not vs.villagers.has(id):
			(_nodes[id]["node"] as Node3D).queue_free()
			_nodes.erase(id)
	for id in vs.villagers:
		var v: Villager = vs.villagers[id]
		if not _nodes.has(id) or _nodes[id]["prof"] != v.profession:
			if _nodes.has(id):
				(_nodes[id]["node"] as Node3D).queue_free()
			var n := VillagerFigures.make_villager(v.profession, v.is_hero)
			n.name = "Villager%d" % id
			add_child(n)
			_nodes[id] = {"node": n, "prof": v.profession}
	if vs.dog != null and _dog_node == null:
		_dog_node = VillagerFigures.make_dog()
		_dog_node.name = "Dog"
		add_child(_dog_node)
		_last_dog_pos = vs.dog.pos


func _pose_villager(n: Node3D, v: Villager) -> void:
	n.position = v.pos
	n.rotation.y = v.facing
	n.scale = Vector3.ONE * FamilyDefs.body_scale(v.stage, v.growth)  # дети ниже ростом
	VillagerAnim.apply(n, VillagerAnim.state_of(v, vs), _t, float(v.id))


func _pose_dog() -> void:
	if _dog_node == null or vs.dog == null:
		return
	var d := vs.dog
	_dog_node.position = d.pos
	_dog_node.rotation.y = d.facing
	var body := _dog_node.get_node("Body") as Node3D
	var head := body.get_node("Head") as Node3D
	var a := d.anxious_level
	body.position = Vector3.ZERO
	head.rotation = Vector3.ZERO
	if a > 0.0:
		# Метание по кругу туда-сюда и поскуливание (кивки головой).
		body.position.x = sin(_t * 3.0) * 0.5 * a
		body.rotation.y = sin(_t * 3.0) * 0.5 * a
		head.rotation.x = absf(sin(_t * 11.0)) * 0.5 * a
	elif d.moving:
		body.position.y = absf(sin(_t * 12.0)) * 0.05
		body.rotation.y = 0.0
	else:
		body.rotation.y = 0.0
	_last_dog_pos = d.pos


func _update_ring() -> void:
	var v := vs.get_villager(selected_id) if selected_id >= 0 else null
	if v == null:
		if _ring != null:
			_ring.visible = false
		return
	if _ring == null:
		_ring = MeshInstance3D.new()
		_ring.name = "SelectRing"
		var cm := CylinderMesh.new()
		cm.top_radius = 0.75
		cm.bottom_radius = 0.75
		cm.height = 0.05
		cm.radial_segments = 16
		_ring.mesh = cm
		var m := StandardMaterial3D.new()
		m.albedo_color = SELECT_COLOR
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring.material_override = m
		add_child(_ring)
	_ring.visible = true
	_ring.position = v.pos + Vector3(0, 0.05, 0)
