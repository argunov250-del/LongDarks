class_name MainMenu
extends Control
## Главное меню (шаг 25): Новая игра -> режим -> сложность -> старт; Продолжить; Загрузить; Настройки; Выход.
## Дизайн: design/gdd/modes-difficulty.md. Портрет и ландшафт: страницы лежат в ScrollContainer.

const MAIN_SCENE := "res://scenes/main.tscn"
const FONT := 30
const BTN_H := 84.0

var starter: Callable = Callable()   # (pending: Dictionary) -> void; по умолчанию смена сцены
var settings := GameSettings.new()
var drive_settings := DriveSettings.new()
var pages: Dictionary = {}           # id -> Control
var continue_button: Button
var load_button: Button
var new_button: Button
var quit_button: Button
var career_button: Button
var sandbox_button: Button
var start_button: Button
var preset_buttons: Dictionary = {}
var neighbour_buttons: Dictionary = {}
var winter_slider: HSlider
var weather_slider: HSlider
var slots: SlotsView
var scroll: ScrollContainer
var _winter_label: Label
var _weather_label: Label
var _syncing := false


func _ready() -> void:
	theme = load("res://scenes/ui/theme.tres")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.12, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var host := MarginContainer.new()
	host.custom_minimum_size.x = 640
	for s in ["left", "right", "top", "bottom"]:
		host.add_theme_constant_override("margin_" + s, 24)
	center.add_child(host)
	var hostbox := VBoxContainer.new()
	host.add_child(hostbox)
	drive_settings.load()
	_build_main(hostbox)
	_build_mode(hostbox)
	_build_difficulty(hostbox)
	_build_settings(hostbox)
	slots = SlotsView.new()
	slots.set_anchors_preset(Control.PRESET_FULL_RECT)
	slots.setup("load")
	slots.slot_chosen.connect(_on_slot_chosen)
	slots.closed.connect(show_page.bind(&"main"))
	pages[&"load"] = slots
	slots.visible = false
	add_child(slots)
	resized.connect(_fit)
	show_page(&"main")
	_fit()


func _fit() -> void:
	# узкий экран: колонка во всю ширину (с запасом), широкий: не шире 640
	var host: Control = scroll.get_child(0).get_child(0)
	host.custom_minimum_size.x = clampf(size.x, 200.0, 640.0)


func _btn(text: String, parent: Control, cb: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BTN_H)
	b.add_theme_font_size_override("font_size", FONT)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.focus_mode = Control.FOCUS_NONE
	if cb.is_valid():
		b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _lbl(text: String, parent: Control, size_px: int = FONT) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size_px)
	parent.add_child(l)
	return l


func _page(id: StringName, parent: Control, title: String) -> VBoxContainer:
	var p := VBoxContainer.new()
	p.add_theme_constant_override("separation", 14)
	_lbl(title, p, 44 if id == &"main" else 36)
	parent.add_child(p)
	pages[id] = p
	return p


func _build_main(parent: Control) -> void:
	var p := _page(&"main", parent, "LongDarks")
	new_button = _btn("Новая игра", p, show_page.bind(&"mode"))
	continue_button = _btn("Продолжить", p, _on_continue)
	load_button = _btn("Загрузить", p, _on_load_page)
	_btn("Настройки", p, show_page.bind(&"settings"))
	quit_button = _btn("Выход", p, _on_quit)


func _build_mode(parent: Control) -> void:
	var p := _page(&"mode", parent, "Режим игры")
	sandbox_button = _btn("Песочница", p, _on_pick_mode.bind(ModeDefs.SANDBOX))
	_lbl(String(ModeDefs.MODES[ModeDefs.SANDBOX]["desc"]), p, 22)
	career_button = _btn("Карьера", p, _on_pick_mode.bind(ModeDefs.CAREER))
	career_button.disabled = not ModeDefs.MODES[ModeDefs.CAREER]["enabled"]
	_lbl(String(ModeDefs.MODES[ModeDefs.CAREER]["desc"]), p, 22)
	_btn("Назад", p, show_page.bind(&"main"))


func _build_difficulty(parent: Control) -> void:
	var p := _page(&"difficulty", parent, "Сложность")
	var flow := HFlowContainer.new()
	p.add_child(flow)
	for id in ModeDefs.PRESET_ORDER:
		var b := _btn(ModeDefs.preset_name(id), flow, _on_preset.bind(id))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preset_buttons[id] = b
	_winter_label = _lbl("", p, 26)
	winter_slider = _slider(p, ModeDefs.WINTER_MULT_RANGE, _on_winter)
	_lbl("Поведение соседей", p, 26)
	var nflow := HFlowContainer.new()
	p.add_child(nflow)
	for id in ModeDefs.NEIGHBOUR_ORDER:
		var b := _btn(String(ModeDefs.NEIGHBOUR_MODES[id]["name"]), nflow, _on_neighbours.bind(id))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 22)
		neighbour_buttons[id] = b
	_weather_label = _lbl("", p, 26)
	weather_slider = _slider(p, ModeDefs.WEATHER_MULT_RANGE, _on_weather)
	start_button = _btn("Начать игру", p, _on_start)
	_btn("Назад", p, show_page.bind(&"mode"))


func _slider(parent: Control, rng: Vector2, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = rng.x
	s.max_value = rng.y
	s.step = ModeDefs.SLIDER_STEP
	s.custom_minimum_size = Vector2(0, 56)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(cb)
	parent.add_child(s)
	return s


func _build_settings(parent: Control) -> void:
	var p := _page(&"settings", parent, "Настройки")
	_lbl("Управление машиной", p, 26)
	var flow := HFlowContainer.new()
	p.add_child(flow)
	for sc in ManualDriveDefs.SCHEMES:
		var b := _btn(ManualDriveDefs.scheme_name(sc), flow, _on_scheme.bind(sc))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_pressed_no_signal(sc == drive_settings.scheme)
		b.name = "scheme_" + String(sc)
	_btn("Назад", p, show_page.bind(&"main"))


func show_page(id: StringName) -> void:
	for k in pages:
		(pages[k] as Control).visible = k == id
	scroll.visible = id != &"load"
	if id == &"main":
		var has_any := SaveManager.latest_slot() != ""
		continue_button.disabled = not has_any
		load_button.disabled = SaveManager.list_slots().is_empty()
	elif id == &"difficulty":
		_sync_difficulty()
	scroll.scroll_vertical = 0


func current_page() -> StringName:
	for k in pages:
		if (pages[k] as Control).visible:
			return k
	return &""


func _on_pick_mode(id: StringName) -> void:
	if settings.set_mode(id):
		show_page(&"difficulty")


func _on_preset(id: StringName) -> void:
	settings.set_preset(id)
	_sync_difficulty()


func _on_winter(v: float) -> void:
	if not _syncing:
		settings.set_winter_mult(v)
		_sync_difficulty()


func _on_weather(v: float) -> void:
	if not _syncing:
		settings.set_weather_mult(v)
		_sync_difficulty()


func _on_neighbours(id: StringName) -> void:
	settings.set_neighbour_mode(id)
	_sync_difficulty()


func _sync_difficulty() -> void:
	_syncing = true
	winter_slider.value = settings.winter_mult
	weather_slider.value = settings.weather_mult
	_syncing = false
	_winter_label.text = "Длина зимы: x%.2f (%d мин)" % [settings.winter_mult, roundi(settings.winter_minutes())]
	_weather_label.text = "Частота непогоды: x%.2f" % settings.weather_mult
	for id in preset_buttons:
		(preset_buttons[id] as Button).set_pressed_no_signal(id == settings.preset)
	for id in neighbour_buttons:
		(neighbour_buttons[id] as Button).set_pressed_no_signal(id == settings.neighbour_mode)


func _on_scheme(sc: StringName) -> void:
	drive_settings.set_scheme(sc)
	drive_settings.save()
	for c in pages[&"settings"].get_children():
		if c is HFlowContainer:
			for b in c.get_children():
				(b as Button).set_pressed_no_signal(b.name == "scheme_" + String(drive_settings.scheme))


func _on_start() -> void:
	_launch({"settings": settings.to_dict()})


func _on_continue() -> void:
	var slot := SaveManager.latest_slot()
	if slot != "":
		_launch({"load_slot": slot})


func _on_load_page() -> void:
	slots.refresh()
	show_page(&"load")


func _on_slot_chosen(slot: String) -> void:
	_launch({"load_slot": slot})


func _on_quit() -> void:
	get_tree().quit()


func _launch(pend: Dictionary) -> void:
	if starter.is_valid():
		starter.call(pend)
		return
	SimRunner.reset()
	SimRunner.pending = pend
	get_tree().change_scene_to_file(MAIN_SCENE)
