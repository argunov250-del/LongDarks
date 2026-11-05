extends "res://tests/test_case.gd"

const Env = preload("res://tests/villagers/villager_env.gd")


func _find(n: Node, name: String) -> Node:
	return n.find_child(name, true, false)


func test_woodpile_height_follows_amount() -> void:
	var low := BuildingMeshes.make_yard(&"dugout", {"wood": 0.2, "garden": &"empty", "done": true})
	var high := BuildingMeshes.make_yard(&"dugout", {"wood": 1.0, "garden": &"empty", "done": true})
	var empty := BuildingMeshes.make_yard(&"dugout", {"wood": 0.0, "garden": &"empty", "done": true})
	assert_true(_find(empty, "Stack") == null, "empty woodpile has no stack")
	var hl := ((_find(low, "Stack") as MeshInstance3D).mesh as BoxMesh).size.y
	var hh := ((_find(high, "Stack") as MeshInstance3D).mesh as BoxMesh).size.y
	assert_true(hh > hl and hl > 0.0, "stack height = amount")
	for n in [low, high, empty]:
		assert_true(_find(n, "Fence") != null and _find(n, "Chimney") != null and _find(n, "Garden") != null)
		assert_true(_find(n, "Barn") == null)
		n.free()
	var barn := BuildingMeshes.make_yard(&"dugout", {"wood": 0.5, "garden": &"ripe", "garden_frac": 1.0, "crop": &"vegetables", "barn": true, "done": true})
	assert_true(_find(barn, "Barn") != null and _find(barn, "Cow") != null and _find(barn, "Plant") != null)
	barn.free()
	var ghost := BuildingMeshes.make_yard(&"izba", {}, BuildingMeshes.GHOST_OK)
	assert_true(_find(ghost, "Fence") != null and _find(ghost, "Woodpile") == null)
	ghost.free()


func test_buildings_view_shows_yard_and_updates() -> void:
	var e := Env.new(5000, {})
	var id := e.add_done(&"dugout", 10.0, 0.0)
	var view := BuildingsView.new()
	view.household = e.vs.household
	view.setup(e.con)
	assert_true(view.node_for(id).has_node("Yard"), "yard node on the house")
	var sig := view.signature(e.con.get_building(id))
	e.vs.household.home(id).woodpile = 6
	assert_true(view.signature(e.con.get_building(id)) != sig, "woodpile change redraws")
	view.refresh()
	var stack := _find(view.node_for(id), "Stack") as MeshInstance3D
	assert_true(stack != null and stack.mesh.size.y > 0.1)
	view.free()


func test_animation_states_and_figures() -> void:
	var e := Env.new(5000, {})
	var fig := VillagerFigures.make_villager(&"farmer", false)
	for p in ["Body/ArmL", "Body/ArmR", "Body/ArmR/Axe", "Body/ArmR/Hoe", "Body/ArmL/BucketL", "Body/ArmR/BucketR", "Body/Armful/Logs", "Body/Armful/Firewood", "Body/Armful/Basket"]:
		assert_true(fig.has_node(p), p)
	var v := e.hero()
	v.moving = true
	v.task = {"kind": &"water", "phase": &"deliver", "carry": 6, "res": &"water", "target": 1, "dest": &"house", "key": "k", "work": 0.0}
	var st := VillagerAnim.state_of(v, e.vs)
	assert_eq(st, {"pose": VillagerAnim.POSE_WALK, "load": VillagerAnim.LOAD_BUCKETS})
	VillagerAnim.apply(fig, st, 0.3, 1.0)
	assert_true((fig.get_node("Body/ArmL/BucketL") as Node3D).visible and (fig.get_node("Body/ArmR/BucketR") as Node3D).visible)
	assert_false((fig.get_node("Body/Armful") as Node3D).visible)
	v.moving = false
	v.at_site = true
	v.task["phase"] = &"fetch"
	v.task["carry"] = 0
	assert_eq(VillagerAnim.state_of(v, e.vs)["pose"], VillagerAnim.POSE_CRANK)
	v.task = {"kind": &"chop", "phase": &"chop", "carry": 2, "res": &"logs", "target": 1, "key": "k", "work": 0.0, "dest": &""}
	st = VillagerAnim.state_of(v, e.vs)
	assert_eq(st["pose"], VillagerAnim.POSE_CHOP)
	VillagerAnim.apply(fig, st, 0.3, 1.0)
	assert_true((fig.get_node("Body/ArmR/Axe") as Node3D).visible)
	var a0 := (fig.get_node("Body/ArmR") as Node3D).rotation.x
	VillagerAnim.apply(fig, st, 0.6, 1.0)
	assert_true(absf((fig.get_node("Body/ArmR") as Node3D).rotation.x - a0) > 0.05, "axe swings")
	v.task = {"kind": &"carry", "phase": &"deliver", "carry": 4, "res": &"firewood", "target": 1, "key": "k", "work": 0.0, "dest": &"woodpile"}
	st = VillagerAnim.state_of(v, e.vs)
	assert_eq(st, {"pose": VillagerAnim.POSE_STACK, "load": VillagerAnim.LOAD_FIREWOOD})
	VillagerAnim.apply(fig, st, 0.3, 1.0)
	assert_true((fig.get_node("Body/Armful/Firewood") as Node3D).visible and not (fig.get_node("Body/Armful/Logs") as Node3D).visible)
	v.task = {"kind": &"garden", "phase": &"deliver", "carry": 8, "res": &"potato", "target": 1, "key": "k", "work": 0.0, "dest": &"house"}
	assert_eq(VillagerAnim.state_of(v, e.vs)["load"], VillagerAnim.LOAD_BASKET)
	v.at_site = false
	v.task = {}
	assert_eq(VillagerAnim.state_of(v, e.vs)["pose"], VillagerAnim.POSE_IDLE)
	fig.free()


func test_garden_poses() -> void:
	var e := Env.new(5000, {})
	var house := e.add_done(&"dugout", 10.0, 0.0)
	var h := e.vs.household.home(house)
	var v := e.hero()
	v.at_site = true
	v.task = {"kind": &"garden", "phase": &"work", "carry": 0, "res": &"", "target": house, "key": "k", "work": 0.0, "dest": &""}
	assert_eq(VillagerAnim.state_of(v, e.vs)["pose"], VillagerAnim.POSE_DIG)
	v.task["work"] = HouseholdDefs.PLANT_WORK * 0.8
	assert_eq(VillagerAnim.state_of(v, e.vs)["pose"], VillagerAnim.POSE_PLANT)
	h.garden_state = Household.GARDEN_RIPE
	assert_eq(VillagerAnim.state_of(v, e.vs)["pose"], VillagerAnim.POSE_HARVEST)
