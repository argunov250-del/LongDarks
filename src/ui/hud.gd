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
const TOOLS_TAB := 4            # вкладка «Земля»: кисти (вырубка, поле, посадка, лечение, дорога)
const TOOLS_TITLE := "Земля"
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
var tools_tab: Button          # вкладка «Земля» с кистями
var tool_buttons: Array[Button] = []
var _tabs_scroll: ScrollContainer   # запасной вариант: ряд вкладок прокручивается по горизонтали
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
var _tab_list: ScrollContainer     # список зданий вкладки: прокручивается, если не помещается
var _list_avail_w := 400.0         # ширина под список (для расчёта переноса строк)
var _list_max_h := 400.0           # высота под список (экран минус всё остальное)
var drive_settings: DriveSettings  # настройки ручного вождения (общие с ManualDriveController)
var _settings_panel: PanelContainer
var _settings_title: Label
var _scheme_buttons: Dictionary = {}
var _calib_button: Button
var _settings_close: Button
var _driving := false
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
	tools_tab.set_pressed_no_signal(_selected_tab == TOOLS_TAB)
	_tab_panel.visible = _selected_tab >= 0
	_menu_box.visible = not (mode == LayoutMode.Mode.PORTRAIT and _selected_tab >= 0)  # портрет: лист не вмещает меню и список
	if _selected_tab >= 0:
		_tab_title.text = TOOLS_TITLE if _selected_tab == TOOLS_TAB else TABS[_selected_tab]
		_fill_tab_items(_selected_tab)


func _fill_tab_items(tab: int) -> void:
	for c in _tab_items.get_children():
		_tab_items.remove_child(c)
		if not tool_buttons.has(c):
			c.queue_free()
	if tab == TOOLS_TAB:
		for tb in tool_buttons:
			_tab_items.add_child(tb)
		fit_tab_list()
		return
	for id in BuildingDefs.ids_in_tab(tab):
		var b := _mk_button(BuildingDefs.display_name(id))
		b.custom_minimum_size = Vector2(0.0, MIN_TOUCH_DP * _dp)
		b.pressed.connect(_on_build_item.bind(id))
		_tab_items.add_child(b)
	fit_tab_list()


## A brush tool was chosen: collapse the «Земля» tab.
func _on_tool_pressed() -> void:
	if _selected_tab == TOOLS_TAB:
		select_tab(TOOLS_TAB)


func _on_build_item(id: StringName) -> void:
	select_tab(_selected_tab)  # свернуть вкладку
	build_selected.emit(id)


## Панель действий: заголовок + кнопки [id, текст, включена]. Если набор id не
## изменился, обновляются только тексты/состояния (нажатие не прерывается).
func show_actions(title: String, actions: Array, tint: Color = Color(0, 0, 0, 0)) -> void:
	_bar_label.text = title
	if tint.a > 0.0:
		_bar_label.add_theme_color_override("font_color", tint)
	else:
		_bar_label.remove_theme_color_override("font_color")
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


## Настройки: панель «Управление машиной» (Джойстик / Наклон / Кнопки), хранится в user://settings.cfg.
func do_settings() -> void:
	_ensure_drive_settings()
	_menu_popup.visible = false
	_sheet.visible = false
	_settings_panel.visible = not _settings_panel.visible
	_refresh_settings()


func _ensure_drive_settings() -> void:
	if drive_settings == null:
		drive_settings = DriveSettings.new()
		drive_settings.load()


func _on_scheme_pressed(scheme: StringName) -> void:
	_ensure_drive_settings()
	if drive_settings.set_scheme(scheme):
		drive_settings.save()
	_refresh_settings()


func _on_calibrate_pressed() -> void:
	_ensure_drive_settings()
	drive_settings.tilt_neutral = Vector3.ZERO  # следующая посадка: текущая поза телефона станет нейтральной
	drive_settings.save()
	_set_status("Наклон: поза обнулится при посадке")


func _refresh_settings() -> void:
	_ensure_drive_settings()
	for k in _scheme_buttons:
		(_scheme_buttons[k] as Button).set_pressed_no_signal(k == drive_settings.scheme)


## Режим вождения: скрывает вкладки строительства, меню и панель действий (минимум элементов на экране).
func set_driving(on: bool) -> void:
	_driving = on
	if on:
		hide_actions()
		_settings_panel.visible = false
		if _selected_tab >= 0:
			select_tab(_selected_tab)
	_apply_mode(mode)


func is_driving() -> bool:
	return _driving


## Масштаб dp и отступы безопасной зоны — для экрана вождения.
func ui_scale() -> float:
	return _dp


func safe_insets() -> Dictionary:
	return _safe()


func tab_list() -> ScrollContainer:
	return _tab_list


## Сколько строк займёт ряд кнопок шириной widths при переносе в avail_w (чистая функция, тестируется).
static func flow_rows(widths: Array, avail_w: float, hgap: float) -> int:
	var rows := 1
	var x := 0.0
	for w in widths:
		var ww: float = minf(w, avail_w)
		if x > 0.0 and x + hgap + ww > avail_w:
			rows += 1
			x = 0.0
		x += (hgap if x > 0.0 else 0.0) + ww
	return rows if not widths.is_empty() else 0


## Высота списка вкладки: по содержимому, но не больше доступной; дальше — прокрутка.
func fit_tab_list() -> void:
	if _tab_list == null:
		return
	var widths: Array = []
	for c in _tab_items.get_children():
		widths.append((c as Control).get_combined_minimum_size().x)
	var hg := _tab_items.get_theme_constant("h_separation")
	var vg := _tab_items.get_theme_constant("v_separation")
	var rows := flow_rows(widths, _list_avail_w, hg)
	var row_h := MIN_TOUCH_DP * _dp
	var need := float(rows) * row_h + float(maxi(rows - 1, 0)) * vg
	_tab_list.custom_minimum_size.y = minf(need, maxf(_list_max_h, row_h * 2.0))


## Подключает панели жителей к системе (main/тесты).
func bind_seasons(system: SeasonSystem) -> void:
	seasons = system
	_refresh_clock(true)


## Короткое сообщение о начале погодного события (прогноза в интерфейсе нет).
func bind_weather(sim_in: Simulation) -> void:
	sim_in.bus.subscribe(WeatherSystem.TOPIC_STARTED, func(p: Dictionary) -> void:
		villagers_ui.show_toast(WeatherDefs.toast_text(p.get("id", &""))))


## Notification «Бурун-5 сломался» (step 19).
func bind_vehicles(sim_in: Simulation) -> void:
	sim_in.bus.subscribe(VehicleSystem.TOPIC_BROKEN, func(p: Dictionary) -> void:
		villagers_ui.show_toast(String(p.get("text", ""))))


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
	field_button = _mk_button("Поле")
	field_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_button.pressed.connect(func(): field_requested.emit())
	plant_button = _mk_button("Посадить лес")
	plant_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plant_button.pressed.connect(func(): plant_requested.emit())
	heal_button = _mk_button("Лечить землю")
	heal_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heal_button.pressed.connect(func(): heal_requested.emit())
	road_button = _mk_button("Дорога")
	road_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	road_button.pressed.connect(func(): road_requested.emit())
	tools_tab = _mk_button(TOOLS_TITLE, true)
	tools_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools_tab.pressed.connect(select_tab.bind(TOOLS_TAB))
	_tabs_row.add_child(tools_tab)
	tool_buttons = [fell_button, field_button, plant_button, heal_button, road_button]
	_tabs_scroll = ScrollContainer.new()
	_tabs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_tabs_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tabs_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs_scroll.add_child(_tabs_row)
	for tb in tool_buttons:
		tb.pressed.connect(_on_tool_pressed)
	_tab_panel = PanelContainer.new()
	_tab_title = Label.new()
	_tab_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tab_box := _mk_box(VBoxContainer.new())
	_tab_panel.add_child(tab_box)
	tab_box.add_child(_tab_title)
	_tab_items = HFlowContainer.new()
	_tab_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_list = ScrollContainer.new()
	_tab_list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tab_list.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_tab_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_list.add_child(_tab_items)
	tab_box.add_child(_tab_list)
	for tb in tool_buttons:
		_tab_items.add_child(tb)
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

	_settings_panel = PanelContainer.new()
	_settings_panel.visible = false
	add_child(_settings_panel)
	var sbox := _mk_box(VBoxContainer.new())
	_settings_panel.add_child(sbox)
	_settings_title = Label.new()
	_settings_title.text = "Управление машиной"
	_settings_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sbox.add_child(_settings_title)
	var sflow := HFlowContainer.new()
	sflow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sbox.add_child(sflow)
	for sc in ManualDriveDefs.SCHEMES:
		var sb := _mk_button(ManualDriveDefs.scheme_name(sc), true)
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.pressed.connect(_on_scheme_pressed.bind(sc))
		_scheme_buttons[sc] = sb
		sflow.add_child(sb)
	_calib_button = _mk_button("Сбросить калибровку наклона")
	_calib_button.pressed.connect(_on_calibrate_pressed)
	sbox.add_child(_calib_button)
	_settings_close = _mk_button("Закрыть")
	_settings_close.pressed.connect(func(): _settings_panel.visible = false)
	sbox.add_child(_settings_close)

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
	_menu_box.visible = not (mode == LayoutMode.Mode.PORTRAIT and _selected_tab >= 0)
	var land := mode == LayoutMode.Mode.LANDSCAPE
	menu_button.visible = land and not _driving
	fab.visible = not land and not _driving
	_dock.visible = land and not _driving
	_menu_popup.visible = false
	_sheet.visible = false
	if land:
		_reparent_to(_tab_panel, _dock)
		_reparent_to(_tabs_scroll, _dock)
		_reparent_to(_menu_box, _menu_popup)
	else:
		_reparent_to(_tabs_scroll, _sheet_box)
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
	for b in tab_buttons + tool_buttons + [tools_tab, menu_button, save_button, load_button, settings_button, villagers_button, priorities_button]:
		b.custom_minimum_size = Vector2(0.0, touch)
	for b in speed_buttons:
		b.custom_minimum_size = Vector2(touch if land else touch * 0.85, touch)
	_tabs_scroll.custom_minimum_size.y = touch + 2.0 * _dp
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

	# Панель настроек: по центру, не шире экрана.
	_set_anchors(_settings_panel, 0.5, 0.5, 0.5, 0.5)
	_settings_panel.custom_minimum_size.x = minf(vp.x - l - r, 420.0 * _dp)
	_settings_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_settings_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	for b in _scheme_buttons.values() + [_calib_button, _settings_close]:
		(b as Control).custom_minimum_size = Vector2(0.0, touch)

	# Список вкладки: ширина и высота, оставшиеся под него (дальше — прокрутка).
	var fixed := touch + 2.0 * _dp + _tab_title.get_combined_minimum_size().y + 4.0 * gap + 12.0 * _dp
	if land:
		_list_avail_w = (_dock.offset_right - _dock.offset_left) - 16.0 * _dp
		_list_max_h = vp.y - (tp + touch + 2.0 * edge) - bt - fixed
	else:
		_list_avail_w = vp.x - l - r - 16.0 * _dp
		_list_max_h = vp.y - (tp + touch + 2.0 * edge) - (bt + fs + gap) - fixed - 2.0 * gap
	fit_tab_list()


## Размер вьюпорта; вне дерева (тесты) — типичный портретный экран.
## Test hook: non-zero forces the layout viewport size.
var viewport_override := Vector2.ZERO


func _vp_size() -> Vector2:
	if viewport_override != Vector2.ZERO:
		return viewport_override
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
