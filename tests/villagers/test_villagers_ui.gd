extends "res://tests/test_case.gd"

const Env = preload("res://tests/villagers/villager_env.gd")


func _hud(e: Env) -> Hud:
	var hud: Hud = load("res://scenes/ui/hud.tscn").instantiate()
	hud.sim = e.sim
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	if not hud.is_node_ready():
		hud._ready()
	hud.bind_villagers(e.vs)
	return hud


func test_villagers_panel_lists_everyone_both_layouts() -> void:
	var e := Env.new(5000, {&"logs": 40})
	var v := e.add_villager(&"cook", [&"strong", &"lazy"])
	var hud := _hud(e)
	for mode in [LayoutMode.Mode.LANDSCAPE, LayoutMode.Mode.PORTRAIT]:
		hud._apply_mode(mode)
		hud.villagers_button.pressed.emit()
		var ui := hud.villagers_ui
		assert_true(ui.is_open())
		assert_eq(ui.mode, VillagersUi.MODE_VILLAGERS)
		assert_eq(ui._rows.size(), 2)
		var info: RichTextLabel = ui._rows[v.id]["info"]
		assert_true(info.text.contains(v.display_name))
		assert_true(info.text.contains("повар"))
		assert_true(info.text.contains("[color=%s]сильный" % VillagersUi.GOOD_COLOR), "good trait green")
		assert_true(info.text.contains("[color=%s]ленивый" % VillagersUi.BAD_COLOR), "bad trait red")
		assert_true(info.text.contains("Свободен") or info.text.contains("Колет") or info.text.contains("Идёт"), "current task shown")
		ui.hide_panel()
		assert_false(ui.is_open())
	hud.free()


func test_card_button_opens_backstory() -> void:
	var e := Env.new()
	var v := e.add_villager(&"doctor", [&"careful"])
	var hud := _hud(e)
	var bc := BuildController.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(bc)
	bc.setup(e.con, null, hud, null, e.sim)
	bc.villagers = e.vs
	hud.villagers_button.pressed.emit()
	hud.villagers_ui._rows[v.id]["card"].pressed.emit()
	assert_eq(bc.selected_villager, v.id)
	assert_true(hud.is_actions_visible())
	assert_true(hud._bar_label.text.contains(v.backstory), "backstory in card")
	assert_true(hud._bar_label.text.contains("аккуратный"))
	# тап по жителю на карте
	bc.clear_selection()
	bc.select_at(v.pos)
	assert_eq(bc.selected_villager, v.id)
	bc.clear_selection()
	assert_false(hud.is_actions_visible())
	hud.free()
	bc.free()


func test_priorities_panel_buttons_change_system() -> void:
	var e := Env.new()
	var hud := _hud(e)
	for mode in [LayoutMode.Mode.PORTRAIT, LayoutMode.Mode.LANDSCAPE]:
		hud._apply_mode(mode)
		hud.priorities_button.pressed.emit()
		var ui := hud.villagers_ui
		assert_eq(ui._prio_rows.size(), TaskDefs.CATEGORIES.size())
		var cat := TaskDefs.BUILD
		e.vs.set_priority(cat, 2)
		ui._prio_rows[cat]["plus"].pressed.emit()
		assert_eq(e.vs.get_priority(cat), 3)
		assert_true(ui._prio_rows[cat]["plus"].disabled)
		ui._prio_rows[cat]["minus"].pressed.emit()
		ui._prio_rows[cat]["minus"].pressed.emit()
		ui._prio_rows[cat]["minus"].pressed.emit()
		assert_eq(e.vs.get_priority(cat), 0)
		assert_eq(ui._prio_rows[cat]["value"].text, "выкл")
		assert_true(ui._prio_rows[cat]["minus"].disabled)
		ui.hide_panel()
	hud.free()


func test_arrival_notification() -> void:
	var e := Env.new()
	var hud := _hud(e)
	assert_false(hud.villagers_ui.toast_panel.visible)
	var v := e.vs.spawn_newcomer()
	assert_true(hud.villagers_ui.toast_panel.visible)
	assert_true(hud.villagers_ui.toast_label.text.contains(v.display_name))
	hud.free()


func test_building_priority_action_cycles() -> void:
	var e := Env.new(5000, {&"logs": 40})
	var id := e.add_done(&"dugout", 10.0, 0.0)
	var hud := _hud(e)
	var bc := BuildController.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(bc)
	bc.setup(e.con, null, hud, null, e.sim)
	bc.villagers = e.vs
	bc.select_building(id)
	assert_true(hud._bar_ids.has(&"bprio"))
	var seen := [e.vs.building_priority(id)]
	for i in 5:
		bc.on_action(&"bprio")
		seen.append(e.vs.building_priority(id))
	assert_eq(seen, [-1, 0, 1, 2, 3, -1])
	hud.free()
	bc.free()


func test_figures_and_view_sync() -> void:
	var e := Env.new()
	for p in VillagerDefs.PROFESSIONS:
		var n := VillagerFigures.make_villager(p, false)
		assert_true(n.get_node("Body/Torso") != null)
		n.free()
	var hero_fig := VillagerFigures.make_villager(&"mechanic", true)
	assert_true(hero_fig.has_node("Mark"))
	hero_fig.free()
	var view := VillagersView.new()
	view.setup(e.vs)
	assert_true(view.node_for(e.hero().id) != null)
	assert_true(view.dog_node() != null)
	var v := e.add_villager(&"fisher")
	view._sync()
	assert_true(view.node_for(v.id) != null)
	e.vs.remove_villager(v.id)
	view._sync()
	assert_true(view.node_for(v.id) == null or view.node_for(v.id).is_queued_for_deletion())
	e.vs.dog.set_anxious(1.0)
	view._t = 1.0
	view._pose_dog()
	assert_true(absf(view.dog_node().get_node("Body").position.x) > 0.0, "anxious dog paces")
	view.free()
