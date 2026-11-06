class_name VehicleSystem
extends SimSystem
## Vehicles, drivers, roads/footpaths/ruts. Design: design/gdd/vehicles.md.
## A driver is a villager with a task of kind &"drive" (category «Вождение»). VillagerSystem walks him
## to the vehicle, then calls drive_tick() every tick. Wear/breakdowns = step 19, fuel chains = step 20,
## manual driving = step 21 (hooks: Vehicle.breakdown_rate, refuel(), assigned_driver).

const TOPIC_CHANGED := &"vehicles_changed"
enum Go { ARRIVED, MOVING, BLOCKED }
enum Res { ONGOING, DONE, FAILED }

var world: WorldMap
var economy: EconomySystem
var construction: ConstructionSystem
var production: ProductionSystem
var villagers: VillagerSystem
var food: FoodSystem
var seasons: SeasonSystem
var weather: WeatherSystem
var vehicles: Dictionary = {}          # id -> Vehicle
var trails := TrailMap.new()
var pf: VehiclePathfinder
## Test/debug overrides (negative = use the real source; temperature: NAN = real).
var mud_override := -1.0
var snow_override := -1.0
var temperature_override := NAN
var _next_id := 1
var _sim: Simulation
var _foot_last: Dictionary = {}        # villager id -> last cell idx


func bind(world_in: WorldMap, economy_in: EconomySystem, construction_in: ConstructionSystem, production_in: ProductionSystem, villagers_in: VillagerSystem, food_in: FoodSystem = null, seasons_in: SeasonSystem = null, weather_in: WeatherSystem = null) -> void:
	world = world_in
	economy = economy_in
	construction = construction_in
	production = production_in
	villagers = villagers_in
	food = food_in
	seasons = seasons_in
	weather = weather_in
	pf = VehiclePathfinder.new(world, construction, villagers, trails)
	pf.deposits = economy.deposits
	if villagers != null:
		villagers.vehicles = self


func attach(sim: Simulation) -> void:
	_sim = sim
	sim.bus.subscribe(ConstructionSystem.TOPIC_RUIN_DISMANTLED, _on_ruin_dismantled)


func _emit() -> void:
	if _sim != null:
		_sim.bus.emit(TOPIC_CHANGED, {})


# ---------- registry ----------

func get_vehicle(id: int) -> Vehicle:
	return vehicles.get(id)


func vehicle_list() -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	for id in vehicles:
		out.append(vehicles[id])
	return out


## Adds a vehicle and registers it with the workshop (Repairable). Hook for trade (neighbours, later).
func add_vehicle(type: StringName, condition: float, fuel: float, pos: Vector3, origin: StringName = &"found") -> Vehicle:
	var v := Vehicle.new(_next_id, type, condition)
	_next_id += 1
	v.origin = origin
	v.pos = Vector3(pos.x, world.height_at(pos.x, pos.z), pos.z)
	v.fuel = clampf(fuel, 0.0, v.tank())
	vehicles[v.id] = v
	if production != null:
		production.register_repairable(v)
	_emit()
	return v


func remove_vehicle(id: int) -> void:
	if vehicles.has(id):
		if production != null:
			production.unregister_repairable(vehicles[id].repair_id)
		vehicles.erase(id)
		_emit()


## Start: abandoned vehicles near ruins nearest to the hub (spread apart).
func populate_start() -> void:
	var hub := villagers.hub_position()
	var ruins: Array = construction.ruins.values()
	ruins.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: float = Vector2(a["pos"].x - hub.x, a["pos"].z - hub.z).length()
		var db: float = Vector2(b["pos"].x - hub.x, b["pos"].z - hub.z).length()
		return da < db or (da == db and a["id"] < b["id"]))
	var used: Array[Vector3] = []
	var ri := 0
	for e in VehicleDefs.START_VEHICLES:
		var spot := Vector3.INF
		while ri < ruins.size():
			var rp: Vector3 = ruins[ri]["pos"]
			ri += 1
			var far := true
			for u in used:
				if Vector2(u.x - rp.x, u.z - rp.z).length() < VehicleDefs.START_RUIN_MIN_GAP:
					far = false
			if far:
				spot = pf.nearest_passable(rp + Vector3(VehicleDefs.START_OFFSET, 0.0, VehicleDefs.START_OFFSET * 0.5))
				used.append(rp)
				break
		if spot == Vector3.INF:
			spot = pf.nearest_passable(hub + Vector3(10.0 + used.size() * 6.0, 0.0, 10.0))
			used.append(spot)
		var v := add_vehicle(e["type"], e["condition"], e["fuel"], spot, &"found")
		v.facing = world.hash01(v.id, 3, 5) * TAU


func _on_ruin_dismantled(p: Dictionary) -> void:
	var rid := int(p.get("ruin", -1))
	if rid < 0 or not construction.ruins.has(rid) or vehicles.size() >= VehicleDefs.MAX_VEHICLES:
		return
	var c: Vector2i = construction.ruins[rid]["cell"]
	if world.hash01(c.x, c.y, 77) >= VehicleDefs.RUIN_FIND_CHANCE:
		return
	discover_at(construction.ruins[rid]["pos"], world.hash01(c.x, c.y, 78), world.hash01(c.x, c.y, 79))


## Hook: a vehicle is found at pos; r_type picks from RUIN_FINDS by weight, r_cond the condition.
func discover_at(pos: Vector3, r_type: float, r_cond: float) -> Vehicle:
	var total := 0
	for f in VehicleDefs.RUIN_FINDS:
		total += int(f["weight"])
	var pick := int(r_type * total) % total
	for f in VehicleDefs.RUIN_FINDS:
		pick -= int(f["weight"])
		if pick < 0:
			return add_vehicle(f["type"], lerpf(f["cmin"], f["cmax"], r_cond), f["fuel"], pf.nearest_passable(pos + Vector3(4.0, 0.0, 2.0)), &"ruins")
	return null


# ---------- drivability and driver rules ----------

func is_drivable(v: Vehicle) -> bool:
	return v != null and v.is_repaired() and v.fuel > 0.0


func status_text(v: Vehicle) -> String:
	if not v.is_repaired():
		return "Не на ходу: нужен ремонт"
	if v.fuel <= 0.0:
		return "Нет топлива"
	if v.stuck_left > 0.0:
		return "Застряла"
	if v.driver_id != 0:
		return "В работе"
	return "Исправна"


func any_driver_exists() -> bool:
	for vil: Villager in villagers.villagers.values():
		if vil.profession == &"driver":
			return true
	return false


## Driver rule: profession «водитель», the villager assigned to this vehicle by the player,
## or anyone when the settlement has no driver at all (then skill is low -> slower).
func can_drive(vil: Villager, v: Vehicle) -> bool:
	if v.assigned_driver != 0:
		return v.assigned_driver == vil.id
	return vil.profession == &"driver" or not any_driver_exists()


func assign_driver(vehicle_id: int, villager_id: int) -> void:
	var v := get_vehicle(vehicle_id)
	if v != null:
		v.assigned_driver = villager_id
		_emit()


func driver_speed_mult(vil: Villager) -> float:
	return lerpf(VehicleDefs.DRIVER_SPEED_MIN, VehicleDefs.DRIVER_SPEED_MAX, clampf(vil.skill(VehicleDefs.DRIVE), 0.0, 1.0)) if vil != null else VehicleDefs.DRIVER_SPEED_MIN


func temperature() -> float:
	if not is_nan(temperature_override):
		return temperature_override
	return seasons.outdoor_temp() if seasons != null else VehicleDefs.DEFAULT_TEMP


## Seconds of engine start/warm-up before driving (frost lengthens it; a warm engine starts fast).
func start_delay(v: Vehicle, vil: Villager = null) -> float:
	var cold := maxf(0.0, -temperature())
	var base := VehicleDefs.START_BASE + cold * VehicleDefs.START_PER_DEG * float(VehicleDefs.def(v.type)["cold"])
	var skill := vil.skill(VehicleDefs.DRIVE) if vil != null else 0.0
	return minf(base, VehicleDefs.START_MAX) * (1.0 - v.warm) * (1.0 - VehicleDefs.START_SKILL_RELIEF * skill)


func refuel(v: Vehicle, litres: float) -> void:
	v.fuel = clampf(v.fuel + litres, 0.0, v.tank())  # step 20 hook (fuel chains)


# ---------- terrain / speed ----------

func cell_idx(p: Vector3) -> int:
	var c := world.cell_of(p.x, p.z)
	return c.y * world.size + c.x


func slip_level(v: Vehicle, idx: int) -> float:
	var mud := mud_override
	if mud < 0.0:
		mud = weather.vehicle_stuck_multiplier() if weather != null else (seasons.mud_level() if seasons != null else 0.0)
	var snow := snow_override
	if snow < 0.0:
		snow = seasons.snow_cover() if seasons != null else 0.0
	var d := VehicleDefs.def(v.type)
	var s := (mud * (1.0 - float(d["mud"])) + snow * (1.0 - float(d["snow"]))) * (1.0 + VehicleDefs.LOAD_SLIP * v.load_frac())
	if trails.is_road(idx):
		s *= 1.0 - VehicleDefs.ROAD_SLIP_RELIEF
	else:
		s *= 1.0 - VehicleDefs.RUT_SLIP_RELIEF * trails.rut_level(idx)
	return clampf(s, 0.0, 1.0)


## Speed (m/s) of a vehicle on a cell with a driver.
func speed_at(v: Vehicle, idx: int, vil: Villager) -> float:
	var base := float(VehicleDefs.def(v.type)["speed"]) * driver_speed_mult(vil)
	var sp := base * (1.0 - VehicleDefs.LOAD_SPEED_LOSS * v.load_frac()) * trails.vehicle_mult(idx) * (1.0 - VehicleDefs.SLIP_SPEED_LOSS * slip_level(v, idx))
	return maxf(sp, base * VehicleDefs.MIN_SPEED_FRAC)


## Walk speed multiplier from footpaths at a position.
func walk_mult_at(p: Vector3) -> float:
	return trails.walk_mult(cell_idx(p))


## Villager walked (called every tick with his position): footpaths form from frequent walking.
func note_walk(vid: int, p: Vector3) -> void:
	var i := cell_idx(p)
	if _foot_last.get(vid, -1) != i:
		_foot_last[vid] = i
		trails.add_foot(i)


# ---------- missions ----------

func is_reserved(key: String) -> bool:
	for v: Vehicle in vehicles.values():
		if v.mission.get("jobkey", "") == key:
			return true
	return false


func _field_claimed(idx: int) -> bool:
	var key := "fd:%d" % idx
	for vil: Villager in villagers.villagers.values():
		if vil.task.get("key", "") == key:
			return true
	return is_reserved(key)


func plan(v: Vehicle) -> Dictionary:
	match VehicleDefs.role(v.type):
		&"haul":
			return _plan_haul(v)
		&"plow":
			return _plan_field(&"plow")
		&"harvest":
			return _plan_field(&"harvest")
		&"assist":
			return _plan_assist(v)
	return {}


func _fill(s: Storage) -> float:
	return float(s.used()) / float(maxi(1, s.capacity))


func _plan_haul(v: Vehicle) -> Dictionary:
	if economy.storages.size() < 2:
		return {}
	var src: Storage = null
	var dst: Storage = null
	for s in economy.storages:
		if src == null or _fill(s) > _fill(src):
			src = s
		if s.free_space() > 0 and (dst == null or _fill(s) < _fill(dst)):
			dst = s
	if src == null or dst == null or src == dst or _fill(src) - _fill(dst) < VehicleDefs.HAUL_MIN_IMBALANCE:
		return {}
	var best: StringName = &""
	for r in src.contents:
		if ResourceDefs.is_warehouse_stockable(r) and (best == &"" or src.amount(r) > src.amount(best)):
			best = r
	if best == &"":
		return {}
	var n := mini(mini(VehicleDefs.capacity_units(v.type, best), src.amount(best)), dst.free_space())
	if n < 1:
		return {}
	return {"kind": &"haul", "phase": &"to_src", "res": best, "n": n, "src": src.id, "dst": dst.id, "work": 0.0}


func _plan_field(action: StringName) -> Dictionary:
	if food == null or construction.build_speed_multiplier <= 0.0:
		return {}
	var keys := food.fields.keys()
	keys.sort()
	for i in keys:
		if food.field_action(i) == action and not _field_claimed(i):
			return {"kind": &"field", "phase": &"to_field", "idx": i, "action": action, "jobkey": "fd:%d" % i, "work": 0.0}
	return {}


func _site_candidates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in construction.buildings:
		var b: Building = construction.buildings[id]
		if not b.is_done() and b.stage_paid and b.blocked == &"":
			out.append({"skey": "b:%d" % id, "skind": &"build", "target": id, "pos": b.position})
	for rid in construction.open_dismantles():
		out.append({"skey": "d:%d" % rid, "skind": &"dismantle", "target": rid, "pos": construction.ruins[rid]["pos"]})
	for idx in trails.marks:
		out.append({"skey": "rd:%d" % idx, "skind": &"road", "target": idx, "pos": world.cell_center(idx % world.size, idx / world.size)})
	return out


func _plan_assist(v: Vehicle) -> Dictionary:
	if construction.build_speed_multiplier <= 0.0:
		return {}
	var site: Dictionary = VehicleDefs.def(v.type).get("site", {})
	var best := {}
	var bd := INF
	for c in _site_candidates():
		if float(site.get(c["skind"], 1.0)) <= 1.0:
			continue
		var taken := false
		for o: Vehicle in vehicles.values():
			if o != v and o.type == v.type and o.mission.get("skey", "") == c["skey"]:
				taken = true
		if taken:
			continue
		var d: float = Vector2(c["pos"].x - v.pos.x, c["pos"].z - v.pos.z).length()
		if d < bd:
			bd = d
			best = c
	if best.is_empty():
		return {}
	return {"kind": &"assist", "phase": &"to_site", "skey": best["skey"], "skind": best["skind"], "target": best["target"], "pos": best["pos"], "time": 0.0}


func _site_open(skind: StringName, target: int) -> bool:
	match skind:
		&"build":
			var b := construction.get_building(target)
			return b != null and not b.is_done()
		&"dismantle":
			return construction.open_dismantles().has(target)
		&"road":
			return trails.marks.has(target)
	return false


## Work multiplier of working machines at a site (excavator/bulldozer/crane).
func site_multiplier(skind: StringName, target: int) -> float:
	var m := 1.0
	for v: Vehicle in vehicles.values():
		if v.mission.get("kind", &"") == &"assist" and v.mission.get("phase", &"") == &"work" and v.mission.get("skind", &"") == skind and int(v.mission.get("target", -1)) == target:
			m *= float((VehicleDefs.def(v.type).get("site", {}) as Dictionary).get(skind, 1.0))
	return minf(m, VehicleDefs.MAX_SITE_MULT)


## Demand: does this vehicle have anything to do (a driver is worth sending)?
func has_demand(v: Vehicle) -> bool:
	return not plan(v).is_empty()


## Driving jobs for VillagerSystem: a free drivable vehicle with demand, or one with a driver (resume).
func jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in vehicles:
		var v: Vehicle = vehicles[id]
		if not is_drivable(v):
			continue
		if v.driver_id == 0 and not has_demand(v):
			continue
		out.append({"key": "veh:%d" % id, "cat": VehicleDefs.DRIVE, "kind": &"drive", "target": id, "pos": v.pos,
			"only": v.driver_id if v.driver_id != 0 else v.assigned_driver, "vehicle": v})
	return out


func board(vil: Villager, v: Vehicle) -> bool:
	if v.driver_id != 0 and v.driver_id != vil.id:
		return false
	if v.driver_id == vil.id and not v.mission.is_empty():
		return true  # resume after load
	var m := plan(v)
	if m.is_empty():
		return false
	v.driver_id = vil.id
	v.chain = 0
	m["next"] = m["phase"]
	m["phase"] = &"warmup"
	m["wait"] = start_delay(v, vil)
	v.mission = m
	return true


func release(v: Vehicle) -> void:
	if v == null:
		return
	if v.cargo_n > 0:
		economy.deposit(v.cargo_res, v.cargo_n)
		v.cargo_n = 0
	v.driver_id = 0
	v.mission = {}
	v.path.clear()
	v.moving = false


## Called by VillagerSystem each tick while the villager is the driver.
func drive_tick(vil: Villager, t: Dictionary, dt: float) -> int:
	var v := get_vehicle(int(t["target"]))
	if v == null or v.driver_id != vil.id:
		return Res.FAILED
	var left := dt
	var res := Res.ONGOING
	while left > 0.0 and res == Res.ONGOING:
		var step := minf(left, 0.5)
		left -= step
		res = _mission_step(v, vil, step)
	vil.pos = v.pos
	vil.facing = v.facing
	vil.moving = v.moving
	if res != Res.ONGOING:
		release(v)
	return res


func _mission_step(v: Vehicle, vil: Villager, dt: float) -> int:
	if not is_drivable(v):
		return Res.FAILED
	var m := v.mission
	if m.is_empty():
		return Res.DONE
	villagers.train(vil, VehicleDefs.DRIVE, dt)
	v.warm = 1.0 if m["phase"] != &"warmup" else v.warm
	match m["phase"]:
		&"warmup":
			m["wait"] = float(m["wait"]) - dt
			v.warm = clampf(1.0 - maxf(0.0, float(m["wait"])) / maxf(0.001, start_delay_full(v)), 0.0, 1.0)
			if m["wait"] <= 0.0:
				v.warm = 1.0
				m["phase"] = m["next"]
		&"to_src", &"to_dst":
			var s := economy.get_storage(int(m["src"] if m["phase"] == &"to_src" else m["dst"]))
			if s == null:
				return Res.FAILED
			var g := _drive_to(v, vil, s.position, VehicleDefs.ARRIVE_RADIUS, dt)
			if g == Go.BLOCKED:
				return Res.FAILED
			if g == Go.ARRIVED:
				m["phase"] = &"load" if m["phase"] == &"to_src" else &"unload"
				m["work"] = 0.0
		&"load":
			m["work"] = float(m["work"]) + dt
			if m["work"] >= VehicleDefs.LOAD_TIME:
				var s := economy.get_storage(int(m["src"]))
				var n := s.remove(m["res"], int(m["n"])) if s != null else 0
				if n <= 0:
					return Res.FAILED
				v.cargo_res = m["res"]
				v.cargo_n = n
				m["phase"] = &"to_dst"
		&"unload":
			m["work"] = float(m["work"]) + dt
			if m["work"] >= VehicleDefs.UNLOAD_TIME:
				var s := economy.get_storage(int(m["dst"]))
				var put := s.add(v.cargo_res, v.cargo_n) if s != null else 0
				var rest := v.cargo_n - put
				if rest > 0:
					rest -= economy.deposit(v.cargo_res, rest)
				v.cargo_n = 0
				economy._changed()
				return _next(v, vil)
		&"to_field":
			var c := world.cell_center(int(m["idx"]) % world.size, int(m["idx"]) / world.size)
			var g := _drive_to(v, vil, c, VehicleDefs.FIELD_RADIUS, dt)
			if g == Go.BLOCKED:
				return Res.FAILED
			if g == Go.ARRIVED:
				m["phase"] = &"field_work"
		&"field_work":
			if food == null or food.field_action(int(m["idx"])) != m["action"]:
				return _next(v, vil)
			m["work"] = float(m["work"]) + villagers.work_rate(vil, TaskDefs.FIELD) * float(VehicleDefs.def(v.type)["work"]) * dt
			_burn_work(v, dt)
			if m["work"] >= food.work_need(&"field", int(m["idx"])):
				var r := food.finish(&"field", int(m["idx"]))
				if r.is_empty():
					return _next(v, vil)
				v.cargo_res = r["res"]
				v.cargo_n = int(r["n"])
				m["phase"] = &"to_store"
				m["store"] = villagers._nearest_storage_free(v.pos)
		&"to_store":
			var s := economy.get_storage(int(m.get("store", 0)))
			if s == null:
				s = economy.get_storage(villagers._nearest_storage_free(v.pos))
			if s == null:
				return Res.FAILED
			var g := _drive_to(v, vil, s.position, VehicleDefs.ARRIVE_RADIUS, dt)
			if g == Go.BLOCKED:
				return Res.FAILED
			if g == Go.ARRIVED:
				var left := v.cargo_n - economy.deposit(v.cargo_res, v.cargo_n)
				v.cargo_n = left  # storages full: keep the load, wait for room (release() returns what fits)
				if left <= 0:
					return _next(v, vil)
				return Res.FAILED
		&"to_site":
			var g := _drive_to(v, vil, m["pos"], VehicleDefs.SITE_RADIUS, dt)
			if g == Go.BLOCKED:
				return Res.FAILED
			if g == Go.ARRIVED:
				m["phase"] = &"work"
		&"work":
			m["time"] = float(m["time"]) + dt
			_burn_work(v, dt)
			if m["time"] >= VehicleDefs.ASSIST_MAX_TIME or not _site_open(m["skind"], int(m["target"])):
				return Res.DONE
	return Res.ONGOING


func start_delay_full(v: Vehicle) -> float:
	var cold := maxf(0.0, -temperature())
	return maxf(0.001, minf(VehicleDefs.START_BASE + cold * VehicleDefs.START_PER_DEG * float(VehicleDefs.def(v.type)["cold"]), VehicleDefs.START_MAX))


## Mission finished: chain a new one without re-boarding (up to MAX_CHAIN), else done.
func _next(v: Vehicle, _vil: Villager) -> int:
	v.chain += 1
	if v.chain >= VehicleDefs.MAX_CHAIN:
		return Res.DONE
	var m := plan(v)
	if m.is_empty():
		return Res.DONE
	v.mission = m
	return Res.ONGOING


func _burn_work(v: Vehicle, dt: float) -> void:
	v.fuel = maxf(0.0, v.fuel - float(VehicleDefs.def(v.type)["work_fuel"]) * dt)


## Moves along the path: speed by terrain/load/driver, fuel per km, slip -> stuck, ruts form.
func _drive_to(v: Vehicle, vil: Villager, goal: Vector3, radius: float, dt: float) -> int:
	var g := pf.nearest_passable(goal)
	if Vector2(goal.x - v.pos.x, goal.z - v.pos.z).length() <= radius or Vector2(g.x - v.pos.x, g.z - v.pos.z).length() <= 1.0:
		v.path.clear()
		v.moving = false
		return Go.ARRIVED
	if v.stuck_left > 0.0:
		v.stuck_left -= dt * (1.0 + vil.skill(VehicleDefs.DRIVE))
		v.moving = false
		return Go.MOVING
	var gc := world.cell_of(g.x, g.z)
	if v.path.is_empty() or v.path_goal != gc:
		if not pf.is_passable(world.cell_of(v.pos.x, v.pos.z)):
			v.pos = pf.nearest_passable(v.pos)
		v.path = pf.find_path(v.pos, g)
		v.path_goal = gc
		if v.path.is_empty():
			return Go.BLOCKED
	var idx := cell_idx(v.pos)
	var budget := speed_at(v, idx, vil) * dt
	var moved := 0.0
	v.moving = false
	while budget > 0.0 and not v.path.is_empty():
		var tp := v.path[0]
		var d := Vector2(tp.x - v.pos.x, tp.z - v.pos.z)
		var l := d.length()
		var use := minf(l, budget)
		if l > 0.001:
			v.facing = atan2(d.x, d.y)
			v.pos.x += d.x / l * use
			v.pos.z += d.y / l * use
		if l <= budget:
			v.path.pop_front()
		budget -= use
		moved += use
		v.moving = true
	v.pos.y = world.height_at(v.pos.x, v.pos.z)
	_after_move(v, idx, moved)
	return Go.MOVING


func _after_move(v: Vehicle, from_idx: int, dist: float) -> void:
	if dist <= 0.0:
		return
	v.odometer += dist
	v.fuel = maxf(0.0, v.fuel - dist / 1000.0 * float(VehicleDefs.def(v.type)["fuel_km"]) * (1.0 + VehicleDefs.LOAD_FUEL * v.load_frac()))
	var i := cell_idx(v.pos)
	if i != from_idx:
		trails.add_rut(i)
	v.stuck_acc += dist * slip_level(v, i) * VehicleDefs.STUCK_PER_M
	if v.stuck_acc >= 1.0:
		v.stuck_acc = 0.0
		v.stuck_left = VehicleDefs.STUCK_TIME


# ---------- roads ----------

func road_cells_in_brush(center: Vector3, radius: float, circle: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c := world.cell_of(center.x, center.z)
	var r := int(ceil(radius / world.cell_size))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cc := c + Vector2i(dx, dz)
			if cc.x < 0 or cc.y < 0 or cc.x >= world.size or cc.y >= world.size:
				continue
			if circle and Vector2(dx, dz).length() * world.cell_size > radius:
				continue
			var i := cc.y * world.size + cc.x
			if trails.roads.has(i) or trails.marks.has(i) or not pf.is_passable(cc):
				continue
			out.append(cc)
	return out


## Marks road cells (cost is paid per cell from storages). Returns how many were marked.
func designate_road(cells: Array[Vector2i]) -> int:
	var n := 0
	for c in cells:
		var i := c.y * world.size + c.x
		if trails.roads.has(i) or trails.marks.has(i):
			continue
		if not economy.consume(VehicleDefs.ROAD_COST):
			break
		trails.marks[i] = 0.0
		n += 1
	if n > 0:
		_emit()
	return n


func add_road_work(idx: int, amount: float) -> void:
	if not trails.marks.has(idx):
		return
	trails.marks[idx] = float(trails.marks[idx]) + amount
	if trails.marks[idx] >= VehicleDefs.ROAD_WORK:
		trails.build_road(idx)
		_emit()


## Road jobs for builders (category BUILD).
func road_jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var keys := trails.marks.keys()
	keys.sort()
	for i in keys:
		out.append({"key": "rd:%d" % i, "cat": TaskDefs.BUILD, "kind": &"road", "target": i, "tcat": TaskDefs.BUILD,
			"pos": world.cell_center(i % world.size, i / world.size)})
		if out.size() >= VehicleDefs.ROAD_JOB_CAP:
			break
	return out


# ---------- tick ----------

func tick(sim: Simulation, dt: float) -> void:
	_sim = sim
	var day := sim.clock.day_seconds()
	trails.decay(dt / day)
	for id in vehicles:
		var v: Vehicle = vehicles[id]
		if v.driver_id != 0 and villagers.get_villager(v.driver_id) == null:
			release(v)  # driver gone
		if v.driver_id == 0:
			v.warm = maxf(0.0, v.warm - dt / VehicleDefs.COOL_TIME)
			v.moving = false


# ---------- save ----------

func get_save_key() -> StringName:
	return &"vehicles"


static func _mission_out(m: Dictionary) -> Dictionary:
	var o := {}
	for k in m:
		var x = m[k]
		if x is StringName:
			o[String(k)] = {"sn": String(x)}
		elif x is Vector3:
			o[String(k)] = {"v3": [x.x, x.y, x.z]}
		else:
			o[String(k)] = x
	return o


static func _mission_in(d: Dictionary) -> Dictionary:
	var m := {}
	for k in d:
		var x = d[k]
		if x is Dictionary and x.has("sn"):
			m[StringName(String(k))] = StringName(String(x["sn"]))
		elif x is Dictionary and x.has("v3"):
			m[StringName(String(k))] = Vector3(x["v3"][0], x["v3"][1], x["v3"][2])
		else:
			m[StringName(String(k))] = x
	return m


func save_state() -> Dictionary:
	var list := []
	for id in vehicles:
		var v: Vehicle = vehicles[id]
		list.append({"id": v.id, "type": String(v.type), "origin": String(v.origin), "cond": v.condition, "pos": [v.pos.x, v.pos.y, v.pos.z],
			"facing": v.facing, "fuel": v.fuel, "driver": v.driver_id, "assigned": v.assigned_driver, "cargo_res": String(v.cargo_res),
			"cargo_n": v.cargo_n, "warm": v.warm, "stuck": v.stuck_left, "odo": v.odometer, "chain": v.chain, "mission": _mission_out(v.mission)})
	return {"next_id": _next_id, "vehicles": list, "trails": trails.save_state()}


func load_state(d: Dictionary) -> void:
	for id in vehicles.keys():
		if production != null:
			production.unregister_repairable(vehicles[id].repair_id)
	vehicles.clear()
	_next_id = SaveManager.to_int(d.get("next_id"), 1)
	if d.get("trails") is Dictionary:
		trails.load_state(d["trails"])
	for e in d.get("vehicles", []):
		if not e is Dictionary:
			continue
		var type := StringName(String(e.get("type", "truck")))
		if not VehicleDefs.DEFS.has(type):
			continue
		var v := Vehicle.new(SaveManager.to_int(e.get("id"), 0), type, float(e.get("cond", 1.0)))
		v.origin = StringName(String(e.get("origin", "found")))
		var p: Array = e.get("pos", [0, 0, 0])
		v.pos = Vector3(p[0], p[1], p[2])
		v.facing = float(e.get("facing", 0.0))
		v.fuel = float(e.get("fuel", 0.0))
		v.driver_id = SaveManager.to_int(e.get("driver"), 0)
		v.assigned_driver = SaveManager.to_int(e.get("assigned"), 0)
		v.cargo_res = StringName(String(e.get("cargo_res", "")))
		v.cargo_n = SaveManager.to_int(e.get("cargo_n"), 0)
		v.warm = float(e.get("warm", 0.0))
		v.stuck_left = float(e.get("stuck", 0.0))
		v.odometer = float(e.get("odo", 0.0))
		v.chain = SaveManager.to_int(e.get("chain"), 0)
		if e.get("mission") is Dictionary:
			v.mission = _mission_in(e["mission"])
		vehicles[v.id] = v
		_next_id = maxi(_next_id, v.id + 1)
		if production != null:
			production.register_repairable(v)
	_emit()
