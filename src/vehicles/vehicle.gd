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


func _init(id_in: int = 0, type_in: StringName = &"truck", condition_in: float = 1.0) -> void:
	super._init(StringName("vehicle_%d" % id_in), condition_in)
	id = id_in
	type = type_in
	var d := VehicleDefs.def(type_in)
	step_cost = (d["repair_cost"] as Dictionary).duplicate()
	step_gain = VehicleDefs.REPAIR_GAIN
	display_name = "%s «%s»" % [d["name"], VehicleDefs.MODEL_NAMES[type_in]]


func tank() -> float:
	return float(VehicleDefs.def(type)["tank"])


func is_repaired() -> bool:
	return condition >= VehicleDefs.DRIVABLE_CONDITION


func cargo_kg() -> float:
	return float(cargo_n) * VehicleDefs.unit_kg(cargo_res) if cargo_n > 0 else 0.0


## Load 0..1 by weight.
func load_frac() -> float:
	var mk := float(VehicleDefs.def(type)["max_kg"])
	return clampf(cargo_kg() / mk, 0.0, 1.0) if mk > 0.0 else 0.0


## Step 19 hook: breakdown rate per km (not used yet).
func breakdown_rate(driver_skill: float) -> float:
	return (1.0 - condition) * (1.0 - 0.5 * driver_skill)
