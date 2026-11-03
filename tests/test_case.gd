class_name TestCase
extends RefCounted
## Базовый класс тестов: накапливает ошибки assert_*, не прерывая выполнение.

var errors: Array[String] = []


func _reset() -> void:
	errors.clear()


func assert_true(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		errors.append(msg)


func assert_false(cond: bool, msg: String = "expected false") -> void:
	if cond:
		errors.append(msg)


func assert_eq(actual, expected, msg: String = "") -> void:
	if actual != expected:
		errors.append("%s expected <%s>, got <%s>" % [msg, str(expected), str(actual)])


func assert_almost_eq(actual: float, expected: float, eps: float = 0.0001, msg: String = "") -> void:
	if absf(actual - expected) > eps:
		errors.append("%s expected ~<%s>, got <%s>" % [msg, str(expected), str(actual)])
