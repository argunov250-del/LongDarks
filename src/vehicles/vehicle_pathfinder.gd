class_name VehiclePathfinder
extends RefCounted
## Vehicle grid A*: avoids water, steep slopes, trees (forest not yet felled), flooded cells
## (VillagerSystem pathfinder.blocked), buildings. Roads and deep ruts are cheaper.
## No path smoothing: vehicles follow roads.

var world: WorldMap
var construction: ConstructionSystem
var villagers: VillagerSystem
var trails: TrailMap
var deposits: Deposits
var _grid: AStarGrid2D
var _sig := ""


func _init(world_in: WorldMap, construction_in: ConstructionSystem, villagers_in: VillagerSystem, trails_in: TrailMap) -> void:
	world = world_in
	construction = construction_in
	villagers = villagers_in
	trails = trails_in


func slope_of(cx: int, cz: int) -> float:
	var lo := INF
	var hi := -INF
	for dz in 2:
		for dx in 2:
			var h := world.node_height(cx + dx, cz + dz)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return (hi - lo) / world.cell_size


func _occupied() -> Dictionary:
	var out := {}
	if construction == null:
		return out
	for b: Building in construction.buildings.values():
		for c in construction.footprint_cells(Vector2(b.position.x, b.position.z), b.size(), b.rot):
			out[c.y * world.size + c.x] = true
	return out


func _ensure() -> void:
	var blocked: Dictionary = villagers.pathfinder.blocked if villagers != null else {}
	var sig := "%d:%d:%d:%d:%d" % [world.seed_value, construction.buildings.size() if construction != null else 0, blocked.size(), trails.revision, deposits.revision if deposits != null else 0]
	if _grid != null and sig == _sig:
		return
	_sig = sig
	var occ := _occupied()
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, world.size, world.size)
	_grid.cell_size = Vector2.ONE
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()
	for cz in world.size:
		for cx in world.size:
			var i := cz * world.size + cx
			if not _cell_ok(cx, cz) or occ.has(i) or blocked.has(i):
				_grid.set_point_solid(Vector2i(cx, cz), true)
			elif trails.is_road(i):
				_grid.set_point_weight_scale(Vector2i(cx, cz), VehicleDefs.ROAD_PATH_WEIGHT)
			elif trails.rut_level(i) >= 0.5:
				_grid.set_point_weight_scale(Vector2i(cx, cz), 0.85)


func _cell_ok(cx: int, cz: int) -> bool:
	var t := world.cell_type(cx, cz)
	if WorldMap.is_water_type(t) or t == WorldMap.Terrain.RUINS:
		return false
	if t == WorldMap.Terrain.FOREST and construction != null and construction.has_trees(Vector2i(cx, cz)):
		return false
	return slope_of(cx, cz) <= VehicleDefs.MAX_SLOPE


func is_passable(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= world.size or c.y >= world.size:
		return false
	_ensure()
	return not _grid.is_point_solid(c)


func nearest_passable(p: Vector3) -> Vector3:
	var c := world.cell_of(p.x, p.z)
	if is_passable(c):
		return p
	for r in range(1, world.size):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) == r and is_passable(c + Vector2i(dx, dz)):
					return world.cell_center(c.x + dx, c.y + dz)
	return p


## Empty array — unreachable.
func find_path(from: Vector3, to: Vector3) -> Array[Vector3]:
	_ensure()
	var out: Array[Vector3] = []
	var a := world.cell_of(from.x, from.z)
	var b := world.cell_of(to.x, to.z)
	if not is_passable(a) or not is_passable(b):
		return out
	if a == b:
		out.append(Vector3(to.x, world.height_at(to.x, to.z), to.z))
		return out
	var ids := _grid.get_id_path(a, b)
	for i in range(1, ids.size()):
		out.append(world.cell_center(ids[i].x, ids[i].y))
	if out.is_empty():
		return out
	out[out.size() - 1] = Vector3(to.x, world.height_at(to.x, to.z), to.z)
	return out
