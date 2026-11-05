extends "res://tests/test_case.gd"


func _rig() -> Dictionary:
	var sim := Simulation.new(1)
	var world := WorldMap.new(12345)
	var eco := EconomySystem.new(world)
	var con := ConstructionSystem.new(world, eco)
	var prod := ProductionSystem.new(con, eco)
	con.attach(sim)
	prod.attach(sim)
	sim.register_system(con)
	sim.register_system(eco)
	sim.register_system(prod)
	eco.add_storage(Storage.new(1000))
	var hud: Hud = load("res://scenes/ui/hud.tscn").instantiate()
	hud.sim = sim
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	if not hud.is_node_ready():
		hud._ready()
	var bc := BuildController.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(bc)
	bc.setup(con, null, hud, null, sim)
	bc.production = prod
	var b := Building.new()
	b.id = 1
	b.type = &"sawmill"
	b.stage = BuildingDefs.Stage.DONE
	con.buildings[1] = b
	return {"sim": sim, "eco": eco, "prod": prod, "hud": hud, "bc": bc}


func test_panel_shows_production_and_pause_both_layouts() -> void:
	var r := _rig()
	var hud: Hud = r["hud"]
	var bc: BuildController = r["bc"]
	var prod: ProductionSystem = r["prod"]
	for mode in [LayoutMode.Mode.LANDSCAPE, LayoutMode.Mode.PORTRAIT]:
		hud._apply_mode(mode)
		prod.set_paused(1, false)
		bc.select_building(1)
		assert_true(hud.is_actions_visible())
		assert_true(hud._bar_ids.has(&"pause"))
		assert_true(hud._bar_label.text.contains("Доски"), "recipe shown")
		assert_true(hud._bar_label.text.contains("ждёт сырьё") or hud._bar_label.text.contains("Цикл"))
		var idx: int = hud._bar_ids.find(&"pause")
		assert_eq(hud._bar_buttons[idx].text, "Пауза")
		hud._bar_buttons[idx].pressed.emit()
		assert_true(prod.is_paused(1))
		assert_eq(hud._bar_buttons[idx].text, "Продолжить")
		assert_true(hud._bar_label.text.contains("пауза"))
		bc.clear_selection()
	hud.free()
	bc.free()
