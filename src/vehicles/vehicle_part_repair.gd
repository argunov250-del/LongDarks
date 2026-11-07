class_name VehiclePartRepair
extends Repairable
## Repairable view of ONE part of a vehicle (workshop queue entry «Бурун-5: мотор»).
## The vehicle's `parts` dictionary is the source of truth; `condition` is only a mirror for saving.
## Design: design/gdd/vehicles.md «Износ и поломки».

var vehicle: Vehicle
var part: StringName


func _init(vehicle_in: Vehicle, part_in: StringName) -> void:
	vehicle = vehicle_in
	part = part_in
	super._init(StringName("vehicle_%d:%s" % [vehicle_in.id, String(part_in)]), vehicle_in.parts[part_in])
	step_cost = (VehicleDefs.PART_REPAIR_COST[part_in] as Dictionary).duplicate()
	step_gain = VehicleDefs.REPAIR_GAIN


func needs_repair() -> bool:
	return float(vehicle.parts[part]) < 1.0 - 0.000001


func apply_repair(gain: float) -> void:
	vehicle.set_part(part, float(vehicle.parts[part]) + gain)
