extends "res://tests/test_case.gd"

const P := "__test_"


class RngSystem extends SimSystem:
	var value := 0
	var counter := 0

	func tick(sim: Simulation, _dt: float) -> void:
		value += sim.rng.randi_range(0, 1000)
		counter += 1

	func get_save_key() -> StringName:
		return &"test_rng"

	func save_state() -> Dictionary:
		return {"value": value, "counter": counter}

	func load_state(d: Dictionary) -> void:
		value = SaveManager.to_int(d.get("value"), value)
		counter = SaveManager.to_int(d.get("counter"), counter)


func _make(seed_value: int) -> Array:
	var sim := Simulation.new(seed_value)
	var sys := RngSystem.new()
	sim.register_system(sys)
	return [sim, sys]


func _snap(sim: Simulation, sys: RngSystem) -> Array:
	return [sim.tick_count, sim.clock.get_total_usec(), sim.rng.state, sys.value, sys.counter, sim.rng.randi()]


func _cleanup() -> void:
	for s in SaveManager.list_slots():
		if s.begins_with(P):
			SaveManager.delete_slot(s)


func test_round_trip_determinism() -> void:
	var a := _make(-8123456789012345678)
	var sim: Simulation = a[0]
	sim.clock.set_speed(3)
	sim.clock.set_day_length(600.0)
	for i in 37:
		sim.advance(0.137)
	assert_eq(SaveManager.save(sim, P + "rt"), OK)
	for i in 50:
		sim.advance(0.1)
	var expected := _snap(sim, a[1])

	var b := _make(1)
	assert_eq(SaveManager.load_slot(b[0], P + "rt"), OK)
	assert_eq(b[0].clock.get_speed(), 3)
	assert_eq(b[0].clock.day_length_usec, 600000000)
	for i in 50:
		b[0].advance(0.1)
	assert_eq(_snap(b[0], b[1]), expected)
	_cleanup()


func test_corrupt_file() -> void:
	DirAccess.make_dir_recursive_absolute(SaveManager.SAVE_DIR)
	var sim: Simulation = _make(1)[0]
	for content in ["{not json", "[1,2]", "{}", "{\"version\":99,\"sim\":{}}", "{\"version\":1}"]:
		var f := FileAccess.open(SaveManager.slot_path(P + "bad"), FileAccess.WRITE)
		f.store_string(content)
		f.close()
		assert_true(SaveManager.load_slot(sim, P + "bad") != OK, "should fail: " + content)
	assert_eq(sim.tick_count, 0)
	assert_eq(SaveManager.load_slot(sim, P + "nope"), ERR_FILE_NOT_FOUND)
	assert_eq(SaveManager.load_slot(sim, "../x"), ERR_INVALID_PARAMETER)
	_cleanup()


func test_unknown_and_missing_keys() -> void:
	var a := _make(5)
	a[1].value = 42
	var d: Dictionary = a[0].to_dict()
	d["systems"]["future_system"] = {"x": 1}
	d["totally_new_key"] = 1
	var b := _make(9)
	b[0].from_dict(d)
	assert_eq(b[1].value, 42)
	# Пустой словарь и отсутствие ключа системы — значения по умолчанию.
	var c := _make(9)
	c[1].value = 7
	c[0].from_dict({})
	assert_eq(c[1].value, 7)
	d["systems"].erase("test_rng")
	c[0].from_dict(d)
	assert_eq(c[1].value, 7)


func test_list_and_delete() -> void:
	var sim: Simulation = _make(1)[0]
	assert_eq(SaveManager.save(sim, P + "b"), OK)
	assert_eq(SaveManager.save(sim, P + "a"), OK)
	var slots := SaveManager.list_slots()
	assert_true(slots.has(P + "a") and slots.has(P + "b"))
	assert_true(slots.find(P + "a") < slots.find(P + "b"))
	assert_eq(SaveManager.delete_slot(P + "a"), OK)
	assert_false(SaveManager.list_slots().has(P + "a"))
	assert_eq(SaveManager.delete_slot(P + "a"), ERR_FILE_NOT_FOUND)
	_cleanup()
