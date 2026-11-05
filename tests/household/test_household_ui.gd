extends "res://tests/test_case.gd"

const Env = preload("res://tests/villagers/villager_env.gd")


func _bc(e: Env) -> Array:
	var hud: Hud = load("res://scenes/ui/hud.tscn").instantiate()
	hud.sim = e.sim
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	if not hud.is_node_ready():
		hud._ready()
	var bc := BuildController.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(bc)
	bc.setup(e.con, null, hud, null, e.sim)
	bc.villagers = e.vs
	return [hud, bc]


func test_build_tabs_have_well_and_canteen() -> void:
	assert_true(BuildingDefs.ids_in_tab(BuildingDefs.Tab.PRODUCTION).has(&"well"))
	assert_true(BuildingDefs.ids_in_tab(BuildingDefs.Tab.SOCIAL).has(&"canteen"))
	assert_true(BuildingDefs.total_cost(&"well").size() > 0 and BuildingDefs.total_cost(&"canteen").size() > 0)
	var e := Env.new()
	var r := _bc(e)
	var hud: Hud = r[0]
	for mode in [LayoutMode.Mode.LANDSCAPE, LayoutMode.Mode.PORTRAIT]:
		hud._apply_mode(mode)
		hud.select_tab(1)
		var names := []
		for b in hud._tab_items.get_children():
			names.append((b as Button).text)
		assert_true(names.has("Колодец"), "well in production tab")
		hud.select_tab(1)
		hud.select_tab(2)
		names = []
		for b in hud._tab_items.get_children():
			names.append((b as Button).text)
		assert_true(names.has("Столовая"), "canteen in social tab")
		hud.select_tab(2)
	hud.free()
	r[1].free()


func test_house_panel_shows_yard_and_builds_barn() -> void:
	var e := Env.new(5000, {&"logs": 20, &"planks": 20})
	var house := e.add_done(&"dugout", 10.0, 0.0)
	e.run(1.0)
	var r := _bc(e)
	var hud: Hud = r[0]
	var bc: BuildController = r[1]
	for mode in [LayoutMode.Mode.LANDSCAPE, LayoutMode.Mode.PORTRAIT]:
		hud._apply_mode(mode)
		var h := e.vs.household.home(house)
		h.barn = false
		if e.con.barn_of(house) != null:
			e.con.buildings.erase(e.con.barn_of(house).id)
		h.woodpile = 3
		bc.select_building(house)
		var txt: String = hud._bar_label.text
		for key in ["Печь", "Поленница: 3/", "Огород", "Вода", "Еда", "Сарай: нет"]:
			assert_true(txt.contains(key), "panel mentions " + key)
		assert_true(hud._bar_ids.has(&"build_barn"), "build barn button")
		var idx: int = hud._bar_ids.find(&"build_barn")
		assert_eq(hud._bar_buttons[idx].text, "Построить сарай")
		assert_false(hud._bar_buttons[idx].disabled)
		hud._bar_buttons[idx].pressed.emit()
		assert_true(e.con.barn_of(house) != null and not h.barn, "barn is a construction")
		assert_true(hud._bar_label.text.contains("строится"))
		assert_false(hud._bar_ids.has(&"build_barn"), "button gone once built")
		bc.clear_selection()
	hud.free()
	bc.free()


func test_canteen_panel() -> void:
	var e := Env.new()
	var c := e.add_done(&"canteen", 20.0, 0.0)
	e.run(1.0)
	e.vs.household.canteen(c).food.add(&"potato", 4)
	var r := _bc(e)
	r[1].select_building(c)
	assert_true(r[0]._bar_label.text.contains("картофель 4"))
	r[0].free()
	r[1].free()
