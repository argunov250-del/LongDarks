extends "res://tests/test_case.gd"


func test_speed_multiplier() -> void:
	var c := GameClock.new()
	c.advance(10.0)
	assert_almost_eq(c.get_total_seconds(), 10.0)
	c.set_speed(3)
	c.advance(10.0)
	assert_almost_eq(c.get_total_seconds(), 40.0)


func test_pause_and_invalid_speed() -> void:
	var c := GameClock.new()
	assert_true(c.set_speed(0))
	c.advance(5.0)
	assert_almost_eq(c.get_total_seconds(), 0.0)
	assert_false(c.set_speed(7))
	assert_eq(c.get_speed(), 0)


func test_day_rollover() -> void:
	var c := GameClock.new()
	c.set_day_length(100.0)
	assert_eq(c.get_day(), 1)
	c.advance(99.0)
	assert_eq(c.get_day(), 1)
	assert_almost_eq(c.get_time_of_day(), 0.99)
	c.advance(1.0)
	assert_eq(c.get_day(), 2)
	assert_almost_eq(c.get_time_of_day(), 0.0)
	c.set_speed(2)
	c.advance(75.0)
	assert_eq(c.get_day(), 3)
	assert_almost_eq(c.get_hour(), 12.0)
