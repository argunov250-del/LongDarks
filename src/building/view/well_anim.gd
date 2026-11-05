class_name WellAnim
extends RefCounted
## Анимация колодца, синхронная с позой жителя POSE_CRANK: ворот вращается той же фазой,
## что и руки жителя (VillagerAnim.crank_phase), ведро на цепи идёт вниз-вверх.


static func apply(well_node: Node3D, active: bool, phase: float) -> void:
	var wl := well_node.find_child("Windlass", true, false) as Node3D
	var chain := well_node.find_child("Chain", true, false) as Node3D
	var bucket := well_node.find_child("Bucket", true, false) as Node3D
	if wl == null or chain == null or bucket == null:
		return
	wl.rotation.x = phase if active else 0.0
	var k := (1.0 - cos(phase)) * 0.5 if active else 1.0  # 0 — внизу, 1 — поднято
	var y := BuildingMeshes.WELL_BASE_Y + lerpf(BuildingMeshes.WELL_BUCKET_LOW, BuildingMeshes.WELL_BUCKET_HIGH, k)
	bucket.position.y = y
	var top := BuildingMeshes.WELL_BASE_Y + BuildingMeshes.WELL_AXIS_Y
	var len := maxf(top - y - 0.14, 0.05)
	chain.scale.y = len
	chain.position.y = top - len * 0.5
