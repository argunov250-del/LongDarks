extends "res://tests/test_case.gd"
## Птицы шага 15: только весной после первых птиц, число растёт с потеплением.

const CEnv = preload("res://tests/climate/climate_env.gd")


func _birds(e) -> ClimateBirds:
	var map := WorldMap.new(20260401)
	var b := ClimateBirds.new()
	b.setup(e.climate, e.seasons, map, Deposits.new(map))
	return b


func test_birds_only_in_spring_after_first_birds() -> void:
	var e := CEnv.new()
	var b := _birds(e)
	e.seasons.start_at(SeasonDefs.SPRING, 0.5)
	assert_eq(b.target_count(), 0, "no birds before the milestone")
	e.climate.advance_season()
	e.climate.advance_season()
	e.climate.advance_season()
	assert_true(e.climate.first_birds_seen())
	e.seasons.start_at(SeasonDefs.SPRING, 0.5)
	assert_true(b.target_count() > 0, "birds in spring")
	e.seasons.start_at(SeasonDefs.WINTER, 0.5)
	assert_eq(b.target_count(), 0, "no birds in winter")
	e.seasons.start_at(SeasonDefs.SPRING, 0.5)
	for i in 30:
		b.step(0.1)
	assert_eq(b.multimesh.visible_instance_count, b.target_count())
	b.free()
