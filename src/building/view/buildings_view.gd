class_name BuildingsView
extends Node3D
## Узлы 3D для зданий ConstructionSystem. Перестраивает только изменившиеся
## (по подписи: тип, стадия, дискретный прогресс); опрос ~5 раз в секунду.

const POLL_INTERVAL := 0.2
const PROGRESS_STEPS := 10
const WOOD_STEPS := 10  # ступеней высоты поленницы

var con: ConstructionSystem
var villagers: VillagerSystem    # опционально: колодцы крутят ворот вместе с жителем
var household: HouseholdSystem  # опционально: двор жилья показывает запасы и огород
var _nodes: Dictionary = {}  # id -> {"node": Node3D, "sig": String}
var _acc := 0.0


func setup(construction: ConstructionSystem) -> void:
	con = construction
	refresh()


func _process(dt: float) -> void:
	_animate_wells()
	_acc += dt
	if _acc >= POLL_INTERVAL:
		_acc = 0.0
		refresh()


## Состояние двора жилья для узла Yard (пустой словарь — только забор).
func yard_state(b: Building) -> Dictionary:
	var h: Household = household.homes.get(b.id) if household != null else null  # запасы живут и при улучшении
	if h == null:
		return {"done": true} if b.is_done() else {}
	var wood := float(h.woodpile) / float(maxi(1, BuildingDefs.firewood_capacity(b.type)))
	return {"wood": snappedf(wood, 1.0 / WOOD_STEPS), "garden": h.garden_state, "garden_frac": snappedf(h.garden_fraction(), 0.25),
		"crop": h.garden_crop, "barn": h.barn, "done": b.is_done()}


func signature(b: Building) -> String:
	var sig := "%s|%d|%d" % [b.type, b.stage, int(b.stage_fraction() * PROGRESS_STEPS)]
	if BuildingDefs.has_yard(b.type):
		sig += "|" + str(yard_state(b))
	if b.damaged or b.burning:
		sig += "|dmg%d_fire%d" % [int(b.damaged), int(b.burning)]
	return sig


## Ворот и ведро колодца: работают, пока житель стоит у него в позе набора воды.
func _animate_wells() -> void:
	if con == null:
		return
	for id in _nodes:
		var b: Building = con.buildings.get(id)
		if b == null or not BuildingDefs.is_well(b.type):
			continue
		var seed_v := -1.0
		if villagers != null:
			for v: Villager in villagers.villagers.values():
				if v.at_site and not v.moving and (v.task.get("kind", &"") == &"water" or v.task.get("kind", &"") == &"extinguish") and v.task.get("phase", &"") == &"fetch" and int(v.task.get("src", 0)) == id:
					seed_v = float(v.id)
					break
		WellAnim.apply(_nodes[id]["node"], seed_v >= 0.0, VillagerAnim.crank_phase(VillagerAnim.clock, maxf(seed_v, 0.0)))


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
			if BuildingDefs.has_yard(b.type):
				n.add_child(BuildingMeshes.make_yard(b.type, yard_state(b)))
			if b.is_done() and (b.damaged or b.burning):
				var fp := b.size()
				n.add_child(WeatherFx.make_soot(fp, BuildingDefs.wall_height(b.type) + 0.6))
				if b.burning:
					var fx := WeatherFx.make_fire(maxf(fp.x, fp.y) * 0.3, BuildingDefs.wall_height(b.type) + 1.2, 28)
					fx.position.y = BuildingDefs.wall_height(b.type) * 0.6
					n.add_child(fx)
			add_child(n)
			entry = {"node": n, "sig": sig}
			_nodes[id] = entry
		var node: Node3D = entry["node"]
		node.position = b.position
		node.rotation.y = b.rot
