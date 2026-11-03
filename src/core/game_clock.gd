class_name GameClock
extends RefCounted
## Игровые часы. Детерминированны: время хранится в целых микросекундах.
## Скорость: 0 (пауза), 1, 2, 3.

const SPEEDS: Array[int] = [0, 1, 2, 3]
## Длина игровых суток в реальных секундах при скорости 1.
## HOOK (сезоны): позже заменить на day_length_for(day) / таблицу по сезонам.
const DEFAULT_DAY_LENGTH := 1440.0
const USEC := 1000000

var day_length_usec: int = roundi(DEFAULT_DAY_LENGTH * USEC)
var _speed: int = 1
var _total_usec: int = 0


func set_day_length(seconds: float) -> void:
	day_length_usec = maxi(1, roundi(seconds * USEC))


## Возвращает false и не меняет скорость, если значение недопустимо.
func set_speed(value: int) -> bool:
	if not SPEEDS.has(value):
		return false
	_speed = value
	return true


func get_speed() -> int:
	return _speed


func is_paused() -> bool:
	return _speed == 0


## Двигает часы на real_delta реальных секунд с учётом скорости.
func advance(real_delta: float) -> void:
	if real_delta <= 0.0:
		return
	_total_usec += roundi(real_delta * USEC) * _speed


func get_total_seconds() -> float:
	return float(_total_usec) / USEC


func get_total_usec() -> int:
	return _total_usec


## Номер дня, начиная с 1.
func get_day() -> int:
	return _total_usec / day_length_usec + 1


## Доля суток [0, 1).
func get_time_of_day() -> float:
	return float(_total_usec % day_length_usec) / day_length_usec


## Игровой час [0, 24).
func get_hour() -> float:
	return get_time_of_day() * 24.0


## Для загрузки/тестов: задать абсолютное время в секундах.
func set_total_seconds(seconds: float) -> void:
	_total_usec = maxi(0, roundi(seconds * USEC))
