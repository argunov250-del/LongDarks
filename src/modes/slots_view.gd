class_name SlotsView
extends PanelContainer
## Список слотов сохранения: режим "save" (имя + перезапись) и "load" (загрузка), удаление.
## Дизайн: design/gdd/modes-difficulty.md. Не знает о сцене/симуляции: только сигналы.

signal slot_chosen(slot: String)                         # режим load
signal save_requested(slot: String, display_name: String)  # режим save
signal closed

var mode := "load"
var name_edit: LineEdit
var save_button: Button
var close_button: Button
var rows: Dictionary = {}   # slot -> {"main": Button, "delete": Button}
var _list: VBoxContainer
var _title: Label
var _empty: Label


static func slot_for_name(display_name: String) -> String:
	var s := display_name.strip_edges()
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "%"]:
		s = s.replace(ch, "_")
	s = s.lstrip(".").substr(0, 40)
	return s


static func describe(info: Dictionary) -> String:
	if info.get("corrupt", false):
		return "%s\nповреждён" % info["slot"]
	var season := String(SeasonDefs.NAMES.get(StringName(info.get("season", "")), "?"))
	var when := Time.get_datetime_string_from_unix_time(SaveManager.to_int(info.get("saved_at", 0)), true).substr(0, 16)
	return "%s\n%s  |  %s, день %d  |  жителей %d" % [info.get("name", info["slot"]), when, season, SaveManager.to_int(info.get("day", 0)), SaveManager.to_int(info.get("population", 0))]


func setup(mode_in: String) -> void:
	mode = mode_in
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	_title = Label.new()
	_title.text = "Сохранить игру" if mode == "save" else "Загрузить игру"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	if mode == "save":
		var hb := HBoxContainer.new()
		box.add_child(hb)
		name_edit = LineEdit.new()
		name_edit.placeholder_text = "Название сохранения"
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.custom_minimum_size.y = 72
		hb.add_child(name_edit)
		save_button = Button.new()
		save_button.text = "Сохранить"
		save_button.custom_minimum_size = Vector2(0, 72)
		save_button.pressed.connect(_on_save)
		hb.add_child(save_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	_empty = Label.new()
	_empty.text = "Сохранений нет"
	box.add_child(_empty)
	close_button = Button.new()
	close_button.text = "Назад"
	close_button.custom_minimum_size = Vector2(0, 72)
	close_button.pressed.connect(func() -> void: closed.emit())
	box.add_child(close_button)
	refresh()


func refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	rows.clear()
	var infos := SaveManager.list_infos()
	_empty.visible = infos.is_empty()
	for info in infos:
		var slot: String = info["slot"]
		var row := VBoxContainer.new()
		var lbl := Label.new()
		lbl.text = describe(info)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(lbl)
		var hb := HBoxContainer.new()
		row.add_child(hb)
		var main := Button.new()
		main.text = "Перезаписать" if mode == "save" else "Загрузить"
		main.disabled = mode == "load" and info["corrupt"]
		main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		main.custom_minimum_size = Vector2(0, 72)
		main.pressed.connect(_on_row.bind(slot, String(info["name"])))
		hb.add_child(main)
		var del := Button.new()
		del.text = "Удалить"
		del.custom_minimum_size = Vector2(0, 72)
		del.pressed.connect(_on_delete.bind(slot))
		hb.add_child(del)
		row.add_child(HSeparator.new())
		_list.add_child(row)
		rows[slot] = {"main": main, "delete": del}


func _on_row(slot: String, display_name: String) -> void:
	if mode == "save":
		save_requested.emit(slot, display_name)
	else:
		slot_chosen.emit(slot)


func _on_save() -> void:
	var dn := name_edit.text.strip_edges()
	var slot := slot_for_name(dn)
	if slot == "" or not SaveManager.is_valid_slot_name(slot):
		name_edit.placeholder_text = "Введите название"
		return
	save_requested.emit(slot, dn)


func _on_delete(slot: String) -> void:
	SaveManager.delete_slot(slot)
	refresh()
