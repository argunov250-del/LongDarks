extends "res://tests/test_case.gd"
## Шаг 24: панель «Соседи» помещается на экран в портрете и ландшафте.

func test_panel_fits_all_resolutions() -> void:
	var hud: Hud = load("res://scenes/ui/hud.tscn").instantiate()
	hud.sim = Simulation.new(1)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(hud)
	hud.set_process(false)
	var nb := NeighbourSystem.new(3)
	await (Engine.get_main_loop() as SceneTree).process_frame
	hud.bind_neighbours(nb, hud.sim)
	for size in [Vector2i(1280, 720), Vector2i(2400, 1080), Vector2i(1080, 2400)]:
		hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
		hud.size = Vector2(size)
		hud.viewport_override = Vector2(size)
		hud.layout.update_size(Vector2(size))
		hud._apply_mode(LayoutMode.decide(Vector2(size)))
		hud._apply_layout()
		hud.show_neighbours_panel()
		await (Engine.get_main_loop() as SceneTree).process_frame
		await (Engine.get_main_loop() as SceneTree).process_frame
		var r: Rect2 = hud.neighbours_ui.panel.get_global_rect()
		assert_true(r.position.y >= 0.0 and r.end.y <= float(size.y) + 0.5, "panel inside screen %s %s" % [str(size), str(r)])
		assert_true(r.position.x >= 0.0 and r.end.x <= float(size.x) + 0.5, "panel inside width " + str(size))
		assert_true(hud.neighbours_ui.list_box.get_child_count() > 5, "content built")
	hud.free()
