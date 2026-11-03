extends "res://tests/test_case.gd"


func test_layout_decision() -> void:
	assert_eq(LayoutMode.decide(Vector2(1080, 2400)), LayoutMode.Mode.PORTRAIT)
	assert_eq(LayoutMode.decide(Vector2(2400, 1080)), LayoutMode.Mode.LANDSCAPE)
	assert_eq(LayoutMode.decide(Vector2(1920, 1080)), LayoutMode.Mode.LANDSCAPE)
	assert_eq(LayoutMode.decide(Vector2(1000, 1000)), LayoutMode.Mode.PORTRAIT)
	assert_eq(LayoutMode.decide(Vector2(1100, 1000)), LayoutMode.Mode.PORTRAIT)
	assert_eq(LayoutMode.decide(Vector2(1200, 1000)), LayoutMode.Mode.LANDSCAPE)
	assert_eq(LayoutMode.decide(Vector2.ZERO), LayoutMode.Mode.PORTRAIT)


func test_layout_signal() -> void:
	var lm := LayoutMode.new()
	var seen: Array = []
	lm.mode_changed.connect(func(m): seen.append(m))
	assert_false(lm.update_size(Vector2(1080, 2400)))
	assert_true(lm.update_size(Vector2(2400, 1080)))
	assert_false(lm.update_size(Vector2(2000, 1000)))
	assert_true(lm.update_size(Vector2(1080, 2400)))
	assert_eq(seen, [LayoutMode.Mode.LANDSCAPE, LayoutMode.Mode.PORTRAIT])
	lm.free()


func test_time_format() -> void:
	assert_eq(Hud.format_time(0.0), "00:00")
	assert_eq(Hud.format_time(0.5), "12:00")
	assert_eq(Hud.format_time(0.75), "18:00")
	assert_eq(Hud.format_time(0.999999), "23:59")
	assert_eq(Hud.format_date(3), "День 3")


func test_safe_margins() -> void:
	var m := Hud.safe_margins(Rect2i(0, 100, 1080, 2200), Vector2i(1080, 2400), Vector2(1080, 2400))
	assert_almost_eq(m["top"], 100.0)
	assert_almost_eq(m["bottom"], 100.0)
	assert_almost_eq(m["left"], 0.0)
	var z := Hud.safe_margins(Rect2i(), Vector2i(1080, 2400), Vector2(1080, 2400))
	assert_almost_eq(z["top"], 0.0)


func _make_hud() -> Hud:
	var hud: Hud = load("res://scenes/ui/hud.tscn").instantiate()
	hud.sim = Simulation.new(1)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(hud)
	if not hud.is_node_ready():  # в -s раннере корень ещё не в дереве
		hud._ready()
	return hud


func test_speed_buttons_set_clock_speed() -> void:
	var hud := _make_hud()
	hud.speed_buttons[3].pressed.emit()
	assert_eq(hud.sim.clock.get_speed(), 3)
	hud.speed_buttons[0].pressed.emit()
	assert_eq(hud.sim.clock.get_speed(), 0)
	hud.speed_buttons[1].pressed.emit()
	assert_eq(hud.sim.clock.get_speed(), 1)
	hud.free()


func test_labels_follow_clock_and_mouse_filter() -> void:
	var hud := _make_hud()
	hud.sim.clock.set_day_length(100.0)
	hud.sim.clock.set_total_seconds(150.0)
	hud._refresh_clock(true)
	assert_eq(hud.date_label.text, "День 2")
	assert_eq(hud.time_label.text, "12:00")
	assert_eq(hud.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	hud.free()


func test_modes_reparent_same_actions() -> void:
	var hud := _make_hud()
	hud._apply_mode(LayoutMode.Mode.LANDSCAPE)
	assert_true(hud.menu_button.visible)
	assert_false(hud.fab.visible)
	hud._apply_mode(LayoutMode.Mode.PORTRAIT)
	assert_true(hud.fab.visible)
	hud.fab.pressed.emit()
	assert_true(hud._sheet.visible)
	assert_eq(hud.tab_buttons.size(), 4)
	assert_true(hud.tab_buttons[0].custom_minimum_size.y >= 48.0)
	hud.free()
