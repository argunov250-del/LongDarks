class_name Hud
extends Control
## Оболочка интерфейса: верхняя панель (дата/время/скорость), вкладки
## строительства и меню. Одни и те же действия и узлы используются в обоих
## режимах; меняется только расположение (см. LayoutMode).
## Корень и пустые контейнеры пропускают касания (mouse_filter = IGNORE),
## чтобы жесты камеры работали вне элементов управления.

signal build_selected(type_id: StringName)   # выбрано здание во вкладке строительства
signal field_requested                        # «Поле» (шаг 16): кисть полей с выбором культуры
signal plant_requested                        # «Посадить лес» (шаг 17)
signal road_requested                         # «Дорога» (шаг 18)
signal heal_requested                         # «Лечить землю» (шаг 17)
signal fell_requested                         # кнопка «Вырубка» во вкладках строительства
signal action_pressed(id: StringName)         # кнопка панели действий (размещение/здание/руина)
signal villager_card_requested(id: int)       # «Карточка» в списке жителей

const MIN_TOUCH_DP := 48.0
const REF_SHORT_SIDE_DP := 411.0  # типичная короткая сторона телефона в dp
const TABS: Array[String] = ["Жильё", "Производство", "Социальные", "Защита"]
const SPEED_LABELS: Array[String] = ["II", "1x", "2x", "3x"]

var sim: Simulation
var layout := LayoutMode.new()
var mode: int = -1

var date_label: Label
var time_label: Label
var speed_buttons: Array[Button] = []
var tab_buttons: Array[Button] = []
var field_button: Button
var plant_button: Button
var heal_button: Button
var road_button: Button
var fell_button: Button      # режим вырубки леса (рядом с вкладками)
var menu_button: Button      # ландшафт: кнопка меню в верхней панели
var fab: Button              # портрет: плавающая кнопка
var save_button: Button
var load_button: Button
var settings_button: Button
var villagers_button: Button
var priorities_button: Button
var status_label: Label
var seasons: SeasonSystem      # шаг 13: «Весна, день 3» и температура (null — только «День N»)
var villagers_ui: VillagersUi  # панели «Жители», «Приоритеты», уведомления

var _top_bar: PanelContainer
var _top_row: HBoxContainer
var _tabs_row: HBoxContainer
var _tab_panel: PanelContainer
var _tab_title: Label
var _tab_items: HFlowContainer
var _bar: PanelContainer          # панель действий под верхней панелью
var _bar_label: Label
var _bar_row: HFlowContainer
var _bar_ids: Array = []
var _bar_buttons: Array[Button] = []
var _menu_box: VBoxContainer
var _menu_popup: PanelContainer   # ландшафт: выпадающее меню
var _dock: VBoxContainer          # ландшафт: нижняя док-панель
var _sheet: PanelContainer        # портрет: нижний лист
var _sheet_box: VBoxContainer
var _base_theme: Theme
var _selected_tab := -1
var _dp := 2.6
var _last_text := ""


static func format_time(time_of_day: float) -> String:
	var minutes := int(floor(clampf(time_of_day, 0.0, 0.999999) * 1440.0))
	return "%02d:%02d" % [minutes / 60, minutes % 60]


static func format_date(day: int) -> String:
	return "День %d" % day


## «Весна, день 3».
static func format_season_date(season_name: String, day_of_season: int) -> String:
	return "%s, день %d" % [season_name, day_of_season]


## «-8 °C», «+12 °C» (знак минус — обычный дефис).
static func format_temp(temp: float) -> String:
	var t := roundi(temp)
	return ("%+d °C" % t) if t != 0 else "0 °C"


## Отступы безопасной зоны (в единицах вьюпорта). Пустой Rect -> нули.
static func safe_margins(safe: Rect2i, window: Vector2i, viewport: Vector2) -> Dictionary:
	var m := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if window.x <= 0 or window.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return m
	var sx := viewport.x / window.x
	var sy := viewport.y / window.y
	m["left"] = maxf(0.0, safe.position.x) * sx
	m["top"] = maxf(0.0, safe.position.y) * sy
	m["right"] = maxf(0.0, window.x - safe.end.x) * sx
	m["bottom"] = maxf(0.0, window.y - safe.end.y) * sy
	return m


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if sim == null:
		var runner := get_node_or_null("/root/SimRunner")
		if runner != null:
			sim = runner.sim
	_base_theme = theme
	_build()
	layout.update_size(_vp_size())
	add_child(layout)
	layout.mode_changed.connect(_apply_mode)
	if is_inside_tree():
		get_viewport().size_changed.connect(_apply_layout)
	_apply_mode(layout.mode)
	_refresh_clock(true)


func _process(_delta: float) -> void:
	_refresh_clock(false)


# ---------- действия (общие для обоих режимов) ----------

func set_speed(value: int) -> void:
	if sim != null and sim.clock.set_speed(value):
		_refresh_speed_buttons()


func select_tab(index: int) -> void:
	_selected_tab = -1 if index == _selected_tab else index  # повторное нажатие сворачивает
	for i in tab_buttons.size():
		tab_buttons[i].set_pressed_no_signal(i == _selected_tab)
	_tab_panel.visible = _selected_tab >= 0
	if _selected_tab >= 0:
		_tab_title.text = TABS[_selected_tab]
		_fill_tab_items(_selected_tab)


func _fill_tab_items(tab: int) -> void:
	for c in _tab_items.get_children():
		_tab_items.remove_child(c)
		c.queue_free()
	for id in BuildingDefs.ids_in_tab(tab):
		var b := _mk_button(BuildingDefs.display_name(id))
		b.custom_minimum_size = Vector2(0.0, MIN_TOUCH_DP * _dp)
		b.pressed.connect(_on_build_item.bind(id))
		_tab_items.add_child(b)


func _on_build_item(id: StringName) -> void:
	select_tab(_selected_tab)  # свернуть вкладку
	build_selected.emit(id)


## Панель действий: заголовок + кнопки [id, текст, включена]. Если набор id не
## изменился, обновляются только тексты/состояния (нажатие не прерывается).
func show_actions(title: String, actions: Array) -> void:
	_bar_label.text = title
	var ids: Array = []
	for a in actions:
		ids.append(a[0])
	if ids != _bar_ids:
		for c in _bar_row.get_children():
			_bar_row.remove_child(c)
			c.queue_free()
		_bar_buttons.clear()
		_bar_ids = ids
		for a in actions:
			var b := _mk_button(a[1])
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size = Vector2(0.0, MIN_TOUCH_DP * _dp)
			b.pressed.connect(func(): action_pressed.emit(a[0]))
			_bar_row.add_child(b)
			_bar_buttons.append(b)
	for i in actions.size():
		_bar_buttons[i].text = actions[i][1]
		_bar_buttons[i].disabled = not actions[i][2]
	_bar.visible = true


func hide_actions() -> void:
	_bar.visible = false
	_bar_ids = []


func is_actions_visible() -> bool:
	return _bar.visible


func do_save() -> void:
	_set_status("Сохранено" if SimRunner.quick_save() == OK else "Ошибка сохранения")


func do_load() -> void:
	_set_status("Загружено" if SimRunner.quick_load() == OK else "Нет сохранения")
	_refresh_clock(true)


func do_settings() -> void:
	_set_status("Настройки: скоро")


## Подключает панели жителей к системе (main/тесты).
func bind_seasons(system: SeasonSystem) -> void:
	seasons = system
	_refresh_clock(true)


## Короткое сообщение о начале погодного события (прогноза в интерфейсе нет).
func bind_weather(sim_in: Simulation) -> void:
	sim_in.bus.subscribe(WeatherSystem.TOPIC_STARTED, func(p: Dictionary) -> void:
		villagers_ui.show_toast(WeatherDefs.toast_text(p.get("id", &""))))


func bind_villagers(system: VillagerSystem) -> void:
	villagers_ui.bind(system, sim)


func show_villagers_panel(panel_mode: StringName) -> void:
	_menu_popup.visible = false
	_sheet.visible = false
	villagers_ui.show_panel(panel_mode)


func toggle_menu() -> void:
	if mode == LayoutMode.Mode.LANDSCAPE:
		_menu_popup.visible = not _menu_popup.visible
	else:
		_sheet.visible = not _sheet.visible


func _set_status(text: String) -> void:
	status_label.text = text
	status_label.visible = text != ""


# ---------- построение ----------

func _mk_button(text: String, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	return b


func _mk_box(box: BoxContainer) -> BoxContainer:
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


func _build() -> void:
	_top_bar = PanelContainer.new()
	add_child(_top_bar)
	_top_row = _mk_box(HBoxContainer.new())
	_top_bar.add_child(_top_row)
	var dt: VBoxContainer = _mk_box(VBoxContainer.new())
	dt.add_theme_constant_override("separation", 0)
	_top_row.add_child(dt)
	date_label = Label.new()
	time_label = Label.new()
	for l in [date_label, time_label]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dt.add_child(l)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_row.add_child(spacer)
	for i in GameClock.SPEEDS.size():
		var b := _mk_button(SPEED_LABELS[i], true)
		b.pressed.connect(set_speed.bind(GameClock.SPEEDS[i]))
		speed_buttons.append(b)
		_top_row.add_child(b)
	menu_button = _mk_button("Меню")
	menu_button.pressed.connect(toggle_menu)
	_top_row.add_child(menu_button)

	# Вкладки, панель вкладки и меню переставляются между режимами.
	_tabs_row = _mk_box(HBoxContainer.new())
	for i in TABS.size():
		var t := _mk_button(TABS[i], true)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.pressed.connect(select_tab.bind(i))
		tab_buttons.append(t)
		_tabs_row.add_child(t)
	fell_button = _mk_button("Вырубка")
	fell_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fell_button.pressed.connect(func(): fell_requested.emit())
	_tabs_row.add_child(fell_button)
	field_button = _mk_button("Поле")
	field_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_button.pressed.connect(func(): field_requested.emit())
	_tabs_row.add_child(field_button)
	plant_button = _mk_button("Посадить лес")
	plant_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plant_button.pressed.connect(func(): plant_requested.emit())
	_tabs_row.add_child(plant_button)
	heal_button = _mk_button("Лечить землю")
	heal_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heal_button.pressed.connect(func(): heal_requested.emit())
	_tabs_row.add_child(heal_button)
	road_button = _mk_button("Дорога")
	road_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	road_button.pressed.connect(func(): road_requested.emit())
	_tabs_row.add_child(road_button)
	_tab_panel = PanelContainer.new()
	_tab_title = Label.new()
	_tab_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tab_box := _mk_box(VBoxContainer.new())
	_tab_panel.add_child(tab_box)
	tab_box.add_child(_tab_title)
	_tab_items = HFlowContainer.new()
	_tab_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab_box.add_child(_tab_items)
	_tab_panel.visible = false
	_menu_box = _mk_box(VBoxContainer.new())
	save_button = _mk_button("Сохранить")
	save_button.pressed.connect(do_save)
	load_button = _mk_button("Загрузить")
	load_button.pressed.connect(do_load)
	settings_button = _mk_button("Настройки")
	settings_button.pressed.connect(do_settings)
	villagers_button = _mk_button("Жители")
	villagers_button.pressed.connect(show_villagers_panel.bind(VillagersUi.MODE_VILLAGERS))
	priorities_button = _mk_button("Приоритеты")
	priorities_button.pressed.connect(show_villagers_panel.bind(VillagersUi.MODE_PRIORITIES))
	status_label = Label.new()
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.visible = false
	for c in [villagers_button, priorities_button, save_button, load_button, settings_button, status_label]:
		_menu_box.add_child(c)

	# Ландшафт: нижняя док-панель и всплывающее меню.
	_dock = _mk_box(VBoxContainer.new())
	add_child(_dock)
	_menu_popup = PanelContainer.new()
	_menu_popup.visible = false
	add_child(_menu_popup)

	# Портрет: нижний лист и плавающая кнопка.
	_sheet = PanelContainer.new()
	_sheet.visible = false
	add_child(_sheet)
	_sheet_box = _mk_box(VBoxContainer.new())
	_sheet.add_child(_sheet_box)
	_bar = PanelContainer.new()
	_bar.visible = false
	add_child(_bar)
	var bar_box := _mk_box(VBoxContainer.new())
	_bar.add_child(bar_box)
	_bar_label = Label.new()
	_bar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar_box.add_child(_bar_label)
	_bar_row = HFlowContainer.new()
	_bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_box.add_child(_bar_row)
	villagers_ui = VillagersUi.new()
	villagers_ui.name = "VillagersUi"
	villagers_ui.villager_pressed.connect(func(id): villager_card_requested.emit(id))
	add_child(villagers_ui)
	fab = _mk_button("☰")
	fab.pressed.connect(toggle_menu)
	add_child(fab)


func _reparent_to(node: Control, new_parent: Node) -> void:
	if node.get_parent() == new_parent:
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	new_parent.add_child(node)


func _apply_mode(new_mode: int) -> void:
	mode = new_mode
	var land := mode == LayoutMode.Mode.LANDSCAPE
	menu_button.visible = land
	fab.visible = not land
	_dock.visible = land
	_menu_popup.visible = false
	_sheet.visible = false
	if land:
		_reparent_to(_tab_panel, _dock)
		_reparent_to(_tabs_row, _dock)
		_reparent_to(_menu_box, _menu_popup)
	else:
		_reparent_to(_tabs_row, _sheet_box)
		_reparent_to(_tab_panel, _sheet_box)
		_reparent_to(_menu_box, _sheet_box)
	_apply_layout()


func _set_anchors(c: Control, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = l
	c.anchor_top = t
	c.anchor_right = r
	c.anchor_bottom = b


func _apply_layout() -> void:
	if _top_bar == null:
		return
	var vp := _vp_size()
	_dp = maxf(minf(vp.x, vp.y) / REF_SHORT_SIDE_DP, 1.0)
	var t: Theme = _base_theme.duplicate() if _base_theme != null else Theme.new()
	t.default_font_size = roundi(15.0 * _dp)
	theme = t
	var land := mode == LayoutMode.Mode.LANDSCAPE
	var touch := MIN_TOUCH_DP * _dp
	var gap := roundi(6.0 * _dp)
	for c in [_top_row, _tabs_row, _dock, _menu_box, _sheet_box]:
		c.add_theme_constant_override("separation", gap)
	for b in tab_buttons + [fell_button, field_button, plant_button, heal_button, menu_button, save_button, load_button, settings_button, villagers_button, priorities_button]:
		b.custom_minimum_size = Vector2(0.0, touch)
	for b in speed_buttons:
		b.custom_minimum_size = Vector2(touch if land else touch * 0.85, touch)
	var fs := touch * 1.3
	fab.custom_minimum_size = Vector2(fs, fs)

	var m := _safe()
	var edge := 8.0 * _dp
	var l: float = m["left"] + edge
	var r: float = m["right"] + edge
	var tp: float = m["top"] + edge
	var bt: float = m["bottom"] + edge

	_set_anchors(_top_bar, 0.0, 0.0, 1.0, 0.0)
	_top_bar.offset_left = l
	_top_bar.offset_right = -r
	_top_bar.offset_top = tp
	_top_bar.offset_bottom = tp
	_top_bar.grow_vertical = Control.GROW_DIRECTION_END

	# Ландшафт: док слева-снизу, не шире ~половины экрана.
	_set_anchors(_dock, 0.0, 1.0, 0.0, 1.0)
	_dock.offset_left = l
	_dock.offset_right = l + minf(vp.x - l - r, 190.0 * _dp * 4.0)
	_dock.offset_bottom = -bt
	_dock.offset_top = -bt
	_dock.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# Меню-попап: справа под верхней панелью.
	_set_anchors(_menu_popup, 1.0, 0.0, 1.0, 0.0)
	_menu_popup.offset_right = -r
	_menu_popup.offset_left = -r - 200.0 * _dp
	_menu_popup.offset_top = tp + touch + 3.0 * edge
	_menu_popup.offset_bottom = _menu_popup.offset_top
	_menu_popup.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# Панель действий: под верхней панелью на всю ширину (оба режима).
	_set_anchors(_bar, 0.0, 0.0, 1.0, 0.0)
	_bar.offset_left = l
	_bar.offset_right = -r
	_bar.offset_top = tp + touch + 2.0 * edge
	_bar.offset_bottom = _bar.offset_top
	_bar.grow_vertical = Control.GROW_DIRECTION_END
	for b in _bar_buttons:
		b.custom_minimum_size = Vector2(0.0, touch)
	for b in _tab_items.get_children():
		(b as Control).custom_minimum_size = Vector2(0.0, touch)

	# Портрет: лист снизу, FAB справа внизу (достаёт большой палец).
	_set_anchors(_sheet, 0.0, 1.0, 1.0, 1.0)
	_sheet.offset_left = l
	_sheet.offset_right = -r
	_sheet.offset_bottom = -bt - fs - gap  # лист над плавающей кнопкой
	_sheet.offset_top = _sheet.offset_bottom
	_sheet.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_set_anchors(fab, 1.0, 1.0, 1.0, 1.0)
	fab.offset_right = -r
	fab.offset_left = -r - fs
	fab.offset_bottom = -bt
	fab.offset_top = fab.offset_bottom - fs

	# Панели жителей: под верхней панелью, над плавающей кнопкой.
	villagers_ui.apply_layout(_dp, l, tp + touch + 2.0 * edge, r, bt + fs + gap)


## Размер вьюпорта; вне дерева (тесты) — типичный портретный экран.
func _vp_size() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1080, 2400)


func _safe() -> Dictionary:
	if not OS.has_feature("mobile") or not is_inside_tree():
		return safe_margins(Rect2i(), Vector2i.ZERO, Vector2.ZERO)
	return safe_margins(
		DisplayServer.get_display_safe_area(),
		DisplayServer.window_get_size(),
		_vp_size())


# ---------- обновление ----------

func _refresh_clock(force: bool) -> void:
	if sim == null:
		return
	var d := format_date(sim.clock.get_day())
	var t := format_time(sim.clock.get_time_of_day())
	if seasons != null:
		d = format_season_date(seasons.season_name(), seasons.day_of_season())
		t += "  " + format_temp(seasons.outdoor_temp())
	if force or d + t != _last_text:
		_last_text = d + t
		date_label.text = d
		time_label.text = t
	_refresh_speed_buttons()


func _refresh_speed_buttons() -> void:
	if sim == null:
		return
	var s := sim.clock.get_speed()
	for i in speed_buttons.size():
		speed_buttons[i].set_pressed_no_signal(GameClock.SPEEDS[i] == s)
