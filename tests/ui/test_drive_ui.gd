extends "res://tests/test_case.gd"
## Step 21 UI: settings panel, driving screen layout, and building lists in tabs never overflow
## (every building button is on screen or reachable by scrolling) at 1280x720, 2400x1080, 1080x2400.

const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(2400, 1080), Vector2i(1080, 2400)]
const TMP_CFG := "user://test_hud_settings.cfg"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _make_hud(size: Vector2i) -> Hud:
	_tree().root.size = size
	var hud: Hud = load("res://scenes/ui/hud.tscn").instantiate()
	hud.sim = Simulation.new(1)
	hud.drive_settings = DriveSettings.new(TMP_CFG)
	_tree().root.add_child(hud)
	await _tree().process_frame
	await _tree().process_frame
	return hud


func test_building_lists_reachable_at_all_sizes() -> void:
	for size in SIZES:
		var hud := await _make_hud(size)
		var vp := _tree().root.get_visible_rect()
		for tab in Hud.TABS.size():
			if hud.mode == LayoutMode.Mode.PORTRAIT:
				hud.toggle_menu()  # the portrait sheet is hidden until the FAB is pressed
			hud.select_tab(tab)
			await _tree().process_frame
			await _tree().process_frame
			var list := hud.tab_list()
			var lr := list.get_global_rect()
			assert_true(vp.encloses(lr.grow(-1.0)), "%s tab %d: list %s inside screen %s (title %s tabs %s gap %s dp %s maxh %s availw %s min %s dock %s panel %s top %s)" % [size, tab, lr, vp, hud._tab_title.get_combined_minimum_size(), hud._tabs_scroll.custom_minimum_size, hud._tabs_row.get_theme_constant("separation"), hud._dp, hud._list_max_h, hud._list_avail_w, list.custom_minimum_size, hud._dock.get_global_rect(), hud._tab_panel.get_global_rect(), hud._top_bar.get_global_rect()])
			var scrollable := list.get_v_scroll_bar().max_value > list.get_v_scroll_bar().page + 1.0
			var ids := BuildingDefs.ids_in_tab(tab)
			var items := list.get_child(0).get_children()
			assert_eq(items.size(), ids.size(), "all buildings listed")
			for b: Control in items:
				var br := b.get_global_rect()
				var visible_now := lr.grow(1.0).encloses(br)
				assert_true(visible_now or scrollable, "%s tab %d: button %s reachable (%s vs %s)" % [size, tab, (b as Button).text, br, lr])
				assert_true(br.size.x <= lr.size.x + 1.0, "button not wider than the list")
			hud.select_tab(tab)  # collapse
			if hud.mode == LayoutMode.Mode.PORTRAIT:
				hud.toggle_menu()
		hud.queue_free()
		await _tree().process_frame


func test_flow_rows() -> void:
	assert_eq(Hud.flow_rows([], 100.0, 4.0), 0)
	assert_eq(Hud.flow_rows([40.0, 40.0], 100.0, 4.0), 1)
	assert_eq(Hud.flow_rows([40.0, 40.0, 40.0], 100.0, 4.0), 2)
	assert_eq(Hud.flow_rows([300.0, 300.0], 100.0, 4.0), 2, "an over-wide item is clamped to its own row")


func test_settings_panel_switches_and_saves_scheme() -> void:
	DirAccess.remove_absolute(TMP_CFG)
	var hud := await _make_hud(Vector2i(1080, 2400))
	hud.do_settings()
	assert_true(hud._settings_panel.visible)
	assert_eq(hud._scheme_buttons.size(), 3)
	(hud._scheme_buttons[ManualDriveDefs.SCHEME_TILT] as Button).pressed.emit()
	assert_eq(hud.drive_settings.scheme, ManualDriveDefs.SCHEME_TILT)
	var again := DriveSettings.new(TMP_CFG)
	again.load()
	assert_eq(again.scheme, ManualDriveDefs.SCHEME_TILT, "persisted to user://")
	assert_true((hud._scheme_buttons[ManualDriveDefs.SCHEME_TILT] as Button).button_pressed)
	hud.queue_free()
	DirAccess.remove_absolute(TMP_CFG)


func test_drive_layout_inside_screen_for_every_scheme() -> void:
	var ins := {"left": 0.0, "top": 60.0, "right": 0.0, "bottom": 40.0}
	for size in SIZES:
		var vp := Vector2(size)
		var dp := maxf(minf(vp.x, vp.y) / Hud.REF_SHORT_SIDE_DP, 1.0)
		for sc in ManualDriveDefs.SCHEMES:
			var lay := DriveHud.compute_layout(vp, dp, ins, sc)
			for k in lay:
				assert_true(Rect2(Vector2.ZERO, vp).encloses(lay[k]), "%s %s %s inside the screen" % [size, sc, k])
			if sc == ManualDriveDefs.SCHEME_BUTTONS:
				assert_false((lay["left"] as Rect2).intersects(lay["right"]), "buttons do not overlap")
				assert_false((lay["gas"] as Rect2).intersects(lay["brake"]))


func test_drive_hud_touch_controls() -> void:
	var pad := DriveHud.new()
	pad.regions = DriveHud.compute_layout(Vector2(1080, 2400), 2.6, {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}, ManualDriveDefs.SCHEME_BUTTONS)
	pad.scheme = ManualDriveDefs.SCHEME_BUTTONS
	pad._press(1, (pad.regions["gas"] as Rect2).get_center())
	pad._press(2, (pad.regions["left"] as Rect2).get_center())
	assert_eq(pad.buttons.axes(), Vector2(-1, 1), "multi-touch: gas + left at once")
	pad._release(1)
	assert_eq(pad.buttons.axes(), Vector2(-1, 0))
	pad.release_all()
	assert_eq(pad.buttons.axes(), Vector2.ZERO, "no stuck input")
	pad.regions = DriveHud.compute_layout(Vector2(1080, 2400), 2.6, {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}, ManualDriveDefs.SCHEME_JOYSTICK)
	var c: Vector2 = (pad.regions["joystick"] as Rect2).get_center()
	pad._press(3, c)
	pad._drag(3, c + Vector2(0.0, -400.0))
	assert_almost_eq(pad.joystick.throttle(), 1.0, 0.001, "stick up = full gas")
	pad._release(3)
	assert_eq(pad.joystick.axes(), Vector2.ZERO)
	pad.free()
