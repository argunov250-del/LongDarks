extends RefCounted
## Test rig for step 18: FoodEnv + VehicleSystem (no seasons: mud/snow/temperature are overrides).

const FoodEnv = preload("res://tests/food/food_env.gd")

var f: FoodEnv
var e: Variant
var vh: VehicleSystem


func _init(season: StringName = SeasonDefs.SPRING, resources: Dictionary = {}) -> void:
	f = FoodEnv.new(season)
	e = f.e
	for k in resources:
		e.storage.add(k, resources[k])
	vh = VehicleSystem.new()
	vh.bind(e.world, e.eco, e.con, e.prod, e.vs, f.food)
	e.sim.register_system(vh)
	vh.attach(e.sim)
	vh.mud_override = 0.0
	vh.snow_override = 0.0
	vh.temperature_override = 15.0


## Ground near the hub the vehicle grid can use.
func spot(k: int = 0) -> Vector3:
	var hub: Vector3 = e.vs.hub_position()
	return vh.pf.nearest_passable(hub + Vector3(10.0 + k * 7.0, 0.0, 6.0))


func spawn(type: StringName, cond: float = 1.0, fuel: float = 999.0, k: int = 0) -> Vehicle:
	return vh.add_vehicle(type, cond, fuel, spot(k))


func driver(skill: float = -1.0) -> Villager:
	var d: Villager = e.add_villager(&"driver")
	if skill >= 0.0:
		d.skills[VehicleDefs.DRIVE] = skill
	return d


## Second storage far from the first, filled so the first is the fuller one.
func second_storage() -> Storage:
	var s := Storage.new(500, spot(5))
	e.eco.add_storage(s)
	return s


func run(seconds: float) -> void:
	e.run(seconds)
