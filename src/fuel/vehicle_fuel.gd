class_name VehicleFuel
extends RefCounted
## Step 20: fuel-type aware refuelling (physical trip to a storage), conversions and upgrades done at the workshop.
## Design: design/gdd/fuel-and-upgrades.md. Owned by VehicleSystem (`vs.fuelx`); all numbers in FuelDefs.

var vs: VehicleSystem


func _init(vs_in: VehicleSystem) -> void:
	vs = vs_in


# ---------- refuelling ----------

## Litre-equivalents still free in the tank/hopper.
func free_litres(v: Vehicle) -> float:
	return maxf(0.0, v.tank() - v.fuel)


## Puts up to `units` of `res` into the tank. Wrong fuel for this engine -> 0 (refused, nothing taken).
## `source` (Storage) is debited; null = free fuel (debug/trade hook). Returns the units used.
func refuel_with(v: Vehicle, res: StringName, units: int, source: Storage = null) -> int:
	if units <= 0 or not v.accepts_fuel(res):
		return 0
	var lpu := FuelDefs.litres_per_unit(res)
	var n := mini(units, int(ceil(free_litres(v) / lpu - 0.0001)))
	if source != null:
		n = mini(n, source.amount(res))
	if n <= 0:
		return 0
	if source != null:
		source.remove(res, n)
	vs.refuel(v, float(n) * lpu)
	return n


## First accepted fuel the storage holds (order of the accepted list), else &"".
func fuel_in(v: Vehicle, s: Storage) -> StringName:
	for r in v.accepted_fuels():
		if s.amount(r) > 0:
			return r
	return &""


## Nearest storage holding a fuel this vehicle can burn: {store, res}, empty if none.
func find_depot(v: Vehicle) -> Dictionary:
	var best := {}
	var bd := INF
	for s: Storage in vs.economy.storages:
		var r := fuel_in(v, s)
		if r == &"":
			continue
		var d := Vector2(s.position.x - v.pos.x, s.position.z - v.pos.z).length()
		if d < bd:
			bd = d
			best = {"store": s.id, "res": r}
	return best


## Refuel trip: tank under REFUEL_BELOW and a depot with the right fuel exists.
func plan_refuel(v: Vehicle) -> Dictionary:
	if v.fuel >= v.tank() * FuelDefs.REFUEL_BELOW:
		return {}
	var dep := find_depot(v)
	if dep.is_empty():
		return {}
	return {"kind": &"refuel", "phase": &"to_depot", "store": dep["store"], "res": dep["res"], "work": 0.0}


## An empty repaired vehicle is pushed to the depot (decision: no canisters, see GDD).
func can_roll_to_depot(v: Vehicle) -> bool:
	return v.is_repaired() and v.fuel <= 0.0 and not plan_refuel(v).is_empty()


## Mission phases to_depot / refuel (called from VehicleSystem._mission_step).
func step(v: Vehicle, vil: Villager, dt: float) -> int:
	var m := v.mission
	var s := vs.economy.get_storage(int(m["store"]))
	if s == null or fuel_in(v, s) == &"":
		return VehicleSystem.Res.FAILED
	if m["phase"] == &"to_depot":
		var g := vs._drive_to(v, vil, s.position, VehicleDefs.ARRIVE_RADIUS, dt)
		if g == VehicleSystem.Go.BLOCKED:
			return VehicleSystem.Res.FAILED
		if g == VehicleSystem.Go.ARRIVED:
			m["phase"] = &"refuel"
			m["work"] = 0.0
		return VehicleSystem.Res.ONGOING
	m["work"] = float(m["work"]) + dt
	if m["work"] < FuelDefs.REFUEL_TIME:
		return VehicleSystem.Res.ONGOING
	if refuel_with(v, fuel_in(v, s), 1000, s) <= 0:
		return VehicleSystem.Res.FAILED
	vs.economy._changed()
	return vs._next(v, vil)


# ---------- conversions and upgrades ----------

func workshop_id() -> int:
	if vs.construction == null:
		return -1
	for id in vs.construction.buildings:
		var b: Building = vs.construction.buildings[id]
		if b.type == Recipes.REPAIR_BUILDING and b.is_done():
			return id
	return -1


func is_busy(v: Vehicle) -> bool:
	return v.mod_job != null and not v.mod_job.done


## Can this mod start now (not installed, nothing else pending, valid kind)?
func can_start(v: Vehicle, kind: StringName) -> bool:
	if is_busy(v):
		return false
	if FuelDefs.CONVERSION_DEFS.has(kind):
		return v.conversion == FuelDefs.NO_CONVERSION
	return FuelDefs.UPGRADE_DEFS.has(kind) and not v.has_upgrade(kind)


## Queues a conversion/upgrade at the workshop. false: not allowed or no workshop.
func start_mod(v: Vehicle, kind: StringName) -> bool:
	var wid := workshop_id()
	if v == null or wid < 0 or not can_start(v, kind):
		return false
	var job := _make_job(v, kind, 0.0)
	if vs.production == null or not vs.production.queue_repair(wid, job.repair_id):
		if vs.production != null:
			vs.production.unregister_repairable(job.repair_id)
		v.mod_job = null
		return false
	vs._emit()
	return true


func _make_job(v: Vehicle, kind: StringName, progress: float) -> VehicleModJob:
	cleanup(v)
	var job := VehicleModJob.new(v, kind, progress)
	job.on_done = _finish
	v.mod_job = job
	if vs.production != null:
		vs.production.register_repairable(job)
	return job


func _finish(job: VehicleModJob) -> void:
	var v := job.vehicle
	job.done = true
	if job.is_conversion():
		v.conversion = job.kind
		v.fuel = 0.0 if job.kind == FuelDefs.GASGEN else minf(v.fuel, v.tank())  # old petrol/diesel cannot feed a gas generator
	elif not v.upgrades.has(job.kind):
		v.upgrades.append(job.kind)
	vs._emit()


## Drops a finished job from the workshop registry (not inside the repair callback: the queue is mid-update).
func cleanup(v: Vehicle) -> void:
	if v.mod_job != null and v.mod_job.done:
		if vs.production != null:
			vs.production.unregister_repairable(v.mod_job.repair_id)
		v.mod_job = null


## UI: vague progress word for the pending job.
func job_text(v: Vehicle) -> String:
	if not is_busy(v):
		return ""
	return "%s: %s" % ["Переделка" if v.mod_job.is_conversion() else "Доработка", FuelDefs.mod_name(v.mod_job.kind)]


# ---------- save ----------

func save_vehicle(v: Vehicle) -> Dictionary:
	var d := {"conv": String(v.conversion), "up": v.upgrades.map(func(u: StringName) -> String: return String(u))}
	if is_busy(v):
		d["job"] = {"kind": String(v.mod_job.kind), "prog": v.mod_job.condition}
	return d


## Restores conversion/upgrades/pending job (call BEFORE VehicleSystem._register so the job gets registered).
func load_vehicle(v: Vehicle, d: Variant) -> void:
	if not (d is Dictionary):
		return
	var conv := StringName(String(d.get("conv", "")))
	v.conversion = conv if FuelDefs.CONVERSION_DEFS.has(conv) else FuelDefs.NO_CONVERSION
	v.upgrades.clear()
	for u in d.get("up", []):
		var k := StringName(String(u))
		if FuelDefs.UPGRADE_DEFS.has(k) and not v.upgrades.has(k):
			v.upgrades.append(k)
	var j = d.get("job")
	if j is Dictionary:
		var kind := StringName(String(j.get("kind", "")))
		if not FuelDefs.mod_def(kind).is_empty():
			var job := VehicleModJob.new(v, kind, float(j.get("prog", 0.0)))
			job.on_done = _finish
			v.mod_job = job
