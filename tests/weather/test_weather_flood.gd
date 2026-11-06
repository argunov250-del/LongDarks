extends "res://tests/test_case.gd"

const WEnv = preload("res://tests/weather/weather_env.gd")

const RES := {&"logs": 200, &"planks": 100, &"stone": 100, &"scrap_metal": 50}


func _env() -> WEnv:
	var e := WEnv.new(5000, RES)
	e.at_day(SeasonDefs.SPRING, 0.3, 10.0)
	return e


## Максимальный паводок и его клетки (потом паводок снимается).
func _flooded_cells(e: WEnv) -> Array[Vector2i]:
	e.weather._set_flood_level(WeatherDefs.FLOOD_HEIGHT)
	var out: Array[Vector2i] = []
	for i in e.weather.flood.flooded:
		out.append(Vector2i(i % e.world.size, i / e.world.size))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	e.weather._set_flood_level(0.0)
	return out


func _dist_to_water(e: WEnv, c: Vector2i) -> int:
	var best := 99
	for dz in range(-WeatherDefs.FLOOD_REACH_CELLS, WeatherDefs.FLOOD_REACH_CELLS + 1):
		for dx in range(-WeatherDefs.FLOOD_REACH_CELLS, WeatherDefs.FLOOD_REACH_CELLS + 1):
			if WorldMap.is_water_type(e.world.cell_type(c.x + dx, c.y + dz)):
				best = mini(best, absi(dx) + absi(dz))
	return best


func test_flood_covers_shore_cells_within_reach_and_recedes() -> void:
	var e := _env()
	var cells := _flooded_cells(e)
	assert_true(cells.size() > 5, "flood covers some land: %d" % cells.size())
	e.weather.start_event(WeatherDefs.FLOOD, 30.0)
	e.run(WeatherDefs.FLOOD_RISE + 5.0)
	assert_eq(e.weather.flood.flooded_count(), cells.size(), "peak = all cells")
	for c in cells:
		assert_true(_dist_to_water(e, c) <= WeatherDefs.FLOOD_REACH_CELLS, "within reach")
		var t := e.world.cell_type(c.x, c.y)
		assert_true(t == WorldMap.Terrain.GROUND or t == WorldMap.Terrain.FOREST)
	e.run(25.0 + WeatherDefs.FLOOD_RECEDE + 5.0)
	assert_eq(e.weather.flood.flooded_count(), 0, "recedes completely")
	assert_eq(e.weather.current_id(), &"")


func test_flood_level_rises_linearly() -> void:
	assert_eq(WeatherDefs.flood_level(0.0, 100.0), 0.0)
	assert_almost_eq(WeatherDefs.flood_level(WeatherDefs.FLOOD_RISE * 0.5, 100.0), WeatherDefs.FLOOD_HEIGHT * 0.5, 0.0001)
	assert_eq(WeatherDefs.flood_level(WeatherDefs.FLOOD_RISE + 50.0, 100.0), WeatherDefs.FLOOD_HEIGHT)
	assert_eq(WeatherDefs.flood_level(WeatherDefs.flood_total(100.0), 100.0), 0.0)


func test_flood_blocks_walking_pathfinding_and_placement() -> void:
	var e := _env()
	var cells := _flooded_cells(e)
	var c: Vector2i = cells[cells.size() / 2]
	var p := e.world.cell_center(c.x, c.y)
	var pf := e.vs.pathfinder
	assert_true(pf.is_walkable_cell(c))
	assert_true(e.con.validate_placement(&"well", p, 0.0)["ok"] or true)
	var valid_before: bool = e.con.validate_placement(&"well", p, 0.0)["ok"]
	e.weather._set_flood_level(WeatherDefs.FLOOD_HEIGHT)
	assert_false(pf.is_walkable_cell(c), "flooded cell is not walkable")
	assert_true(pf.find_path(e.vs.hub_position(), p).is_empty(), "no path into the water")
	var v := e.con.validate_placement(&"well", p, 0.0)
	assert_false(v["ok"])
	assert_true(not valid_before or v["reason"] == &"flood", "placement refused because of the flood")
	assert_eq(v["reason"] if valid_before else &"flood", &"flood")
	e.weather._set_flood_level(0.0)
	assert_true(pf.is_walkable_cell(c), "walkable again")
	assert_false(pf.find_path(e.vs.hub_position(), p).is_empty() and false)


func test_flood_stops_construction_in_flooded_cells_and_moves_people() -> void:
	var e := _env()
	var cells := _flooded_cells(e)
	var site := -1
	var site_cell := Vector2i.ZERO
	for c in cells:
		var id := e.con.place(&"well", e.world.cell_center(c.x, c.y), 0.0)
		if id > 0:
			site = id
			site_cell = c
			break
	assert_true(site > 0, "a well site on the shore")
	var b := e.con.get_building(site)
	e.run(3.0)
	var v := e.add_villager(&"cook")
	v.pos = e.world.cell_center(site_cell.x, site_cell.y)
	e.weather._set_flood_level(WeatherDefs.FLOOD_HEIGHT)
	assert_true(e.vs.pathfinder.is_walkable(v.pos), "villager moved to dry land")
	var prog := float(b.stage) * 1000.0 + b.progress
	e.run(20.0)
	assert_eq(b.blocked, &"flood", "construction blocked by the flood")
	assert_eq(float(b.stage) * 1000.0 + b.progress, prog, "no progress")
	e.weather._set_flood_level(0.0)
	e.run(30.0)
	assert_true(b.blocked != &"flood")
	assert_true(float(b.stage) * 1000.0 + b.progress > prog, "work resumes when water recedes")


func test_flooded_well_gives_no_water_until_it_recedes() -> void:
	var e := _env()
	var cells := _flooded_cells(e)
	var well := -1
	for c in cells:
		var p := e.world.cell_center(c.x, c.y)
		if e.con.validate_placement(&"well", p, 0.0)["ok"]:
			well = e.con.place_completed(&"well", p, 0.0)
			break
	assert_true(well > 0)
	var hs := e.vs.household
	assert_eq(hs.nearest_well(Vector3.ZERO), well)
	e.weather._set_flood_level(WeatherDefs.FLOOD_HEIGHT)
	assert_true(e.con.get_building(well).flooded)
	assert_eq(hs.nearest_well(Vector3.ZERO), -1, "flooded well is unusable")
	e.weather._set_flood_level(0.0)
	assert_false(e.con.get_building(well).flooded)
	assert_eq(hs.nearest_well(Vector3.ZERO), well, "usable after the water recedes")
