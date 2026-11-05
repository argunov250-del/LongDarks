class_name BuildController
extends Node
## Связывает HUD, камеру и ConstructionSystem: режим размещения (призрак в центре
## экрана, камера двигается под ним) и панель выбранного здания/руины по тапу.
## Только UI-логика; правила строительства — в ConstructionSystem.

const ROTATE_STEP := deg_to_rad(15.0)
const TAP_MAX_MOVE := 14.0     # px
const TAP_MAX_TIME_MS := 400
const PICK_STEP := 0.5
const PICK_MAX := 600.0
const INFO_REFRESH := 0.25

const REASON_TEXT := {
	&"": "можно ставить",
	&"outside": "за краем карты",
	&"water": "вода",
	&"slope": "крутой склон",
	&"overlap": "мешает другое здание",
	&"type": "неизвестный тип",
}

var con: ConstructionSystem
var camera: Camera3D
var hud: Hud
var world_view: WorldView
var map: WorldMap

var placing_type: StringName = &""
var ghost_rot := 0.0
var ghost_pos := Vector3.ZERO
var ghost_valid := false
var ghost_reason: StringName = &""
var selected_building := -1
var selected_ruin := -1
var restore_menu := false

var _ghost: Node3D
var _ghost_valid_drawn := -1
var _ghost_type_drawn: StringName = &""
var _press_pos := Vector2.ZERO
var _press_time := 0
var _pressing := false
var _acc := 0.0


func setup(construction: ConstructionSystem, cam: Camera3D, hud_in: Hud, view: WorldView, sim: Simulation) -> void:
	con = construction
	camera = cam
	hud = hud_in
	world_view = view
	map = con.world
	hud.build_selected.connect(start_placement)
	hud.action_pressed.connect(on_action)
	sim.bus.subscribe(ConstructionSystem.TOPIC_CHANGED, _on_changed)
	_on_changed({})


func _on_changed(_p: Dictionary) -> void:
	if world_view != null:
		world_view.sync_ruins(con)


# ---------- размещение ----------

func is_placing() -> bool:
	return placing_type != &""


func start_placement(type: StringName) -> void:
	if not BuildingDefs.exists(type):
		return
	clear_selection()
	placing_type = type
	ghost_rot = 0.0
	_ghost_valid_drawn = -1
	_update_ghost(true)


func cancel_placement() -> void:
	placing_type = &""
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	hud.hide_actions()


func rotate_ghost() -> void:
	ghost_rot = wrapf(ghost_rot + ROTATE_STEP, 0.0, TAU)
	_update_ghost(false)


func confirm_placement() -> int:
	if not is_placing():
		return -1
	_update_ghost(false)
	if not ghost_valid:
		return -1
	var id := con.place(placing_type, ghost_pos, ghost_rot)
	if id > 0:
		cancel_placement()
		select_building(id)
	return id


## Точка земли под центром вьюпорта (или под pos).
func pick_ground(screen: Variant = null) -> Variant:
	if camera == null or not camera.is_inside_tree():
		return null
	var sp: Vector2 = screen if screen != null else camera.get_viewport().get_visible_rect().size * 0.5
	return ground_hit(camera.project_ray_origin(sp), camera.project_ray_normal(sp), map)


## Пересечение луча с рельефом: шаг + бисекция. null — не попал.
static func ground_hit(origin: Vector3, dir: Vector3, m: WorldMap) -> Variant:
	var t := 0.0
	var prev := 0.0
	while t < PICK_MAX:
		var p := origin + dir * t
		if p.y <= m.height_at(p.x, p.z):
			var lo := prev
			var hi := t
			for _i in 12:
				var mid := (lo + hi) * 0.5
				var q := origin + dir * mid
				if q.y <= m.height_at(q.x, q.z):
					hi = mid
				else:
					lo = mid
			var r := origin + dir * hi
			r.y = m.height_at(r.x, r.z)
			return r
		prev = t
		t += PICK_STEP
	return null


func _update_ghost(force_ui: bool) -> void:
	if not is_placing():
		return
	var hit = pick_ground()
	if hit != null:
		ghost_pos = hit
	var v := con.validate_placement(placing_type, ghost_pos, ghost_rot)
	ghost_valid = v["ok"]
	ghost_reason = v["reason"]
	if _ghost == null or _ghost_valid_drawn != int(ghost_valid) or _ghost_type_drawn != placing_type:
		if _ghost != null:
			_ghost.queue_free()
		_ghost = BuildingMeshes.make(placing_type, BuildingDefs.Stage.DONE, 1.0,
				BuildingMeshes.GHOST_OK if ghost_valid else BuildingMeshes.GHOST_BAD)
		_ghost.name = "Ghost"
		add_child(_ghost)  # узел контроллера должен находиться в 3D-дереве (см. main)
		_ghost_valid_drawn = int(ghost_valid)
		_ghost_type_drawn = placing_type
	_ghost.position = Vector3(ghost_pos.x, con.ground_height(ghost_pos), ghost_pos.z)
	_ghost.rotation.y = ghost_rot
	_show_placement_bar()


func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost:
		parts.append("%s %d" % [ResourceDefs.display_name(k), cost[k]])
	return ", ".join(parts)


func _show_placement_bar() -> void:
	var title := "%s: %s\nЦена: %s" % [
		BuildingDefs.display_name(placing_type), REASON_TEXT.get(ghost_reason, ""),
		_cost_text(BuildingDefs.total_cost(placing_type))]
	hud.show_actions(title, [
		[&"rotate", "Повернуть", true],
		[&"confirm", "Поставить", ghost_valid],
		[&"cancel", "Отмена", true]])


# ---------- выбор по тапу ----------

func clear_selection() -> void:
	selected_building = -1
	selected_ruin = -1
	restore_menu = false
	if not is_placing():
		hud.hide_actions()


func select_building(id: int) -> void:
	clear_selection()
	if con.get_building(id) != null:
		selected_building = id
		_show_info()


func select_ruin(rid: int) -> void:
	clear_selection()
	if con.is_ruin_active(rid):
		selected_ruin = rid
		_show_info()


func select_at(p: Vector3) -> void:
	var b := con.building_at(p)
	if b != null:
		select_building(b.id)
		return
	var rid := con.ruin_at(p)
	if rid >= 0:
		select_ruin(rid)
	else:
		clear_selection()


func _show_info() -> void:
	if selected_building >= 0:
		var b := con.get_building(selected_building)
		if b == null:
			clear_selection()
			return
		hud.show_actions(_building_text(b), [
			[&"upgrade", _upgrade_label(b), con.can_upgrade(b.id)],
			[&"close", "Закрыть", true]])
	elif selected_ruin >= 0:
		if not con.is_ruin_active(selected_ruin):
			clear_selection()
			return
		if restore_menu:
			var acts: Array = []
			for t in BuildingDefs.ids_in_tab(BuildingDefs.Tab.HOUSING) + BuildingDefs.ids_in_tab(BuildingDefs.Tab.PRODUCTION) + BuildingDefs.ids_in_tab(BuildingDefs.Tab.SOCIAL) + BuildingDefs.ids_in_tab(BuildingDefs.Tab.DEFENSE):
				if BuildingDefs.is_restorable(t):
					acts.append([StringName("restore:" + t), BuildingDefs.display_name(t), true])
			acts.append([&"back", "Назад", true])
			hud.show_actions("Восстановить руины как (цена вдвое меньше):", acts)
			return
		var busy := con.is_dismantling(selected_ruin)
		var title := "Руины"
		if busy:
			title += "\nРазбор: %d%%" % roundi(con.dismantle_fraction(selected_ruin) * 100.0)
		else:
			title += "\nМатериалы при разборе: " + _cost_text(con.ruin_yield(selected_ruin))
		hud.show_actions(title, [
			[&"restore", "Восстановить", not busy],
			[&"dismantle", "Разбирается…" if busy else "Разобрать", not busy],
			[&"close", "Закрыть", true]])


func _upgrade_label(b: Building) -> String:
	var nxt := BuildingDefs.upgrade_of(b.type)
	return "Улучшить" if nxt == &"" else "Улучшить: " + BuildingDefs.display_name(nxt)


func _building_text(b: Building) -> String:
	var t := BuildingDefs.display_name(b.type)
	if b.is_done():
		return t + "\nГотово"
	t += "\n%s: %d%%" % [BuildingDefs.STAGE_NAMES[b.stage], roundi(b.stage_fraction() * 100.0)]
	match b.blocked:
		&"resources":
			t += " — ждёт ресурсы: " + _cost_text(b.stage_cost())
		&"frozen":
			t += " — земля промёрзла"
	return t


## Обработчик кнопок панели действий.
func on_action(id: StringName) -> void:
	match id:
		&"rotate":
			rotate_ghost()
		&"confirm":
			confirm_placement()
		&"cancel":
			cancel_placement()
		&"close":
			clear_selection()
		&"upgrade":
			con.upgrade(selected_building)
			_show_info()
		&"restore":
			restore_menu = true
			_show_info()
		&"back":
			restore_menu = false
			_show_info()
		&"dismantle":
			con.start_dismantle(selected_ruin)
			_show_info()
		_:
			if String(id).begins_with("restore:"):
				var bid := con.restore_ruin(selected_ruin, StringName(String(id).trim_prefix("restore:")))
				if bid > 0:
					select_building(bid)
				else:
					restore_menu = false
					_show_info()


# ---------- кадр и ввод ----------

func _process(dt: float) -> void:
	if is_placing():
		_update_ghost(false)
		return
	_acc += dt
	if _acc >= INFO_REFRESH:
		_acc = 0.0
		if selected_building >= 0 or selected_ruin >= 0:
			_show_info()


func _unhandled_input(event: InputEvent) -> void:
	if is_placing():
		return
	if event is InputEventScreenTouch and event.index > 0:
		_pressing = false  # многопальцевый жест камеры — не тап
		return
	var pos := Vector2.ZERO
	var pressed := false
	var released := false
	if event is InputEventScreenTouch:
		pos = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		pressed = event.pressed
		released = not event.pressed
	else:
		return
	if pressed:
		_pressing = true
		_press_pos = pos
		_press_time = Time.get_ticks_msec()
	elif released and _pressing:
		_pressing = false
		if pos.distance_to(_press_pos) <= TAP_MAX_MOVE and Time.get_ticks_msec() - _press_time <= TAP_MAX_TIME_MS:
			var hit = pick_ground(pos)
			if hit != null:
				select_at(hit)
