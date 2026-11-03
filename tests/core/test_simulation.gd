extends "res://tests/test_case.gd"


class CountSystem extends SimSystem:
	var ticks := 0
	var total_dt := 0.0

	func tick(_sim: Simulation, dt: float) -> void:
		ticks += 1
		total_dt += dt


func _run(frames: int, delta: float, seed_value := 1) -> Array:
	var sim := Simulation.new(seed_value)
	var sys := CountSystem.new()
	sim.register_system(sys)
	for i in frames:
		sim.advance(delta)
	return [sim, sys]


func test_frame_rate_independence() -> void:
	var a := _run(1, 1.0)
	var b := _run(100, 0.01)
	var c := _run(60, 1.0 / 60.0)
	assert_eq(a[0].tick_count, 10)
	assert_eq(b[0].tick_count, 10)
	assert_eq(a[1].ticks, b[1].ticks)
	assert_eq(a[0].clock.get_total_usec(), b[0].clock.get_total_usec())
	assert_eq(c[0].tick_count, 10)


func test_speed_and_pause() -> void:
	var sim := Simulation.new()
	var sys := CountSystem.new()
	sim.register_system(sys)
	sim.clock.set_speed(2)
	sim.advance(1.0)
	assert_almost_eq(sys.total_dt, 2.0)
	assert_almost_eq(sim.clock.get_total_seconds(), 2.0)
	sim.clock.set_speed(0)
	sim.advance(5.0)
	assert_eq(sys.ticks, 10)
	assert_almost_eq(sim.clock.get_total_seconds(), 2.0)


func test_unregister_system() -> void:
	var sim := Simulation.new()
	var sys := CountSystem.new()
	sim.register_system(sys)
	sim.advance(0.5)
	sim.unregister_system(sys)
	sim.advance(0.5)
	assert_eq(sys.ticks, 5)


func test_deterministic_rng() -> void:
	var s1 := Simulation.new(42)
	var s2 := Simulation.new(42)
	var s3 := Simulation.new(43)
	var r1: Array = []
	var r2: Array = []
	for i in 5:
		r1.append(s1.rng.randi())
		r2.append(s2.rng.randi())
	assert_eq(r1, r2)
	assert_true(s3.rng.randi() != r1[0])
	s1.seed_rng(42)
	assert_eq(s1.rng.randi(), r1[0])
