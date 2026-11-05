class_name BuildingsView
extends Node3D
## Узлы 3D для зданий ConstructionSystem. Перестраивает только изменившиеся
## (по подписи: тип, стадия, дискретный прогресс); опрос ~5 раз в секунду.

const POLL_INTERVAL := 0.2
const PROGRESS_STEPS := 10

var con: ConstructionSystem
var _nodes: Dictionary = {}  # id -> {"node": Node3D, "sig": String}
var _acc := 0.0


func setup(construction: ConstructionSystem) -> void:
	con = construction
	refresh()


func _process(dt: float) -> void:
	_acc += dt
	if _acc >= POLL_INTERVAL:
		_acc = 0.0
		refresh()


func signature(b: Building) -> String:
	return "%s|%d|%d" % [b.type, b.stage, int(b.stage_fraction() * PROGRESS_STEPS)]


func node_for(id: int) -> Node3D:
	return _nodes[id]["node"] if _nodes.has(id) else null


func refresh() -> void:
	if con == null:
		return
	for id in _nodes.keys():
		if not con.buildings.has(id):
			(_nodes[id]["node"] as Node3D).queue_free()
			_nodes.erase(id)
	for id in con.buildings:
		var b: Building = con.buildings[id]
		var sig := signature(b)
		var entry: Dictionary = _nodes.get(id, {})
		if entry.is_empty() or entry["sig"] != sig:
			if not entry.is_empty():
				(entry["node"] as Node3D).queue_free()
			var n := BuildingMeshes.make(b.type, b.stage, b.stage_fraction())
			n.name = "Building%d" % id
			add_child(n)
			entry = {"node": n, "sig": sig}
			_nodes[id] = entry
		var node: Node3D = entry["node"]
		node.position = b.position
		node.rotation.y = b.rot
