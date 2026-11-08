class_name CareerUi
extends Control
## Карьера (шаг 26): компактный трекер целей в HUD, панели вступления/итога главы, титры.
## Дизайн: design/gdd/career.md. Портрет и ландшафт: apply_layout(dp, left, top, right).
## Только отображение: логика — в CareerSystem; закрытие панелей — career.acknowledge().

var career: CareerSystem
var tracker: PanelContainer
var tracker_title: Label
var tracker_list: VBoxContainer
var panel_dim: ColorRect
var panel: PanelContainer
var panel_title: Label
var panel_text: Label
var panel_button: Button
var credits_view: CreditsView
var expanded := true
var on_exit: Callable = Callable()   # возврат в главное меню после титров

var _dp := 2.6
var _vp := Vector2(1080, 2400)
var _lines: Array[Label] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tracker = PanelContainer.new()
	tracker.name = "Tracker"
	tracker.mouse_filter = Control.MOUSE_FILTER_STOP
	tracker.gui_input.connect(_on_tracker_input)
	add_child(tracker)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracker.add_child(box)
	tracker_title = Label.new()
	tracker_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tracker_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tracker_title)
	tracker_list = VBoxContainer.new()
	tracker_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tracker_list)

	panel_dim = ColorRect.new()
	panel_dim.color = Color(0, 0, 0, 0.6)
	panel_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	panel_dim.visible = false
	add_child(panel_dim)
	panel = PanelContainer.new()
	panel.name = "ChapterPanel"
	panel.visible = false
	add_child(panel)
	var pbox := VBoxContainer.new()
	panel.add_child(pbox)
	panel_title = Label.new()
	panel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pbox.add_child(panel_title)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = 120
	pbox.add_child(sc)
	panel_text = Label.new()
	panel_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(panel_text)
	panel_button = Button.new()
	panel_button.text = "Продолжить"
	panel_button.focus_mode = Control.FOCUS_NONE
	panel_button.pressed.connect(_on_panel_button)
	pbox.add_child(panel_button)

	credits_view = CreditsView.new()
	credits_view.visible = false
	credits_view.finished.connect(_on_credits_finished)
	add_child(credits_view)
	apply_layout(_dp, 8.0, 100.0, 8.0, _vp)
	sync()


func bind(career_in: CareerSystem, sim: Simulation) -> void:
	career = career_in
	if sim != null:
		sim.bus.subscribe(CareerSystem.TOPIC_CHANGED, func(_p: Dictionary) -> void: sync())
	if is_inside_tree():
		sync()


## Раскладка: трекер справа сверху под верхней панелью (не шире ~45% экрана), панель по центру.
func apply_layout(dp: float, left: float, top: float, right: float, vp: Vector2) -> void:
	_dp = dp
	_vp = vp
	if tracker == null:
		return
	var w := minf(vp.x * 0.5, 260.0 * dp)
	tracker.anchor_left = 1.0
	tracker.anchor_right = 1.0
	tracker.anchor_top = 0.0
	tracker.anchor_bottom = 0.0
	tracker.offset_right = -right
	tracker.offset_left = -right - w
	tracker.offset_top = top
	tracker.offset_bottom = top
	tracker.grow_vertical = Control.GROW_DIRECTION_END
	var small := roundi(11.0 * dp)
	tracker_title.add_theme_font_size_override("font_size", roundi(12.0 * dp))
	for l in _lines:
		l.add_theme_font_size_override("font_size", small)
	panel_title.add_theme_font_size_override("font_size", roundi(20.0 * dp))
	panel_text.add_theme_font_size_override("font_size", roundi(15.0 * dp))
	panel_button.add_theme_font_size_override("font_size", roundi(16.0 * dp))
	panel_button.custom_minimum_size = Vector2(0, 48.0 * dp)
	var pw := minf(vp.x - 2.0 * left, 420.0 * dp)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -pw * 0.5
	panel.offset_right = pw * 0.5
	var ph := minf(vp.y * 0.6, 360.0 * dp)
	panel.offset_top = -ph * 0.5
	panel.offset_bottom = ph * 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	credits_view.set_scale_dp(dp)


func _on_tracker_input(ev: InputEvent) -> void:
	if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
		expanded = not expanded
		sync()


## Приводит видимость и тексты в соответствие с состоянием CareerSystem.
func sync() -> void:
	if career == null or tracker == null:
		return
	var ch := career.current_chapter()
	var running := career.active and not ch.is_empty() and career.phase != CareerSystem.DONE and career.phase != CareerSystem.CREDITS
	tracker.visible = running and career.phase == CareerSystem.ACTIVE
	if tracker.visible:
		_fill_tracker(ch)
	var show_panel := career.active and (career.phase == CareerSystem.INTRO or career.phase == CareerSystem.OUTRO) and not ch.is_empty()
	panel.visible = show_panel
	panel_dim.visible = show_panel
	if show_panel:
		var intro := career.phase == CareerSystem.INTRO
		panel_title.text = str(ch["title"])
		panel_text.text = str(ch["intro"] if intro else ch["outro"])
		panel_button.text = "Начать" if intro else "Дальше"
	var cr := career.active and career.phase == CareerSystem.CREDITS
	if cr and not credits_view.visible:
		credits_view.start(career.credits)
	credits_view.visible = cr


func _fill_tracker(ch: Dictionary) -> void:
	var objs: Array = ch["objectives"]
	var n_done := 0
	for o in objs:
		if career.is_done(o):
			n_done += 1
	tracker_title.text = "%s  %d/%d%s" % [ch["title"], n_done, objs.size(), "" if expanded else "  ▸"]
	for c in tracker_list.get_children():
		c.queue_free()
	_lines.clear()
	tracker_list.visible = expanded
	if not expanded:
		return
	for o in objs:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.text = objective_line(o)
		l.add_theme_font_size_override("font_size", roundi(11.0 * _dp))
		if career.is_done(o):
			l.modulate = Color(0.6, 0.9, 0.6)
		tracker_list.add_child(l)
		_lines.append(l)


## Строка цели: «[x] Текст (3/5)» — число показывается для счётных условий.
func objective_line(o: Dictionary) -> String:
	var mark := "[x] " if career.is_done(o) else "[ ] "
	var t := mark + str(o["text"])
	if o["type"] != CareerDefs.T_SURVIVE and o["type"] != CareerDefs.T_RELATION and not career.is_done(o):
		t += " (%d/%d)" % [roundi(minf(career.progress_of(o), CareerDefs.target(o))), roundi(CareerDefs.target(o))]
	return t


func _on_panel_button() -> void:
	if career != null:
		career.acknowledge()


func _on_credits_finished() -> void:
	if career != null:
		career.acknowledge()
	if on_exit.is_valid():
		on_exit.call()
