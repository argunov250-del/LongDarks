extends RefCounted
## Общий стенд для тестов жителей: мир + экономика + стройка + производство + жители.

const SEED := 12345

var sim := Simulation.new(7)
var world: WorldMap
var eco: EconomySystem
var con: ConstructionSystem
var prod: ProductionSystem
var vs: VillagerSystem
var storage: Storage


func _init(cap: int = 5000, resources: Dictionary = {}, seed_value: int = 7) -> void:
	sim = Simulation.new(seed_value)
	world = WorldMap.new(SEED)
	eco = EconomySystem.new(world)
	con = ConstructionSystem.new(world, eco)
	prod = ProductionSystem.new(con, eco)
	vs = VillagerSystem.new(world, eco, con, prod)
	var f := world.factory_cell
	storage = Storage.new(cap, world.cell_center(f.x, f.y))
	eco.add_storage(storage)
	for k in resources:
		storage.add(k, resources[k])
	for s in [world, eco, con, prod, vs]:
		sim.register_system(s)
	con.attach(sim)
	prod.attach(sim)
	vs.attach(sim)
	vs.start_new_game()
	vs.arrival_min = 1.0e9  # без случайных гостей, пока тест не включит
	vs.arrival_max = 1.0e9
	vs.next_arrival_in = 1.0e9


func run(seconds: float) -> void:
	for i in int(seconds * 10.0):
		sim.advance(0.1)


func hero() -> Villager:
	return vs.get_hero()


## Свободная суша рядом с центром посёлка: ставит стройку и возвращает id.
func place_near_hub(type: StringName, dx: float = 14.0, dz: float = 0.0) -> int:
	var hub := vs.hub_position()
	for k in 40:
		var p := hub + Vector3(dx + k * 1.5, 0.0, dz + (k % 5) * 6.0)
		if not con.footprint_tree_cells(Vector2(p.x, p.z), BuildingDefs.footprint(type), 0.0).is_empty():
			continue  # без леса: тест не должен ждать вырубки
		var id := con.place(type, p, 0.0)
		if id > 0:
			return id
	return -1


## Готовое здание без стройки.
func add_done(type: StringName, dx: float = 14.0, dz: float = 0.0) -> int:
	var id := place_near_hub(type, dx, dz)
	var b := con.get_building(id)
	b.stage = BuildingDefs.Stage.DONE
	con._on_completed(b)
	return id


func add_villager(profession: StringName, traits: Array = []) -> Villager:
	var v := Villager.generate(sim.rng, {"profession": profession})
	v.traits.clear()
	for t in traits:
		v.traits.append(t)
	v.id = vs._next_id
	vs._next_id += 1
	v.pos = vs.hub_position()
	vs.villagers[v.id] = v
	return v
