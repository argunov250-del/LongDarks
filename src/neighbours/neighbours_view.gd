class_name NeighboursView
extends Node3D
## Мир шага 24: лагерь соседей у края карты (палатки, дом, костёр) и идущие отряды
## (караван — гружёные фигуры/машина, налётчики — тёмные фигуры). design/gdd/neighbours.md.

var system: NeighbourSystem
var _camps: Dictionary = {}
var _party_nodes: Dictionary = {}


func setup(sys: NeighbourSystem) -> void:
	system = sys


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _mesh(mesh: Mesh, c: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c)
	mi.position = pos
	return mi


func _build_camp(n: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = system.camp_pos(n)
	var hut := BoxMesh.new()
	hut.size = Vector3(3.0, 2.0, 3.0)
	root.add_child(_mesh(hut, Color(0.45, 0.32, 0.2), Vector3(0, 1.0, 0)))
	for i in 3:
		var tent := PrismMesh.new()
		tent.size = Vector3(2.4, 2.0, 2.4)
		root.add_child(_mesh(tent, Color(0.7, 0.6, 0.35), Vector3(-4.0 + 4.0 * i, 1.0, 4.0 + float(i % 2) * 1.5)))
	var fire := CylinderMesh.new()
	fire.top_radius = 0.4
	fire.bottom_radius = 0.5
	fire.height = 0.6
	root.add_child(_mesh(fire, Color(0.95, 0.5, 0.1), Vector3(0, 0.3, 3.0)))
	return root


func _figure(kind: StringName, driving: bool) -> Node3D:
	var root := Node3D.new()
	if driving:
		var b := BoxMesh.new()
		b.size = Vector3(1.6, 1.2, 3.0)
		root.add_child(_mesh(b, Color(0.3, 0.45, 0.3), Vector3(0, 0.8, 0)))
		return root
	var c := Color(0.15, 0.1, 0.1) if kind == &"raid" else Color(0.85, 0.7, 0.3)
	var cnt := 3 if kind == &"raid" else 2
	for i in cnt:
		var cap := CapsuleMesh.new()
		cap.radius = 0.35
		cap.height = 1.7
		root.add_child(_mesh(cap, c, Vector3(float(i) * 1.0 - 0.5, 0.9, float(i % 2) * 0.6)))
	return root


func _process(_dt: float) -> void:
	update()


func update() -> void:
	if system == null:
		return
	for n in system.neighbours:
		if not _camps.has(n["id"]):
			_camps[n["id"]] = _build_camp(n)
			add_child(_camps[n["id"]])
		(_camps[n["id"]] as Node3D).visible = int(n["pop"]) > 0
	var alive := {}
	for p in system.parties:
		alive[p["id"]] = true
		if not _party_nodes.has(p["id"]):
			var node := _figure(p["kind"], bool(p["driving"]))
			_party_nodes[p["id"]] = node
			add_child(node)
		var pos := system.party_pos(p)
		if system.world != null:
			pos.y = system.world.height_at(pos.x, pos.z)
		(_party_nodes[p["id"]] as Node3D).position = pos
	for id in _party_nodes.keys():
		if not alive.has(id):
			(_party_nodes[id] as Node3D).queue_free()
			_party_nodes.erase(id)
