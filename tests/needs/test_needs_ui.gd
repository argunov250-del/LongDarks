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


func test_list_shows_need_warnings() -> void:
	var e := Env.new()
	var v := e.add_villager(&"cook")
	var hud := _hud(e)
	hud.villagers_button.pressed.emit()
	var ui := hud.villagers_ui
	var info: RichTextLabel = ui._rows[v.id]["info"]
	assert_false(info.text.contains("голоден"), "no warning when fine")
	v.set_need(NeedsDefs.FOOD, 0.1)
	v.set_need(NeedsDefs.WATER, 0.1)
	v.set_need(NeedsDefs.WARMTH, 0.1)
	v.set_need(NeedsDefs.REST, 0.05)
	v.sick = true
	ui.refresh()
	for w in ["голоден", "жажда", "холодно", "устал", "болен"]:
		assert_true(info.text.contains(w), "warning: " + w)
	hud.free()


func test_sick_and_death_notifications() -> void:
	var e := Env.new()
	e.enable_needs()
	var v := e.add_villager(&"fisher")
	var hud := _hud(e)
	e.vs.needs.fall_sick(v)
	assert_true(hud.villagers_ui.toast_panel.visible)
	assert_true(hud.villagers_ui.toast_label.text.contains("Заболел"))
	assert_true(hud.villagers_ui.toast_label.text.contains(v.display_name))
	assert_true(e.vs.kill_villager(v.id, &"sickness"))
	assert_true(hud.villagers_ui.toast_label.text.contains("Погиб"))
	assert_true(hud.villagers_ui.toast_label.text.contains(v.display_name))
	hud.free()


func test_card_and_house_panel_show_needs_and_residents() -> void:
	var e := Env.new(5000, {&"logs": 40})
	e.enable_needs()
	var id := e.add_done(&"dugout", 10.0, 0.0)
	var hosp := e.add_done(&"hospital", 14.0, -10.0)
	var v := e.add_villager(&"cook")
	e.vs.needs.assign_homes()
	var hud := _hud(e)
	var bc := BuildController.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(bc)
	bc.setup(e.con, null, hud, null, e.sim)
	bc.villagers = e.vs
	v.set_need(NeedsDefs.FOOD, 0.1)
	var card := bc.villager_card_text(v)
	assert_true(card.contains("Потребности"))
	assert_true(card.contains("Еда") and card.contains("Вода") and card.contains("Тепло") and card.contains("Отдых") and card.contains("Здоровье"))
	assert_true(card.contains("голоден"))
	assert_true(card.contains("Землянка"), "home shown")
	var txt := bc.household_text(e.con.get_building(id))
	assert_true(txt.contains("Жильцы: 2/2") or txt.contains("Жильцы: 1/2") or txt.contains("Жильцы"), "residents")
	assert_true(txt.contains(v.display_name))
	assert_true(txt.contains("Тепло:"))
	assert_true(bc._building_text(e.con.get_building(hosp)).contains("Койки"))
	hud.free()
	bc.free()
