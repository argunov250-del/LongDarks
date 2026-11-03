extends "res://tests/test_case.gd"


func test_arithmetic() -> void:
	assert_eq(1 + 1, 2, "1+1")


func test_float() -> void:
	assert_almost_eq(0.1 + 0.2, 0.3)


func test_string() -> void:
	assert_true("LongDarks".begins_with("Long"))
