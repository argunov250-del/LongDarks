extends "res://tests/test_case.gd"


func _rig() -> CameraRig:
	var map := WorldMap.new(777)
	var rig := CameraRig.new()
	rig.setup(map, null)
	return rig


func test_pan_delta() -> void:
	assert_eq(CameraGestures.pan_delta([Vector2(10, 10)], [Vector2(15, 4)]), Vector2(5, -6))
	assert_eq(CameraGestures.pan_delta([Vector2(0, 0), Vector2(10, 0)], [Vector2(4, 2), Vector2(14, 2)]), Vector2(4, 2))
	assert_eq(CameraGestures.pan_delta([], []), Vector2.ZERO)


func test_rotate_angle() -> void:
	var a := [Vector2(0, 0), Vector2(100, 0)]
	var b := [Vector2(0, 0), Vector2(0, 100)]
	assert_almost_eq(CameraGestures.rotate_angle(a, b), PI * 0.5, 0.0001)
	assert_almost_eq(CameraGestures.rotate_angle(b, a), -PI * 0.5, 0.0001)
	assert_almost_eq(CameraGestures.rotate_angle(a, a), 0.0, 0.0001)
	# переход через ±π — короткий путь
	var c := [Vector2(0, 0), Vector2(-100, 1)]
	var d := [Vector2(0, 0), Vector2(-100, -1)]
	assert_true(absf(CameraGestures.rotate_angle(c, d)) < 0.1)


func test_zoom_factor() -> void:
	var a := [Vector2(0, 0), Vector2(100, 0)]
	var b := [Vector2(0, 0), Vector2(200, 0)]
	assert_almost_eq(CameraGestures.zoom_factor(a, b), 0.5, 0.0001)
	assert_almost_eq(CameraGestures.zoom_factor(b, a), 2.0, 0.0001)
	assert_almost_eq(CameraGestures.zoom_factor([Vector2.ZERO], a), 1.0, 0.0001)


func test_simultaneous_rotate_and_zoom() -> void:
	var a := [Vector2(0, 0), Vector2(100, 0)]
	var b := [Vector2(0, 0), Vector2(0, 50)]
	assert_almost_eq(CameraGestures.rotate_angle(a, b), PI * 0.5, 0.0001)
	assert_almost_eq(CameraGestures.zoom_factor(a, b), 2.0, 0.0001)


func test_pivot_clamped_to_bounds() -> void:
	var rig := _rig()
	var ws := rig.world_map.get_world_size()
	rig.set_state(Vector3(-500, 0, ws + 500), 0.0, 50.0)
	assert_almost_eq(rig.target_pivot.x, 0.0, 0.0001)
	assert_almost_eq(rig.target_pivot.z, ws, 0.0001)
	for _i in 50:
		rig.pan_pixels(Vector2(-5000, 5000))
	assert_true(rig.target_pivot.x >= 0.0 and rig.target_pivot.x <= ws)
	assert_true(rig.target_pivot.z >= 0.0 and rig.target_pivot.z <= ws)


func test_pan_ground_follows_finger() -> void:
	var rig := _rig()
	rig.set_state(Vector3(128, 0, 128), 0.0, 60.0, true)
	var before := rig.target_pivot
	rig.pan_pixels(Vector2(100, 0))   # палец вправо -> опорная точка влево (-x при yaw=0)
	assert_true(rig.target_pivot.x < before.x)
	rig.set_state(Vector3(128, 0, 128), 0.0, 60.0, true)
	rig.pan_pixels(Vector2(0, 100))   # палец вниз -> pivot от камеры (-z)
	assert_true(rig.target_pivot.z < 128.0)


func test_zoom_limits() -> void:
	var rig := _rig()
	for _i in 100:
		rig.zoom_by(0.5)
	assert_almost_eq(rig.target_distance, CameraRig.MIN_DISTANCE, 0.0001)
	for _i in 100:
		rig.zoom_by(2.0)
	assert_almost_eq(rig.target_distance, CameraRig.MAX_DISTANCE, 0.0001)


func test_pitch_from_zoom() -> void:
	var near := CameraRig.pitch_for_distance(CameraRig.MIN_DISTANCE)
	var far := CameraRig.pitch_for_distance(CameraRig.MAX_DISTANCE)
	assert_almost_eq(near, deg_to_rad(CameraRig.PITCH_NEAR_DEG), 0.0001)
	assert_almost_eq(far, deg_to_rad(CameraRig.PITCH_FAR_DEG), 0.0001)
	assert_true(near < far)
	assert_true(CameraRig.pitch_for_distance(50.0) > near and CameraRig.pitch_for_distance(50.0) < far)
	assert_almost_eq(CameraRig.pitch_for_distance(0.0), near, 0.0001)
	assert_almost_eq(CameraRig.pitch_for_distance(1e6), far, 0.0001)


func test_camera_above_terrain() -> void:
	var map := WorldMap.new(777)
	for d in [CameraRig.MIN_DISTANCE, 20.0, 100.0]:
		for i in 40:
			var p := Vector3(float(i) * 6.0, 0.0, float(i * 7 % 40) * 6.0)
			var pos := CameraRig.camera_position(p, float(i) * 0.4, d, map)
			assert_true(pos.y >= map.height_at(pos.x, pos.z) + CameraRig.TERRAIN_CLEARANCE - 0.0001)


func test_update_smooths_toward_target() -> void:
	var rig := _rig()
	rig.set_state(Vector3(100, 0, 100), 0.0, 60.0, true)
	rig.target_distance = 20.0
	rig.update(0.016)
	assert_true(rig._distance < 60.0 and rig._distance > 20.0)
	for _i in 300:
		rig.update(0.05)
	assert_almost_eq(rig._distance, 20.0, 0.01)


func test_save_load_roundtrip() -> void:
	var sim := Simulation.new(1)
	var rig := _rig()
	sim.register_system(rig.save_system)
	rig.set_state(Vector3(80, 0, 150), 1.25, 33.0)
	assert_eq(SaveManager.save(sim, "__test_cam"), OK)
	var sim2 := Simulation.new(2)
	var rig2 := _rig()
	sim2.register_system(rig2.save_system)
	assert_eq(SaveManager.load_slot(sim2, "__test_cam"), OK)
	assert_almost_eq(rig2.target_pivot.x, 80.0, 0.001)
	assert_almost_eq(rig2.target_pivot.z, 150.0, 0.001)
	assert_almost_eq(rig2.target_yaw, 1.25, 0.001)
	assert_almost_eq(rig2.target_distance, 33.0, 0.001)
	SaveManager.delete_slot("__test_cam")
