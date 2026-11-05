extends "res://tests/test_case.gd"


## Пара суши по разные стороны реки/озера в одной строке.
func _across_water(w: WorldMap) -> Array:
	for cz in range(8, w.size - 8):
		var left := -1
		var seen_water := false
		for cx in w.size:
			var water := WorldMap.is_water_type(w.cell_type(cx, cz))
			if water and left >= 0:
				seen_water = true
			elif not water:
				if seen_water and left >= 0 and cx - left > 3:
					return [Vector2i(left, cz), Vector2i(cx, cz)]
				left = cx
				seen_water = false
	return []


func test_path_avoids_water() -> void:
	var w := WorldMap.new(12345)
	var pf := Pathfinder.new(w)
	var pair := _across_water(w)
	assert_false(pair.is_empty(), "found land on both sides of water")
	var a: Vector2i = pair[0]
	var b: Vector2i = pair[1]
	var from := w.cell_center(a.x, a.y)
	var to := w.cell_center(b.x, b.y)
	var path := pf.find_path(from, to)
	assert_false(path.is_empty(), "reachable around the water")
	var prev := from
	var water_hits := 0
	var length := 0.0
	for p in path:
		assert_true(pf.is_walkable(p), "waypoint on land")
		# отрезок между точками тоже не мочит ноги
		for i in 21:
			var q := prev.lerp(p, i / 20.0)
			if w.is_water(q.x, q.z):
				water_hits += 1
		length += Vector2(p.x - prev.x, p.z - prev.z).length()
		prev = p
	assert_eq(water_hits, 0, "segments never cross water")
	assert_true(length > Vector2(from.x - to.x, from.z - to.z).length() + 1.0, "had to detour around water")
	assert_almost_eq(path[path.size() - 1].x, to.x, 0.001)


func test_path_cache_and_unreachable() -> void:
	var w := WorldMap.new(12345)
	var pf := Pathfinder.new(w)
	var pair := _across_water(w)
	var from := w.cell_center(pair[0].x, pair[0].y)
	var to := w.cell_center(pair[1].x, pair[1].y)
	var p1 := pf.find_path(from, to)
	var n := pf.cache_size()
	assert_eq(n, 1)
	var p2 := pf.find_path(from, to)
	assert_eq(pf.cache_size(), n, "second call served from cache")
	assert_eq(p1, p2)
	# Цель в воде недостижима
	var water := Vector3.ZERO
	for cz in w.size:
		for cx in w.size:
			if WorldMap.is_water_type(w.cell_type(cx, cz)):
				water = w.cell_center(cx, cz)
	assert_true(pf.find_path(from, water).is_empty())
	# Та же клетка — путь из одной точки
	assert_eq(pf.find_path(from, from).size(), 1)
	assert_true(pf.is_walkable(pf.nearest_walkable(water)))


func test_walker_moves_along_path_and_follows_terrain() -> void:
	var w := WorldMap.new(12345)
	var pf := Pathfinder.new(w)
	var f := w.factory_cell
	var a := w.cell_center(f.x, f.y)
	var b := w.cell_center(f.x + 6, f.y + 2)
	var wk := Walker.new()
	wk.pos = a
	wk.path = pf.find_path(a, b)
	var t := 0.0
	while not wk.path.is_empty() and t < 60.0:
		wk.advance_along(0.1, 2.4, w)
		assert_almost_eq(wk.pos.y, w.height_at(wk.pos.x, wk.pos.z), 0.001)
		t += 0.1
	assert_true(wk.path.is_empty())
	assert_true(Vector2(wk.pos.x - b.x, wk.pos.z - b.z).length() < 0.01)
	var dist := Vector2(a.x - b.x, a.z - b.z).length()
	assert_true(t >= dist / 2.4 - 0.2, "speed limited")
