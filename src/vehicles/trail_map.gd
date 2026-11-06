class_name TrailMap
extends RefCounted
## Three separate ground layers (design/gdd/vehicles.md):
##  roads  — built by the player with the «Дорога» brush (permanent);
##  foot   — footpaths trodden by villagers (procedural, decays);
##  ruts   — wheel ruts worn by vehicles (procedural, decays).
## Cell index = cz * size + cx.

var roads: Dictionary = {}   # idx -> true
var marks: Dictionary = {}   # idx -> work done (designated road cells)
var foot: Dictionary = {}    # idx -> passes (float)
var ruts: Dictionary = {}    # idx -> passes (float)
var revision := 0            # bumped when pathing-relevant data changes (roads, ruts crossing 0.5)
var view_revision := 0       # bumped on any visible change


func foot_level(i: int) -> float:
	return clampf(float(foot.get(i, 0.0)) / VehicleDefs.FOOT_FULL_PASSES, 0.0, 1.0)


func rut_level(i: int) -> float:
	return clampf(float(ruts.get(i, 0.0)) / VehicleDefs.RUT_FULL_PASSES, 0.0, 1.0)


func is_road(i: int) -> bool:
	return roads.has(i)


## Walking speed multiplier at a cell (footpath).
func walk_mult(i: int) -> float:
	return 1.0 + VehicleDefs.FOOT_SPEED_BONUS * foot_level(i)


## Vehicle speed multiplier at a cell: road beats ruts.
func vehicle_mult(i: int) -> float:
	if roads.has(i):
		return VehicleDefs.ROAD_SPEED_MULT
	return 1.0 + VehicleDefs.RUT_SPEED_BONUS * rut_level(i)


func add_foot(i: int, passes: float = 1.0) -> void:
	if roads.has(i):
		return
	var old := foot_level(i)
	foot[i] = minf(float(foot.get(i, 0.0)) + passes, VehicleDefs.FOOT_FULL_PASSES * 1.5)
	if int(old * 4.0) != int(foot_level(i) * 4.0):
		view_revision += 1


func add_rut(i: int, passes: float = 1.0) -> void:
	if roads.has(i):
		return
	var old := rut_level(i)
	ruts[i] = minf(float(ruts.get(i, 0.0)) + passes, VehicleDefs.RUT_FULL_PASSES * 1.5)
	var nw := rut_level(i)
	if int(old * 4.0) != int(nw * 4.0):
		view_revision += 1
	if (old >= 0.5) != (nw >= 0.5):
		revision += 1


## Unused trails slowly overgrow.
func decay(days: float) -> void:
	for layer in [foot, ruts]:
		var rate := VehicleDefs.FOOT_DECAY_PER_DAY if layer == foot else VehicleDefs.RUT_DECAY_PER_DAY
		var dead: Array = []
		for i in layer:
			var before := clampf(float(layer[i]) / (VehicleDefs.FOOT_FULL_PASSES if layer == foot else VehicleDefs.RUT_FULL_PASSES), 0.0, 1.0)
			layer[i] = float(layer[i]) - rate * days
			var after := clampf(float(layer[i]) / (VehicleDefs.FOOT_FULL_PASSES if layer == foot else VehicleDefs.RUT_FULL_PASSES), 0.0, 1.0)
			if int(before * 4.0) != int(after * 4.0):
				view_revision += 1
				if layer == ruts and (before >= 0.5) != (after >= 0.5):
					revision += 1
			if layer[i] <= 0.0:
				dead.append(i)
		for i in dead:
			layer.erase(i)


func build_road(i: int) -> void:
	roads[i] = true
	marks.erase(i)
	foot.erase(i)
	ruts.erase(i)
	revision += 1
	view_revision += 1


func save_state() -> Dictionary:
	var f := {}
	for i in foot:
		f[str(i)] = snappedf(float(foot[i]), 0.01)
	var r := {}
	for i in ruts:
		r[str(i)] = snappedf(float(ruts[i]), 0.01)
	var m := {}
	for i in marks:
		m[str(i)] = marks[i]
	return {"roads": roads.keys(), "marks": m, "foot": f, "ruts": r}


func load_state(d: Dictionary) -> void:
	roads.clear()
	marks.clear()
	foot.clear()
	ruts.clear()
	for i in d.get("roads", []):
		roads[SaveManager.to_int(i, -1)] = true
	for k in (d.get("marks", {}) as Dictionary):
		marks[SaveManager.to_int(k, -1)] = float(d["marks"][k])
	for k in (d.get("foot", {}) as Dictionary):
		foot[SaveManager.to_int(k, -1)] = float(d["foot"][k])
	for k in (d.get("ruts", {}) as Dictionary):
		ruts[SaveManager.to_int(k, -1)] = float(d["ruts"][k])
	revision += 1
	view_revision += 1
