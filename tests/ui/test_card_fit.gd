extends "res://tests/test_case.gd"
## Шаг 23: карточка жителя (с прокруткой и вкладками) помещается на экран в обоих режимах,
## не заходит на нижнюю док-панель (ландшафт) и плавающую кнопку (портрет).

func _long_text() -> String:
	var lines: Array[String] = []
	for i in 40:
		lines.append("Строка карточки номер %d с довольно длинным описанием жителя" % i)
	return "\n".join(lines)


func test_card_fits_all_resolutions() -> void:
	var hud: Hud = load("res://scenes/ui/hud.tscn").instantiate()
	hud.sim = Simulation.new(1)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(hud)
	hud.set_process(false)
	await (Engine.get_main_loop() as SceneTree).process_frame
	for size in [Vector2i(1280, 720), Vector2i(2400, 1080), Vector2i(1080, 2400)]:
		hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
		hud.size = Vector2(size)
		hud.viewport_override = Vector2(size)
		hud.layout.update_size(Vector2(size))
		hud._apply_mode(LayoutMode.decide(Vector2(size)))
		hud._apply_layout()
		hud.show_actions("", [[&"close", "Закрыть", true]], Color(0, 0, 0, 0), [["Основное", _long_text()], ["Потребности", "x"], ["Семья и друзья", "y"]])
		await (Engine.get_main_loop() as SceneTree).process_frame
		await (Engine.get_main_loop() as SceneTree).process_frame
		hud._fit_bar()
		await (Engine.get_main_loop() as SceneTree).process_frame
		var r: Rect2 = hud._bar.get_rect()
		var tag := str(size)
		assert_true(r.position.y >= 0.0 and r.end.y <= float(size.y) + 0.5, "card inside screen %s: %s" % [tag, str(r)])
		assert_true(r.end.x <= float(size.x) + 0.5, "card inside width " + tag)
		if size.x > size.y:
			assert_true(r.end.y <= hud._dock.get_rect().position.y + 0.5, "card above dock %s: %s dock %s" % [tag, str(r), str(hud._dock.get_rect())])
		else:
			assert_true(r.end.y <= hud.fab.get_rect().position.y + 0.5, "card above fab " + tag)
		assert_eq(hud._bar_tab_buttons.size(), 3, "tabs")
		hud.select_card_tab(2)
		assert_eq(hud._bar_label.text, "y")
		hud.select_card_tab(0)
	hud.free()
