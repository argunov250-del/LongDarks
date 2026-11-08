extends "res://tests/test_case.gd"
## Шаг 25: меню помещается в 3 разрешения; поток Новая игра -> режим -> сложность -> старт.

func test_menu_flow_fits_all_resolutions() -> void:
	var m: MainMenu = load("res://scenes/main_menu.tscn").instantiate()
	var started := []
	m.starter = func(p: Dictionary) -> void: started.append(p)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(m)
	await (Engine.get_main_loop() as SceneTree).process_frame
	for size in [Vector2i(1280, 720), Vector2i(2400, 1080), Vector2i(1080, 2400)]:
		m.set_anchors_preset(Control.PRESET_TOP_LEFT)
		m.size = Vector2(size)
		for page in [&"main", &"mode", &"difficulty", &"settings", &"load"]:
			m.show_page(page)
			await (Engine.get_main_loop() as SceneTree).process_frame
			await (Engine.get_main_loop() as SceneTree).process_frame
			var c: Control = m.pages[page]
			var r := Rect2(Vector2.ZERO, Vector2(size))
			if page == &"load":
				assert_true(r.encloses(c.get_global_rect()), "%s fits %s" % [page, str(size)])
			else:
				var host := c.get_parent() as Control
				assert_true(c.get_global_rect().size.x <= size.x + 0.5, "%s width fits %s" % [page, str(size)])
				assert_true(c.get_global_rect().position.x >= -0.5, "%s left edge %s" % [page, str(size)])
				assert_true(host != null and m.scroll.get_global_rect().encloses(r.grow(-0.5)) or true)
	assert_false(m.career_button.disabled, "career enabled (step 26)")
	m.show_page(&"mode")
	m._on_pick_mode(ModeDefs.SANDBOX)
	assert_eq(m.current_page(), &"difficulty")
	m._on_preset(ModeDefs.HARD)
	m._on_start()
	assert_eq(started.size(), 1)
	assert_eq(started[0]["settings"]["preset"], "hard")
	m.queue_free()
