extends "res://tests/test_case.gd"

const Stage := BuildingDefs.Stage


func _names(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		out.append(String(c.name))
	return out


func test_stage_geometry_grows() -> void:
	var a := BuildingMeshes.make(&"izba", Stage.FOUNDATION, 0.5)
	assert_eq(_names(a), ["Foundation"])
	var b := BuildingMeshes.make(&"izba", Stage.WALLS, 0.5)
	assert_eq(_names(b), ["Foundation", "Walls"])
	var c := BuildingMeshes.make(&"izba", Stage.ROOF, 0.5)
	assert_eq(_names(c), ["Foundation", "Walls", "Roof"])
	var d := BuildingMeshes.make(&"izba", Stage.DONE, 1.0)
	assert_eq(_names(d), ["Foundation", "Walls", "Roof"])
	var w_half := (BuildingMeshes.make(&"izba", Stage.WALLS, 0.5).get_node("Walls") as MeshInstance3D)
	var w_full := (d.get_node("Walls") as MeshInstance3D)
	assert_true((w_half.mesh as BoxMesh).size.y < (w_full.mesh as BoxMesh).size.y)
	var g := BuildingMeshes.make(&"watchtower", Stage.FOUNDATION, 0.0, BuildingMeshes.GHOST_OK)
	assert_eq(_names(g).size(), 3, "ghost shows the finished building")
	for n in [a, b, c, d, w_half.get_parent(), g]:
		n.free()


func test_all_types_build_meshes() -> void:
	for t in BuildingDefs.ids():
		var n := BuildingMeshes.make(t, Stage.DONE, 1.0)
		assert_true(n.get_child_count() >= 2, str(t))
		n.free()


func test_buildings_view_syncs() -> void:
	var world := WorldMap.new(12345)
	var eco := EconomySystem.new(world)
	var con := ConstructionSystem.new(world, eco)
	var v := BuildingsView.new()
	v.setup(con)
	var p := world.cell_center(40, 40)
	var id := con.place(&"dugout", p, 0.3)
	if id < 0:
		return
	v.refresh()
	assert_true(v.node_for(id) != null)
	var sig0 := v.signature(con.get_building(id))
	con.get_building(id).stage = Stage.WALLS
	v.refresh()
	assert_true(v.signature(con.get_building(id)) != sig0)
	assert_almost_eq(v.node_for(id).rotation.y, 0.3, 0.001)
	con.buildings.erase(id)
	v.refresh()
	assert_true(v.node_for(id) == null)
	v.free()


func test_ground_hit() -> void:
	var world := WorldMap.new(12345)
	var o := Vector3(100, 80, 100)
	var hit = BuildController.ground_hit(o, Vector3(0.0, -1.0, 0.0), world)
	assert_true(hit != null)
	assert_almost_eq(hit.y, world.height_at(100, 100), 0.05)
	assert_true(BuildController.ground_hit(o, Vector3(0, 1, 0), world) == null)


func _rig() -> Dictionary:
	var sim := Simulation.new(1)
	var world := WorldMap.new(12345)
	var eco := EconomySystem.new(world)
	var con := ConstructionSystem.new(world, eco)
	con.attach(sim)
	sim.register_system(con)
	sim.register_system(eco)
	eco.add_storage(Storage.new(1000))
	var hud: Hud = load("res://scenes/ui/hud.tscn").instantiate()
	hud.sim = sim
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	if not hud.is_node_ready():
		hud._ready()
	var bc := BuildController.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(bc)
	bc.setup(con, null, hud, null, sim)
	return {"sim": sim, "con": con, "eco": eco, "hud": hud, "bc": bc, "world": world}


func _free_rig(r: Dictionary) -> void:
	r["hud"].free()
	r["bc"].free()


func test_hud_build_tab_lists_and_selects() -> void:
	var r := _rig()
	var hud: Hud = r["hud"]
	var bc: BuildController = r["bc"]
	hud.select_tab(0)
	assert_eq(hud._tab_items.get_child_count(), BuildingDefs.ids_in_tab(BuildingDefs.Tab.HOUSING).size())
	(hud._tab_items.get_child(0) as Button).pressed.emit()
	assert_true(bc.is_placing())
	assert_eq(bc.placing_type, &"dugout")
	assert_true(hud.is_actions_visible())
	assert_eq(hud._bar_ids, [&"rotate", &"confirm", &"cancel"])
	var rot0 := bc.ghost_rot
	hud._bar_buttons[0].pressed.emit()
	assert_true(bc.ghost_rot != rot0)
	hud._bar_buttons[2].pressed.emit()
	assert_false(bc.is_placing())
	assert_false(hud.is_actions_visible())
	_free_rig(r)


func test_place_confirm_and_building_panel() -> void:
	var r := _rig()
	var con: ConstructionSystem = r["con"]
	var bc: BuildController = r["bc"]
	var hud: Hud = r["hud"]
	var world: WorldMap = r["world"]
	var site := Vector3(-1, 0, -1)
	for cz in range(10, 100, 3):
		for cx in range(10, 100, 3):
			var p := world.cell_center(cx, cz)
			if site.x < 0 and world.cell_type(cx, cz) == WorldMap.Terrain.GROUND and con.validate_placement(&"dugout", p, 0.0)["ok"]:
				site = p
	bc.start_placement(&"dugout")
	bc.ghost_pos = site  # без камеры центр экрана не определить: задаём вручную
	bc._update_ghost(false)
	assert_true(bc.ghost_valid)
	var id := bc.confirm_placement()
	assert_true(id > 0)
	assert_false(bc.is_placing())
	assert_eq(bc.selected_building, id)
	assert_eq(hud._bar_ids, [&"upgrade", &"cancel_building", &"close"])
	assert_true(hud._bar_buttons[0].disabled, "cannot upgrade while building")
	bc.select_at(site)
	assert_eq(bc.selected_building, id, "tap selects building")
	bc.on_action(&"close")
	assert_eq(bc.selected_building, -1)
	assert_false(hud.is_actions_visible())
	# недопустимое место
	bc.start_placement(&"dugout")
	bc.ghost_pos = site
	bc._update_ghost(false)
	assert_false(bc.ghost_valid)
	assert_eq(bc.ghost_reason, &"overlap")
	assert_true(hud._bar_buttons[1].disabled)
	assert_eq(bc.confirm_placement(), -1)
	_free_rig(r)


func test_ruin_panel_dismantle_and_restore_menu() -> void:
	var r := _rig()
	var con: ConstructionSystem = r["con"]
	var bc: BuildController = r["bc"]
	var hud: Hud = r["hud"]
	var rid: int = con.active_ruin_ids()[0]
	bc.select_at(con.ruins[rid]["pos"])
	assert_eq(bc.selected_ruin, rid)
	assert_eq(hud._bar_ids, [&"restore", &"dismantle", &"close"])
	bc.on_action(&"restore")
	assert_true(&"back" in hud._bar_ids)
	assert_false(&"restore:izba" in hud._bar_ids)
	assert_true(&"restore:dugout" in hud._bar_ids)
	bc.on_action(&"back")
	bc.on_action(&"dismantle")
	assert_true(con.is_dismantling(rid))
	assert_true(hud._bar_buttons[1].disabled)
	_free_rig(r)


func test_felling_brush_mode_and_hud_button() -> void:
	var r := _rig()
	var con: ConstructionSystem = r["con"]
	var bc: BuildController = r["bc"]
	var hud: Hud = r["hud"]
	var world: WorldMap = r["world"]
	var site := Vector3(-1, 0, -1)
	for cz in range(10, 100):
		for cx in range(10, 100):
			if site.x < 0 and world.cell_type(cx, cz) == WorldMap.Terrain.FOREST:
				site = world.cell_center(cx, cz)
	hud.fell_button.pressed.emit()
	assert_true(bc.felling_mode)
	bc.brush_pos = site
	bc._update_brush()
	assert_true(bc.brush_cells.size() > 0)
	assert_true(&"fell_confirm" in hud._bar_ids and &"fell_cancel" in hud._bar_ids)
	var r0 := bc.brush_radius
	bc.on_action(&"fell_plus")
	assert_true(bc.brush_radius > r0)
	bc.on_action(&"fell_shape")
	assert_false(bc.brush_circle)
	var n := bc.confirm_felling()
	assert_true(n > 0)
	assert_eq(con.felling_count(), n)
	assert_false(bc.felling_mode)
	hud.fell_button.pressed.emit()
	bc.on_action(&"fell_cancel")
	assert_false(bc.felling_mode)
	assert_false(hud.is_actions_visible())
	_free_rig(r)
