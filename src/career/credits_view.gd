class_name CreditsView
extends Control
## Финальные титры (шаг 26): прокрутка списка, в конце «Спасибо за игру» и кнопка возврата в меню.
## Дизайн: design/gdd/career.md. Записи берутся из data/career/chapters.json (credits).

signal finished

var scroll_y := 0.0
var speed := 60.0
var running := false
var column: VBoxContainer
var button: Button
var _dp := 2.6
var _data: Dictionary = {}


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	column.anchor_left = 0.0
	column.anchor_right = 1.0
	column.offset_left = 24
	column.offset_right = -24
	add_child(column)
	button = Button.new()
	button.text = "В главное меню"
	button.focus_mode = Control.FOCUS_NONE
	button.anchor_left = 0.5
	button.anchor_right = 0.5
	button.anchor_top = 1.0
	button.anchor_bottom = 1.0
	button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	button.offset_bottom = -24
	button.pressed.connect(func() -> void:
		running = false
		finished.emit())
	add_child(button)


func set_scale_dp(dp: float) -> void:
	_dp = dp
	button.add_theme_font_size_override("font_size", roundi(16.0 * dp))
	button.custom_minimum_size = Vector2(220.0 * dp, 48.0 * dp)
	if not _data.is_empty():
		_build()


## Запускает прокрутку с данными {title, thanks, speed, entries:[{role,name}]}.
func start(data: Dictionary) -> void:
	_data = data
	speed = float(data.get("speed", 60.0))
	_build()
	scroll_y = size.y if size.y > 0.0 else 1000.0
	column.position.y = scroll_y
	running = true


func _label(text: String, px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	column.add_child(l)
	return l


func _build() -> void:
	for c in column.get_children():
		column.remove_child(c)
		c.queue_free()
	_label(str(_data.get("title", "Титры")), roundi(26.0 * _dp), Color(1, 1, 1))
	for e in _data.get("entries", []):
		_label(str(e.get("role", "")), roundi(12.0 * _dp), Color(0.65, 0.7, 0.78))
		_label(str(e.get("name", "")), roundi(16.0 * _dp), Color(0.95, 0.95, 0.9))
	var sp := Control.new()
	sp.custom_minimum_size.y = 80.0 * _dp
	column.add_child(sp)
	_label(str(_data.get("thanks", "Спасибо за игру")), roundi(24.0 * _dp), Color(1.0, 0.9, 0.6))
	var pad := Control.new()
	pad.custom_minimum_size.y = 90.0 * _dp
	column.add_child(pad)


## Шаг прокрутки (px/с * dt); останавливается, когда «Спасибо» дошло до середины.
func advance(dt: float) -> void:
	if not running:
		return
	var stop_y := size.y * 0.5 - column.size.y + 90.0 * _dp + 40.0 * _dp
	scroll_y = maxf(scroll_y - speed * _dp * 0.4 * dt, minf(stop_y, 0.0))
	column.position.y = scroll_y


func _process(delta: float) -> void:
	if visible:
		advance(delta)
