class_name LayoutMode
extends Node
## Выбор раскладки интерфейса по размеру вьюпорта. Шлёт mode_changed при смене
## (ресайз окна / поворот экрана).

enum Mode { PORTRAIT, LANDSCAPE }

## Ландшафт, если ширина/высота >= порога. Почти квадратные экраны -> портрет
## (управление одной рукой надёжнее).
const LANDSCAPE_MIN_ASPECT := 1.15

signal mode_changed(mode: int)

var mode: int = Mode.PORTRAIT


## Чистая функция решения.
static func decide(size: Vector2) -> int:
	if size.x <= 0.0 or size.y <= 0.0:
		return Mode.PORTRAIT
	return Mode.LANDSCAPE if size.x / size.y >= LANDSCAPE_MIN_ASPECT else Mode.PORTRAIT


func _ready() -> void:
	get_viewport().size_changed.connect(refresh)
	refresh()


## Пересчитывает режим; возвращает true, если он изменился.
func refresh() -> bool:
	return update_size(get_viewport().get_visible_rect().size)


func update_size(size: Vector2) -> bool:
	var m := decide(size)
	if m == mode:
		return false
	mode = m
	mode_changed.emit(mode)
	return true
