extends RefCounted
## Test rig for step 17: FoodEnv + RestorationSystem (season forced through FoodSystem).

const FoodEnv = preload("res://tests/food/food_env.gd")

var f: FoodEnv
var rs: RestorationSystem
var e: Variant
var world: WorldMap


func _init(season: StringName = SeasonDefs.SPRING) -> void:
	f = FoodEnv.new(season)
	e = f.e
	world = f.e.world
	rs = RestorationSystem.new()
	rs.bind(e.eco, world, e.con, f.food, f.climate)
	e.sim.register_system(rs)
	rs.attach(e.sim)
	rs.natural_spread = false  # tests opt in


func day() -> float:
	return e.sim.clock.day_seconds()


## Runs n game days in coarse steps.
func days(n: float, step_days: float = 0.5) -> void:
	var t := 0.0
	while t < n:
		var d := minf(step_days, n - t)
		rs.tick(e.sim, d * day())
		f.food.tick(e.sim, d * day())
		t += d


## Ground cell near the hub that can be planted (free, non-poison).
func free_cells(n: int) -> Array[Vector2i]:
	var hub: Vector3 = e.vs.hub_position()
	for k in 80:
		var a := float(k) * 2.4
		var p := hub + Vector3(cos(a), 0.0, sin(a)) * (8.0 + k * 1.2)
		var cells := rs.plant_cells_in_brush(p, 4.0, true)
		cells = cells.filter(func(c: Vector2i) -> bool: return world.cell_type(c.x, c.y) == WorldMap.Terrain.GROUND)
		if cells.size() >= n:
			return cells.slice(0, n)
	return []


func idx(c: Vector2i) -> int:
	return c.y * world.size + c.x


## Plants a sapling and grows it into trees: returns the cell.
func grow_tree(c: Vector2i) -> void:
	rs.designate_plant([c])
	rs.finish(&"plant", idx(c))
	var seasons_s := SeasonDefs.DEFAULT_MINUTES[SeasonDefs.SUMMER] * 60.0
	for i in 8:
		rs.tick(e.sim, seasons_s * RestorationDefs.SAPLING_GROW_SEASONS / 6.0)


func poison_cell() -> Vector2i:
	for cz in world.size:
		for cx in world.size:
			if world.cell_type(cx, cz) == WorldMap.Terrain.POISON:
				return Vector2i(cx, cz)
	return Vector2i(-1, -1)
