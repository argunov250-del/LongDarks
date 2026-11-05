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
const BRUSH_MIN := 2.0
const BRUSH_MAX := 24.0
const BRUSH_STEP := 2.0
const VILLAGER_TAP_MIN := 1.8

const REASON_TEXT := {
	&"": "можно ставить",
	&"outside": "за краем карты",
	&"water": "вода",
	&"slope": "крутой склон",
	&"overlap": "мешает другое здание",
	&"type": "неизвестный тип",
}

var con: ConstructionSystem
var production: ProductionSystem  # опционально (main выставляет после setup)
var villagers: VillagerSystem     # опционально: тап по жителю открывает карточку
var villagers_view: VillagersView # опционально: подсветка выбранного
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
var selected_villager := -1
var restore_menu := false
var felling_mode := false
var brush_radius := 6.0
var brush_circle := true
var brush_pos := Vector3.ZERO
var brush_cells: Array[Vector2i] = []
var economy: EconomySystem  # опционально: деревья в мире скрываются по запасам

var _ghost: Node3D
var _brush: MeshInstance3D
var _brush_drawn := -1.0
var _brush_circle_drawn := true
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
	hud.fell_requested.connect(start_felling_mode)
	hud.villager_card_requested.connect(select_villager)
	sim.bus.subscribe(ConstructionSystem.TOPIC_CHANGED, _on_changed)
	_on_changed({})


func _on_changed(_p: Dictionary) -> void:
	if world_view != null:
		world_view.sync_ruins(con)
		world_view.sync_trees(con.economy.deposits)


# ---------- размещение ----------

func is_placing() -> bool:
	return placing_type != &""


func start_placement(type: StringName) -> void:
	if not BuildingDefs.exists(type):
		return
	cancel_felling_mode()
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


# ---------- вырубка ----------

func start_felling_mode() -> void:
	cancel_placement()
	clear_selection()
	felling_mode = true
	_brush_drawn = -1.0
	_update_brush()


func cancel_felling_mode() -> void:
	if not felling_mode:
		return
	felling_mode = false
	brush_cells = []
	if _brush != null:
		_brush.queue_free()
		_brush = null
	hud.hide_actions()


func change_brush(delta: float) -> void:
	brush_radius = clampf(brush_radius + delta, BRUSH_MIN, BRUSH_MAX)
	_update_brush()


func toggle_brush_shape() -> void:
	brush_circle = not brush_circle
	_update_brush()


## Помечает клетки под кистью; режим закрывается. Возвращает число заданий.
func confirm_felling() -> int:
	if not felling_mode:
		return 0
	_update_brush()
	var n := con.start_felling(brush_cells)
	cancel_felling_mode()
	return n


func _update_brush() -> void:
	if not felling_mode:
		return
	var hit = pick_ground()
	if hit != null:
		brush_pos = hit
	brush_cells = con.fell_cells_in_brush(brush_pos, brush_radius, brush_circle)
	if _brush == null or _brush_drawn != brush_radius or _brush_circle_drawn != brush_circle:
		if _brush != null:
			_brush.queue_free()
		_brush = MeshInstance3D.new()
		_brush.name = "FellBrush"
		if brush_circle:
			var cm := CylinderMesh.new()
			cm.top_radius = brush_radius
			cm.bottom_radius = brush_radius
			cm.height = 0.3
			cm.radial_segments = 24
			_brush.mesh = cm
		else:
			var bm := BoxMesh.new()
			bm.size = Vector3(brush_radius * 2.0, 0.3, brush_radius * 2.0)
			_brush.mesh = bm
		_brush.material_override = BuildingMeshes._mat(BuildingMeshes.GHOST_OK, true)
		add_child(_brush)
		_brush_drawn = brush_radius
		_brush_circle_drawn = brush_circle
	_brush.position = Vector3(brush_pos.x, con.ground_height(brush_pos) + 0.2, brush_pos.z)
	hud.show_actions("Вырубка: %s, радиус %d м\nДеревьев в %d клетках леса" % [
			"круг" if brush_circle else "квадрат", roundi(brush_radius), brush_cells.size()], [
		[&"fell_shape", "Круг" if not brush_circle else "Квадрат", true],
		[&"fell_minus", "−", brush_radius > BRUSH_MIN],
		[&"fell_plus", "+", brush_radius < BRUSH_MAX],
		[&"fell_confirm", "Вырубить", not brush_cells.is_empty()],
		[&"fell_cancel", "Отмена", true]])


# ---------- выбор по тапу ----------

func clear_selection() -> void:
	selected_building = -1
	selected_ruin = -1
	selected_villager = -1
	if villagers_view != null:
		villagers_view.set_selected(-1)
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


func select_villager(id: int) -> void:
	if villagers == null or villagers.get_villager(id) == null:
		return
	cancel_placement()
	cancel_felling_mode()
	clear_selection()
	selected_villager = id
	if villagers_view != null:
		villagers_view.set_selected(id)
	_show_info()


## Радиус тапа по жителю растёт с удалением камеры.
func villager_pick_radius(p: Vector3) -> float:
	if camera == null or not camera.is_inside_tree():
		return VILLAGER_TAP_MIN
	return clampf(camera.global_position.distance_to(p) * 0.035, VILLAGER_TAP_MIN, 8.0)


func select_at(p: Vector3) -> void:
	if villagers != null:
		var v := villagers.villager_near(p, villager_pick_radius(p))
		if v != null:
			select_villager(v.id)
			return
	var b := con.building_at(p)
	if b != null:
		select_building(b.id)
		return
	var rid := con.ruin_at(p)
	if rid >= 0:
		select_ruin(rid)
	else:
		clear_selection()


func villager_card_text(v: Villager) -> String:
	var traits: Array[String] = []
	for t in v.traits:
		traits.append(TraitDefs.display_name(t))
	var t := "%s%s\n%s, %s, %s" % [v.display_name, " (герой)" if v.is_hero else "", v.profession_name(), VillagerDefs.sex_label(v.sex), VillagerDefs.age_text(v.age)]
	t += "\nЧерты: " + ", ".join(traits)
	t += "\nСейчас: " + villagers.task_text(v)
	t += "\n" + v.backstory
	return t


func _show_info() -> void:
	if selected_villager >= 0:
		var v := villagers.get_villager(selected_villager) if villagers != null else null
		if v == null:
			clear_selection()
			return
		hud.show_actions(villager_card_text(v), [[&"close", "Закрыть", true]])
	elif selected_building >= 0:
		var b := con.get_building(selected_building)
		if b == null:
			clear_selection()
			return
		var acts: Array = []
		if production != null and production.is_producing_building(b.id):
			acts.append([&"pause", "Продолжить" if production.is_paused(b.id) else "Пауза", true])
			if production.available_recipes(b.id).size() > 1:
				acts.append([&"recipe", "Рецепт", true])
		if villagers != null and (not b.is_done() or production != null and production.is_producing_building(b.id) or BuildingDefs.is_housing(b.type)):
			acts.append([&"bprio", _priority_label(b.id), true])
		acts.append([&"upgrade", _upgrade_label(b), con.can_upgrade(b.id)])
		if not b.is_done() and b.stage == BuildingDefs.Stage.FOUNDATION and not b.stage_paid and b.progress <= 0.0:
			acts.append([&"cancel_building", "Отменить чертёж", true])
		acts.append([&"close", "Закрыть", true])
		hud.show_actions(_building_text(b), acts)
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
			if con.is_dismantle_blocked(selected_ruin):
				title += " — склады полны"
		else:
			title += "\nМатериалы при разборе: " + _cost_text(con.ruin_yield(selected_ruin))
		hud.show_actions(title, [
			[&"restore", "Восстановить", not busy],
			[&"dismantle", "Разбирается…" if busy else "Разобрать", not busy],
			[&"close", "Закрыть", true]])


func _priority_label(id: int) -> String:
	var p := villagers.building_priority(id)
	return "Приоритет: авто" if p < 0 else "Приоритет: " + TaskDefs.PRIORITY_NAMES[p]


func _upgrade_label(b: Building) -> String:
	var nxt := BuildingDefs.upgrade_of(b.type)
	return "Улучшить" if nxt == &"" else "Улучшить: " + BuildingDefs.display_name(nxt)


func _building_text(b: Building) -> String:
	var t := BuildingDefs.display_name(b.type)
	if b.is_done():
		if production != null and production.is_producing_building(b.id):
			return t + "\n" + production_text(b.id)
		return t + "\nГотово"
	t += "\n%s: %d%%" % [BuildingDefs.STAGE_NAMES[b.stage], roundi(b.stage_fraction() * 100.0)]
	match b.blocked:
		&"resources":
			t += " — ждёт ресурсы: " + _cost_text(b.stage_cost())
		&"frozen":
			t += " — земля промёрзла"
		&"forest":
			t += " — ждёт вырубки"
	return t


const STALL_TEXT := {
	&"no_input": "ждёт сырьё",
	&"no_space": "нет места на складах",
}


## Строки состояния производства: рецепт, прогресс, причина простоя.
func production_text(id: int) -> String:
	var rid := production.recipe_of(id)
	var t := "%s: %s -> %s" % [Recipes.display_name(rid), _cost_text(Recipes.inputs(rid)), _cost_text(Recipes.outputs(rid))]
	t += "\nЦикл: %d%%" % roundi(production.progress_fraction(id) * 100.0)
	if production.is_paused(id):
		t += " — пауза"
	elif production.stall_reason(id) != &"":
		t += " — " + STALL_TEXT.get(production.stall_reason(id), "стоит")
	var q := production.repair_queue(id)
	if not q.is_empty():
		t += "\nРемонт в очереди: %d" % q.size()
	return t


## Обработчик кнопок панели действий.
func on_action(id: StringName) -> void:
	match id:
		&"fell_shape":
			toggle_brush_shape()
		&"fell_minus":
			change_brush(-BRUSH_STEP)
		&"fell_plus":
			change_brush(BRUSH_STEP)
		&"fell_confirm":
			confirm_felling()
		&"fell_cancel":
			cancel_felling_mode()
		&"rotate":
			rotate_ghost()
		&"confirm":
			confirm_placement()
		&"cancel":
			cancel_placement()
		&"close":
			clear_selection()
		&"cancel_building":
			con.cancel_building(selected_building)
			clear_selection()
		&"pause":
			if production != null:
				production.toggle_pause(selected_building)
			_show_info()
		&"recipe":
			if production != null:
				var rs := production.available_recipes(selected_building)
				var i := rs.find(production.recipe_of(selected_building))
				production.set_recipe(selected_building, rs[(i + 1) % rs.size()])
			_show_info()
		&"bprio":
			if villagers != null:
				var p := villagers.building_priority(selected_building) + 1  # авто -> 0 -> 1 -> 2 -> 3 -> авто
				villagers.set_building_priority(selected_building, -1 if p > TaskDefs.PRIORITY_MAX else p)
			_show_info()
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
	if felling_mode:
		_update_brush()
		return
	_acc += dt
	if _acc >= INFO_REFRESH:
		_acc = 0.0
		if selected_building >= 0 or selected_ruin >= 0 or selected_villager >= 0:
			_show_info()


func _unhandled_input(event: InputEvent) -> void:
	if is_placing() or felling_mode:
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
