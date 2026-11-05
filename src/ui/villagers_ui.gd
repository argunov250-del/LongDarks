class_name VillagersUi
extends Control
## Панели «Жители» и «Приоритеты» и уведомление о новичке. Принадлежит HUD
## (Hud.villagers_ui); один и тот же набор узлов в портрете и ландшафте —
## HUD лишь передаёт масштаб и отступы через apply_layout.

signal villager_pressed(id: int)  # кнопка «Карточка» в списке

const MODE_NONE := &""
const MODE_VILLAGERS := &"villagers"
const MODE_PRIORITIES := &"priorities"
const REFRESH := 0.5
const TOAST_SECONDS := 6.0
const GOOD_COLOR := "#6fcf6f"
const BAD_COLOR := "#ef6f6f"

var vs: VillagerSystem
var mode: StringName = MODE_NONE
var toast_panel: PanelContainer
var toast_label: Label
var panel: PanelContainer
var title_label: Label
var list_box: VBoxContainer
var close_button: Button

var _scroll: ScrollContainer
var _dp := 2.6
var _rows: Dictionary = {}        # id -> {"info": RichTextLabel, "card": Button}
var _prio_rows: Dictionary = {}   # cat -> {"value": Label, "minus": Button, "plus": Button}
var _count_label: Label
var _acc := 0.0
var _toast_left := 0.0


func _init() -> void:  # узлы строятся сразу: HUD в тестах бывает вне дерева
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.visible = false
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	title_label = Label.new()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	close_button = Button.new()
	close_button.text = "Закрыть"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(hide_panel)
	head.add_child(close_button)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(list_box)
	toast_panel = PanelContainer.new()
	toast_panel.visible = false
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label = Label.new()
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_panel.add_child(toast_label)
	add_child(toast_panel)


func bind(system: VillagerSystem, sim: Simulation) -> void:
	vs = system
	if sim != null:
		sim.bus.subscribe(VillagerSystem.TOPIC_ARRIVED, _on_arrived)


func _on_arrived(p: Dictionary) -> void:
	show_toast("Прибыл новичок: %s, %s" % [p.get("name", "?"), VillagerDefs.profession_name(p.get("profession", &""))])


func show_toast(text: String) -> void:
	toast_label.text = text
	toast_panel.visible = true
	_toast_left = TOAST_SECONDS


func _process(dt: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= dt
		if _toast_left <= 0.0:
			toast_panel.visible = false
	if mode == MODE_NONE:
		return
	_acc += dt
	if _acc >= REFRESH:
		_acc = 0.0
		refresh()


func show_panel(new_mode: StringName) -> void:
	mode = new_mode
	panel.visible = mode != MODE_NONE
	_clear_list()
	if mode == MODE_VILLAGERS:
		title_label.text = "Жители"
	elif mode == MODE_PRIORITIES:
		title_label.text = "Приоритеты"
	refresh()


func hide_panel() -> void:
	mode = MODE_NONE
	panel.visible = false
	_clear_list()


func is_open() -> bool:
	return panel.visible


func _clear_list() -> void:
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	_rows.clear()
	_prio_rows.clear()
	_count_label = null


func refresh() -> void:
	if vs == null:
		return
	if mode == MODE_VILLAGERS:
		_refresh_villagers()
	elif mode == MODE_PRIORITIES:
		_refresh_priorities()


# ---------- жители ----------

static func traits_bbcode(v: Villager) -> String:
	var parts: Array[String] = []
	for t in v.traits:
		parts.append("[color=%s]%s[/color]" % [GOOD_COLOR if TraitDefs.is_good(t) else BAD_COLOR, TraitDefs.display_name(t)])
	return ", ".join(parts)


func _refresh_villagers() -> void:
	var ids: Array = vs.villagers.keys()
	if ids != _rows.keys():
		_clear_list()
		_count_label = Label.new()
		list_box.add_child(_count_label)
		for id in ids:
			_add_villager_row(vs.villagers[id])
	_count_label.text = "Жителей: %d из %d" % [vs.population(), vs.max_population]
	for id in _rows:
		var v: Villager = vs.villagers[id]
		var info: RichTextLabel = _rows[id]["info"]
		var txt := "[b]%s[/b]%s — %s\n%s\n%s" % [v.display_name, " (герой)" if v.is_hero else "", v.profession_name(), traits_bbcode(v), vs.task_text(v)]
		if info.text != txt:
			info.text = txt


func _add_villager_row(v: Villager) -> void:
	var row := HBoxContainer.new()
	list_box.add_child(row)
	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var card := Button.new()
	card.text = "Карточка"
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(0.0, 48.0 * _dp)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.pressed.connect(func(): villager_pressed.emit(v.id))
	row.add_child(card)
	_rows[v.id] = {"info": info, "card": card}
	list_box.add_child(HSeparator.new())


# ---------- приоритеты ----------

func _refresh_priorities() -> void:
	if _prio_rows.is_empty():
		var hint := Label.new()
		hint.text = "Жители сами выбирают дела. Чем выше приоритет, тем охотнее; «выкл» — никто не возьмётся."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list_box.add_child(hint)
		for cat in TaskDefs.CATEGORIES:
			var row := HBoxContainer.new()
			list_box.add_child(row)
			var name_l := Label.new()
			name_l.text = TaskDefs.NAMES[cat]
			name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_l)
			var minus := _mk_button("−")
			minus.pressed.connect(_change.bind(cat, -1))
			row.add_child(minus)
			var value := Label.new()
			value.custom_minimum_size = Vector2(90.0 * _dp * 0.6, 0.0)
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(value)
			var plus := _mk_button("+")
			plus.pressed.connect(_change.bind(cat, 1))
			row.add_child(plus)
			_prio_rows[cat] = {"value": value, "minus": minus, "plus": plus}
	for cat in _prio_rows:
		var p := vs.get_priority(cat)
		_prio_rows[cat]["value"].text = TaskDefs.PRIORITY_NAMES[p]
		_prio_rows[cat]["minus"].disabled = p <= TaskDefs.PRIORITY_MIN
		_prio_rows[cat]["plus"].disabled = p >= TaskDefs.PRIORITY_MAX


func _mk_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(48.0 * _dp, 48.0 * _dp)
	return b


func _change(cat: StringName, delta: int) -> void:
	if vs != null:
		vs.change_priority(cat, delta)
		_refresh_priorities()


# ---------- раскладка ----------

## top — смещение сверху (под верхней панелью), bottom — отступ снизу (над FAB).
func apply_layout(dp: float, left: float, top: float, right: float, bottom: float) -> void:
	_dp = dp
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = left
	panel.offset_right = -right
	panel.offset_top = top
	panel.offset_bottom = -bottom
	toast_panel.anchor_left = 0.5
	toast_panel.anchor_right = 0.5
	toast_panel.anchor_top = 1.0
	toast_panel.anchor_bottom = 1.0
	var w := minf(300.0 * dp, size.x - 2.0 * (left + right + 56.0 * dp)) if size.x > 0.0 else 300.0 * dp
	toast_panel.offset_left = -w * 0.5
	toast_panel.offset_right = w * 0.5
	toast_panel.offset_bottom = -(bottom + 8.0 * dp)  # над нижним краем, левее плавающей кнопки
	toast_panel.offset_top = toast_panel.offset_bottom
	toast_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	for r in _rows.values():
		(r["card"] as Button).custom_minimum_size = Vector2(0.0, 48.0 * dp)
	for r in _prio_rows.values():
		(r["minus"] as Button).custom_minimum_size = Vector2(48.0 * dp, 48.0 * dp)
		(r["plus"] as Button).custom_minimum_size = Vector2(48.0 * dp, 48.0 * dp)
