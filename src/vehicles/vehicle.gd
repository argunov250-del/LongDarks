class_name Vehicle
extends Repairable
## One vehicle (data only; behaviour in VehicleSystem). Implements the Repairable contract:
## the workshop repairs it via ProductionSystem.queue_repair(workshop, repair_id).

var id: int = 0
var type: StringName = &"truck"
var display_name := ""
var origin: StringName = &"found"       # found | ruins | trade
var pos := Vector3.ZERO
var facing := 0.0
var fuel := 0.0                         # litres
var driver_id: int = 0
var assigned_driver: int = 0            # player-assigned driver role (0 — any)
var cargo_res: StringName = &""
var cargo_n: int = 0
var warm := 0.0                         # engine warmth 0..1
var stuck_left := 0.0                   # s still stuck in mud/snow
var stuck_acc := 0.0
var odometer := 0.0                     # m
var chain := 0
var mission: Dictionary = {}
var path: Array[Vector3] = []
var path_goal := Vector2i(-1, -1)
var moving := false
## Step 19: per-part condition 0..1 (engine/tires/battery). `condition` (Repairable) mirrors the worst part.
var parts: Dictionary = {}
var serviceable := false                # false = abandoned wreck: needs repair up to DRIVABLE_CONDITION first
var accident_rolls := 0                 # deterministic accident roll counter
var start_count := 0                    # deterministic start-failure roll counter
var broken_notified := false
var part_repairs: Dictionary = {}       # part -> VehiclePartRepair
var field_paid := false                 # the current field step has been paid for
var field_work := 0.0                   # progress of the current field-repair step (saved)
## Step 20 (design/gdd/fuel-and-upgrades.md): conversion (&"" | biofuel | gasgen), upgrades, pending workshop job.
var conversion: StringName = FuelDefs.NO_CONVERSION
var upgrades: Array[StringName] = []
var mod_job: VehicleModJob = null
## Step 21 (design/gdd/manual-driving.md): the player is at the wheel (not saved; AI must leave the vehicle alone).
var player_driving := false


func _init(id_in: int = 0, type_in: StringName = &"truck", condition_in: float = 1.0) -> void:
	super._init(StringName("vehicle_%d" % id_in), condition_in)
	id = id_in
	type = type_in
	for part in VehicleDefs.PARTS:
		parts[part] = condition
	serviceable = condition >= VehicleDefs.DRIVABLE_CONDITION
	var d := VehicleDefs.def(type_in)
	step_cost = (d["repair_cost"] as Dictionary).duplicate()
	step_gain = VehicleDefs.REPAIR_GAIN
	display_name = "%s «%s»" % [d["name"], VehicleDefs.MODEL_NAMES[type_in]]


## Tank litres; a gas generator only has a small wood hopper.
func tank() -> float:
	var t := float(VehicleDefs.def(type)["tank"])
	return t * FuelDefs.GASGEN_HOPPER if conversion == FuelDefs.GASGEN else t


func engine() -> StringName:
	return FuelDefs.engine_of(type)


func accepted_fuels() -> Array[StringName]:
	return FuelDefs.accepted(engine(), conversion)


func accepts_fuel(res: StringName) -> bool:
	return FuelDefs.accepts(engine(), conversion, res)


func has_upgrade(kind: StringName) -> bool:
	return upgrades.has(kind)


## Engine speed multiplier of the fuel system (gas generator is weaker).
func engine_speed_mult() -> float:
	return FuelDefs.GASGEN_SPEED if conversion == FuelDefs.GASGEN else 1.0


func fuel_use_mult() -> float:
	return FuelDefs.GASGEN_FUEL_MULT if conversion == FuelDefs.GASGEN else 1.0


## Wreck (never repaired): all parts >= DRIVABLE_CONDITION. In service: no part is broken.
func is_repaired() -> bool:
	if serviceable:
		return min_part() >= VehicleDefs.PART_BROKEN_BELOW
	return min_part() >= VehicleDefs.DRIVABLE_CONDITION


func min_part() -> float:
	var m := 1.0
	for part in VehicleDefs.PARTS:
		m = minf(m, float(parts[part]))
	return m


## Worst part (lowest condition; ties by PARTS order).
func worst_part() -> StringName:
	var w: StringName = VehicleDefs.PARTS[0]
	for part in VehicleDefs.PARTS:
		if float(parts[part]) < float(parts[w]):
			w = part
	return w


func broken_parts() -> Array[StringName]:
	var out: Array[StringName] = []
	for part in VehicleDefs.PARTS:
		if float(parts[part]) < VehicleDefs.PART_BROKEN_BELOW:
			out.append(part)
	return out


func set_part(part: StringName, value: float) -> void:
	parts[part] = clampf(value, 0.0, 1.0)
	sync_condition()
	if min_part() >= VehicleDefs.DRIVABLE_CONDITION:
		serviceable = true
	if broken_parts().is_empty():
		broken_notified = false


## Mirrors the worst part into Repairable.condition (and part repairables) for saving/queue checks.
func sync_condition() -> void:
	condition = min_part()
	for part in part_repairs:
		(part_repairs[part] as Repairable).condition = float(parts[part])


## Whole-vehicle workshop repair: the step goes to the worst part.
func apply_repair(gain: float) -> void:
	set_part(worst_part(), float(parts[worst_part()]) + gain)
	on_condition_changed()


func cargo_kg() -> float:
	return float(cargo_n) * VehicleDefs.unit_kg(cargo_res) if cargo_n > 0 else 0.0


## Load 0..1 by weight.
func load_frac() -> float:
	var mk := float(VehicleDefs.def(type)["max_kg"])
	return clampf(cargo_kg() / mk, 0.0, 1.0) if mk > 0.0 else 0.0


## Speed multiplier of a limping vehicle (worn engine).
func limp_speed_mult() -> float:
	return lerpf(VehicleDefs.LIMP_SPEED, 1.0, clampf(float(parts[&"engine"]) / VehicleDefs.PART_WORN_BELOW, 0.0, 1.0))


## Extra slip factor of worn tyres (1.0 = fine).
func tire_slip_mult() -> float:
	return 1.0 + VehicleDefs.LIMP_SLIP * (1.0 - clampf(float(parts[&"tires"]) / VehicleDefs.PART_WORN_BELOW, 0.0, 1.0))
