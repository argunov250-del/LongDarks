class_name NeighboursUi
extends Control
## Панель «Соседи» (шаг 24, design/gdd/neighbours.md): отношения, торговля, помощь, дипломатия.
## Помещается в портрет и ландшафт: прокрутка, перенос строк, кнопки ≥ 48dp.

var system: NeighbourSystem
var panel: PanelContainer
var list_box: VBoxContainer
var _dp := 2.6
var _acc := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.visible = false
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Соседи"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "Закрыть"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: panel.visible = false)
	head.add_child(close)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list_box)


func bind(sys: NeighbourSystem) -> void:
	system = sys


func show_panel() -> void:
	panel.visible = true
	refresh()


func apply_layout(dp: float, left: float, top: float, right: float, bottom: float) -> void:
	_dp = dp
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = left
	panel.offset_right = -right
	panel.offset_top = top
	panel.offset_bottom = -bottom
	if panel.visible:
		refresh()


func _process(dt: float) -> void:
	_acc += dt
	if panel.visible and _acc > 1.0:
		_acc = 0.0
		refresh()


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_child(l)
	return l


func _button(text: String, fn: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(0.0, 48.0 * _dp)
	b.pressed.connect(func() -> void:
		fn.call()
		refresh())
	list_box.add_child(b)


func refresh() -> void:
	if system == null:
		return
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	for n in system.neighbours:
		var nid: StringName = n["id"]
		_label("%s — %s (%+.2f)" % [n["name"], system.relation_text(n), float(n["relation"])])
		_label(system.summary_text(n))
		_label("Охрана: сторожек %d, вышек %d, заборов %d, охранников %d" % [system.count_done(&"guard_post"), system.count_done(&"watchtower"), system.count_done(&"fence"), system.guards_on_duty()])
		if float(n["pact_left"]) > 0.0:
			_label("Пакт о ненападении: ещё %d дн." % int(ceil(float(n["pact_left"]))))
		if not (n["tribute"] as Dictionary).is_empty():
			_label("Дань: %d × %s" % [int(n["tribute"]["n"]), ResourceDefs.display_name(n["tribute"]["res"])])
		var rq: Dictionary = n["request"]
		if not rq.is_empty():
			_label("Просьба о помощи: %d × %s (ещё %d дн.)" % [int(rq["n"]), "еда" if rq["res"] == &"food" else ResourceDefs.display_name(rq["res"]), int(ceil(float(rq["left"])))])
			_button("Помочь", func() -> void: system.answer_request(nid, true))
			_button("Отказать", func() -> void: system.answer_request(nid, false))
		_label("Торговля (товар везёт караван):")
		var offers: Array = n["offers"]
		for i in offers.size():
			_button(system.offer_text(offers[i]), func() -> void: system.accept_offer(nid, i))
		_label("Дипломатия:")
		_button("Подарок: 10 досок", func() -> void: system.gift(nid, &"planks", 10))
		_button("Подарок: 15 еды", func() -> void: system.gift(nid, &"food", 15))
		_button("Пакт о ненападении (10 досок, 15 картофеля)", func() -> void: system.propose_pact(nid))
		if (n["tribute"] as Dictionary).is_empty():
			_button("Дань: 10 картофеля раз в 5 дней", func() -> void: system.set_tribute(nid, &"potato", 10, 5.0))
		else:
			_button("Отменить дань", func() -> void: system.cancel_tribute(nid))
		_button("Попросить еды (20)", func() -> void: system.ask_help(nid, &"food", 20))
